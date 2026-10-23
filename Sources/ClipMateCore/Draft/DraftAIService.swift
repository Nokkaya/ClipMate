import Foundation

/// 负责将 LLM 的理解、草稿生成、关联影响分析及控件发现与本地引擎对接的 AI 门面
public final class DraftAIService {
    private let ai: AIService
    public var isLocalOnlyProvider: () -> Bool = { false }

    public init(ai: AIService, isLocalOnly: (() -> Bool)? = nil) {
        self.ai = ai
        if let isLocalOnly = isLocalOnly {
            self.isLocalOnlyProvider = isLocalOnly
        }
    }

    public var isAvailable: Bool {
        ai.isConfigured && !isLocalOnlyProvider()
    }

    // MARK: - 1. 结构化理解材料并生成草稿 (Phase 1)

    public struct DraftAIResult: Sendable {
        public let title: String
        public let purpose: DraftPurpose
        public let draftText: String
        public let controls: [DraftGoalControl]
        public let unresolvedItems: [DraftUnresolvedItem]
        public let summary: String
    }

    public func generateDraft(
        sources: [DraftSource],
        purpose: DraftPurpose? = nil
    ) async -> DraftAIResult {
        // 纯本地基础结果（作为高质量底座与回退保障）
        let localDraft = WorkingDraftEngine.createDraft(sources: sources, purpose: purpose)
        guard isAvailable else {
            return DraftAIResult(
                title: localDraft.title,
                purpose: localDraft.purpose,
                draftText: localDraft.candidateText ?? "",
                controls: localDraft.controls,
                unresolvedItems: localDraft.unresolvedItems,
                summary: localDraft.changeSummary
            )
        }

        let combinedSources = sources.map { "【材料来源：\($0.sourceName)】\n\($0.content)" }.joined(separator: "\n\n---\n\n")
        let targetPurposeStr = purpose?.title ?? "自动识别"

        let systemPrompt = """
        你是一个专业的 macOS 剪贴板工作草稿助手。
        根据用户复制的多份碎片材料，理解其事实、需求、限制、冲突与缺失信息，生成一份直接可用的结构化工作草稿。
        要求：
        1. 必须严格依据输入材料，不得凭空编造事实、金额、联系方式或确定上线日期。
        2. 存在不确定事项时，提出最多一个最关键的未决确认问题（unresolved_question）。
        3. 识别1~2个当前内容适用的核心目标或约束控件（controls，如数量调节或硬约束开关）。
        4. 必须输出严格的 JSON 格式，不要多余客套：
        {
          "title": "简短草稿标题（不超过15字）",
          "purpose": "reply|summary|proposal|todo|general",
          "draft_text": "结构化工作草稿正文",
          "controls": [
            {"name": "控件名称", "type": "stepper|constraint", "value": "当前值", "is_hard_constraint": true/false}
          ],
          "unresolved_question": "如果有关键缺失则填写问题，否则为空",
          "summary": "最新变化简述（如：已整理2份材料）"
        }
        """

        let userPrompt = "用户指定用途：\(targetPurposeStr)\n\n输入材料如下：\n\(combinedSources)"

        do {
            let response = try await collectResponse(system: systemPrompt, user: userPrompt)
            if let json = extractJSONObject(from: response) {
                let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? localDraft.title
                let pStr = json["purpose"] as? String ?? ""
                let resolvedPurpose: DraftPurpose
                switch pStr {
                case "reply": resolvedPurpose = .reply
                case "summary": resolvedPurpose = .summary
                case "proposal": resolvedPurpose = .proposal
                case "todo": resolvedPurpose = .todo
                default: resolvedPurpose = purpose ?? localDraft.purpose
                }

                let text = (json["draft_text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? (localDraft.candidateText ?? "")

                var controls = localDraft.controls
                if let ctrlArray = json["controls"] as? [[String: Any]], !ctrlArray.isEmpty {
                    controls = ctrlArray.compactMap { dict -> DraftGoalControl? in
                        guard let name = dict["name"] as? String else { return nil }
                        let typeStr = dict["type"] as? String ?? "constraint"
                        let val = dict["value"] as? String ?? "已开启"
                        let isHard = dict["is_hard_constraint"] as? Bool ?? false
                        let ctrlType: DraftControlType = (typeStr == "stepper") ? .stepper(min: 1, max: 100, step: 1, unit: "", isInteger: true) : .constraintToggle(description: name)
                        return DraftGoalControl(name: name, type: ctrlType, currentValue: val, isHardConstraint: isHard)
                    }
                }

                var unresolved = localDraft.unresolvedItems
                if let q = json["unresolved_question"] as? String, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    unresolved = [DraftUnresolvedItem(question: q, suggestedValues: ["暂未确定", "保持现有安排"], isCritical: true)]
                }

                let summary = (json["summary"] as? String) ?? "已由 AI 综合整理材料"

                return DraftAIResult(
                    title: title.isEmpty ? localDraft.title : title,
                    purpose: resolvedPurpose,
                    draftText: text.isEmpty ? (localDraft.candidateText ?? "") : text,
                    controls: controls.isEmpty ? localDraft.controls : controls,
                    unresolvedItems: unresolved,
                    summary: summary
                )
            }
        } catch {
            // 出错降级返回本地结果
        }

        return DraftAIResult(
            title: localDraft.title,
            purpose: localDraft.purpose,
            draftText: localDraft.candidateText ?? "",
            controls: localDraft.controls,
            unresolvedItems: localDraft.unresolvedItems,
            summary: localDraft.changeSummary
        )
    }

    // MARK: - 2. 跟随复制新材料归属与修改影响评估 (Phase 2)

    public struct AttributionAIResult: Sendable {
        public let relation: DraftAttributionRelation
        public let proposal: DraftRevisionProposal?
        public let summary: String
    }

    public func evaluateAttribution(
        newItemText: String,
        draft: WorkingDraft
    ) async -> AttributionAIResult {
        // 本地快速规则
        let local = WorkingDraftEngine.evaluateAttributionLocally(newItemText: newItemText, draft: draft)
        guard isAvailable else {
            return AttributionAIResult(relation: local.relation, proposal: local.proposal, summary: local.summary)
        }

        let systemPrompt = """
        你是一个 macOS 剪贴板内容归属与关联更新评估引擎。
        用户当前正在进行一份工作草稿，并新复制了一段材料。
        请判断新材料是否属于当前事项，并输出 JSON：
        1. "relation": "addition" (属于当前事项且补充新事实) | "revision" (属于当前事项且修改既有内容/增加限制) | "conflict" (与现有草稿事实直接矛盾) | "irrelevant" (无关材料)
        2. 若属于 revision 或 conflict，请给出关联修改建议 changes：包含 original_snippet（当前草稿中受影响需要替换的原文片段）和 proposed_snippet（建议替换成的新文本）。如果当前草稿没有需要替换的旧文本，仅需追加新要求，则 original_snippet 留空。
        3. 输出格式示例：
        {
          "relation": "revision",
          "title": "新增导出限制并调整演示范围",
          "reason": "客户回复明确暂不要求离线，但导出不可含个人信息",
          "changes": [
            {"original_snippet": "演示需离线支持", "proposed_snippet": "演示阶段暂不要求离线", "reason": "范围调整"},
            {"original_snippet": "导出报告", "proposed_snippet": "导出报告（不包含任何个人信息）", "reason": "隐私保护"}
          ],
          "summary": "新增 1 条限制，影响 2 处内容"
        }
        """

        let baseText = draft.fullDraftText
        let userPrompt = "当前草稿正文：\n\(baseText)\n\n新复制内容：\n\(newItemText)"

        do {
            let response = try await collectResponse(system: systemPrompt, user: userPrompt)
            if let json = extractJSONObject(from: response) {
                let relStr = json["relation"] as? String ?? "irrelevant"
                let relation: DraftAttributionRelation
                switch relStr {
                case "addition": relation = .addition
                case "revision": relation = .revision
                case "conflict": relation = .conflict
                default: relation = .irrelevant
                }

                if relation == .irrelevant {
                    return AttributionAIResult(relation: .irrelevant, proposal: nil, summary: "")
                }

                let title = json["title"] as? String ?? "新信息关联修改"
                let reason = json["reason"] as? String ?? ""
                let summary = json["summary"] as? String ?? "新复制内容影响当前草稿"

                var changes: [DraftTextChange] = []
                if let rawChanges = json["changes"] as? [[String: Any]] {
                    for c in rawChanges {
                        let orig = (c["original_snippet"] as? String) ?? ""
                        let prop = (c["proposed_snippet"] as? String) ?? ""
                        let r = (c["reason"] as? String) ?? ""
                        let ctx = (c["context_hint"] as? String) ?? ""
                        if !prop.isEmpty {
                            changes.append(DraftTextChange(originalSnippet: orig, proposedSnippet: prop, reason: r, contextHint: ctx))
                        }
                    }
                }

                // LLM-R16: 若为 addition 且模型未提供具体 changes，则兜底生成追加项
                if relation == .addition && changes.isEmpty {
                    let change = DraftTextChange(
                        originalSnippet: "",
                        proposedSnippet: "• 补充信息：\(newItemText.trimmingCharacters(in: .whitespacesAndNewlines))",
                        reason: "补充新材料事实",
                        action: .insert
                    )
                    changes.append(change)
                }

                let proposal: DraftRevisionProposal?
                if !changes.isEmpty {
                    proposal = DraftRevisionProposal(
                        title: title,
                        reason: reason,
                        targetVersion: draft.version,
                        changes: changes,
                        relatedSourceIDs: []
                    )
                } else {
                    proposal = nil
                }

                return AttributionAIResult(relation: relation, proposal: proposal, summary: summary)
            }
        } catch {
            // 失败走本地评估
        }

        return AttributionAIResult(relation: local.relation, proposal: local.proposal, summary: local.summary)
    }

    // MARK: - 3. 自然语言一句话修改与关联影响分析 (Phase 3)

    public func proposeRevision(
        instruction: String,
        draft: WorkingDraft
    ) async -> DraftRevisionProposal? {
        guard isAvailable else {
            // 本地简单替换测试
            let change = DraftTextChange(
                originalSnippet: "",
                proposedSnippet: "【修改要求：\(instruction)】",
                reason: instruction,
                action: .insert
            )
            return DraftRevisionProposal(
                title: "本地修改记录",
                reason: instruction,
                targetVersion: draft.version,
                changes: [change]
            )
        }

        let baseText = draft.fullDraftText

        let systemPrompt = """
        你是一个专业的草稿协同修改助手。
        用户对当前草稿输入了一句自然语言修改要求（如“留点余地”、“不要承诺确定上线日期”、“适合一个人完成”等）。
        请理解修改意图，定位当前草稿中所有受影响的段落（包括正文、承诺表述、结尾等相关位置），生成关联修改组。
        要求：
        1. 必须定位草稿中真实存在的 exact original_snippet，不得编造不存在的片段。
        2. 承诺性或结论性表述需要前后一致调整（例如正文取消保证，结尾的致辞保证也需同步调整）。
        3. 必须输出 JSON：
        {
          "title": "取消确定上线日期承诺",
          "reason": "响应用户指令，将绝对保证调整为争取和预估",
          "changes": [
            {
              "original_snippet": "周五必定发布上线",
              "proposed_snippet": "预计周五完成初步交付并视测试情况评估发布",
              "reason": "正文承诺留有余地"
            },
            {
              "original_snippet": "特此保证本周见！",
              "proposed_snippet": "我们将全力推进并及时同步进展！",
              "reason": "结尾致辞同步调整一致"
            }
          ]
        }
        """

        let userPrompt = "当前草稿内容：\n\(baseText)\n\n用户修改指令：\n\(instruction)"

        do {
            let response = try await collectResponse(system: systemPrompt, user: userPrompt)
            if let json = extractJSONObject(from: response) {
                let title = (json["title"] as? String) ?? "指令修改建议：\(instruction)"
                let reason = (json["reason"] as? String) ?? instruction
                var changes: [DraftTextChange] = []
                var allSnippetsFound = true

                if let rawChanges = json["changes"] as? [[String: Any]], !rawChanges.isEmpty {
                    for c in rawChanges {
                        let orig = ((c["original_snippet"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let prop = ((c["proposed_snippet"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let r = (c["reason"] as? String) ?? ""
                        let ctx = (c["context_hint"] as? String) ?? ""

                        if !orig.isEmpty {
                            // LLM-R18: 校验 originalSnippet 确实在草稿中；若有缺失则整组失效
                            if baseText.contains(orig) {
                                changes.append(DraftTextChange(originalSnippet: orig, proposedSnippet: prop, reason: r, action: prop.isEmpty ? .delete : .replace, contextHint: ctx))
                            } else {
                                allSnippetsFound = false
                                break
                            }
                        } else if !prop.isEmpty {
                            changes.append(DraftTextChange(originalSnippet: "", proposedSnippet: prop, reason: r, action: .insert, contextHint: ctx))
                        }
                    }

                    // LLM-R18: 关联修改组必须具备原子完整性。若有任一关键 snippet 不存在，整组废弃，防止局部缺损
                    if allSnippetsFound && !changes.isEmpty {
                        return DraftRevisionProposal(
                            title: title,
                            reason: reason,
                            targetVersion: draft.version,
                            changes: changes
                        )
                    }
                }
            }
        } catch {
            // 出错降级
        }

        return nil
    }

    // MARK: - 3.5 语义目标与偏好控件智能建议 (Phase 4, LLM-R07)

    public func proposeGoalAdjustment(
        draft: WorkingDraft,
        control: DraftGoalControl,
        newValue: String
    ) async -> DraftRevisionProposal? {
        guard isAvailable else { return nil }

        let baseText = draft.fullDraftText
        let systemPrompt = """
        你是一个专业的草稿意图与目标调整助手。
        用户调整了当前草稿的目标/意图控件「\(control.name)」，新设定为「\(newValue)」。
        请根据新的目标，定位当前草稿中所有受影响的表述，生成关联修改组 changes。
        要求：
        1. 必须定位草稿真实存在的 exact original_snippet，不得编造。
        2. 必须输出 JSON 格式：
        {
          "title": "调整\(control.name)为\(newValue)",
          "reason": "契合新的目标设定",
          "changes": [
            {"original_snippet": "...", "proposed_snippet": "...", "reason": "..."}
          ]
        }
        """

        let userPrompt = "当前草稿正文：\n\(baseText)\n\n控件信息：\(control.name) -> \(newValue)"

        do {
            let response = try await collectResponse(system: systemPrompt, user: userPrompt)
            if let json = extractJSONObject(from: response) {
                let title = (json["title"] as? String) ?? "调整\(control.name)：\(newValue)"
                let reason = (json["reason"] as? String) ?? "目标调整"
                var changes: [DraftTextChange] = []
                var allValid = true

                if let rawChanges = json["changes"] as? [[String: Any]], !rawChanges.isEmpty {
                    for c in rawChanges {
                        let orig = ((c["original_snippet"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let prop = ((c["proposed_snippet"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let r = (c["reason"] as? String) ?? ""
                        if !orig.isEmpty {
                            if !baseText.contains(orig) {
                                allValid = false
                                break
                            }
                            changes.append(DraftTextChange(originalSnippet: orig, proposedSnippet: prop, reason: r, action: prop.isEmpty ? .delete : .replace))
                        } else if !prop.isEmpty {
                            changes.append(DraftTextChange(originalSnippet: "", proposedSnippet: prop, reason: r, action: .insert))
                        }
                    }
                    if allValid && !changes.isEmpty {
                        return DraftRevisionProposal(
                            title: title,
                            reason: reason,
                            targetVersion: draft.version,
                            changes: changes
                        )
                    }
                }
            }
        } catch {
        }
        return nil
    }

    // MARK: - 4. 动态信息层级生成 (Phase 5)

    public func generateZoomLevels(
        draft: WorkingDraft
    ) async -> [ZoomLevel: String] {
        let baseText = draft.fullDraftText
        var result: [ZoomLevel: String] = [:]
        result[.full] = baseText

        guard isAvailable else {
            return draft.zoomLevels.isEmpty ? [
                .full: baseText,
                .oneLine: String(baseText.prefix(60))
            ] : draft.zoomLevels
        }

        let systemPrompt = """
        你是一个文本层级压缩专家。根据给定的工作草稿，生成三个层级的结构化压缩：
        1. key_points: 核心要点（保留关键事实、硬约束和数字）
        2. action_items: 结论与执行清单（待办/交付项列表）
        3. one_line: 完整准确的一句话概括（不超过50字）
        要求严格保留原内容中的否定条件、限制和重要约束，不得把建议说成确定决定。
        输出 JSON 格式：
        {
          "key_points": "...",
          "action_items": "...",
          "one_line": "..."
        }
        """

        let userPrompt = "草稿正文：\n\(baseText)"

        do {
            let response = try await collectResponse(system: systemPrompt, user: userPrompt)
            if let json = extractJSONObject(from: response) {
                if let kp = json["key_points"] as? String, !kp.isEmpty {
                    result[.keyPoints] = kp
                }
                if let act = json["action_items"] as? String, !act.isEmpty {
                    result[.actionItems] = act
                }
                if let one = json["one_line"] as? String, !one.isEmpty {
                    result[.oneLine] = one
                }
            }
        } catch {
            // 出错保留已有的
        }

        return result
    }

    // MARK: - 辅助网络收集与 JSON 解析

    private func collectResponse(system: String, user: String) async throws -> String {
        var full = ""
        for try await chunk in ai.stream(messages: [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ]) {
            full += chunk
        }
        return full
    }

    private func extractJSONObject(from text: String) -> [String: Any]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 尝试从 ```json ... ``` 代码块中提取
        if let startRange = trimmed.range(of: "```json"),
           let endRange = trimmed[startRange.upperBound...].range(of: "```") {
            let jsonString = String(trimmed[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = jsonString.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj
            }
        }

        // 寻找第一个 '{' 和最后一个 '}'
        if let firstBrace = trimmed.firstIndex(of: "{"),
           let lastBrace = trimmed.lastIndex(of: "}") {
            let jsonString = String(trimmed[firstBrace...lastBrace])
            if let data = jsonString.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj
            }
        }

        return nil
    }
}
