import Foundation

public enum DraftEngineError: LocalizedError, Equatable {
    case proposalNotFound
    case snippetNotFound(String)
    case versionMismatch(expected: Int, actual: Int)
    case violatesHardConstraint(String)
    case overlappingChanges
    case general(String)

    public var errorDescription: String? {
        switch self {
        case .proposalNotFound:
            return "未找到指定的修改建议"
        case .snippetNotFound(let snippet):
            return "待替换文本「\(snippet.prefix(20))...」在当前草稿中未找到，可能已被修改，取消采用"
        case .versionMismatch(let expected, let actual):
            return "修改建议基于版本 v\(expected)，当前草稿已演进为 v\(actual)，版本不匹配，取消采用"
        case .violatesHardConstraint(let reason):
            return "该修改与已锁定的硬约束「\(reason)」冲突，无法直接采用"
        case .overlappingChanges:
            return "修改建议中存在重叠的文本替换区间，无法安全采用"
        case .general(let msg):
            return msg
        }
    }
}

/// 工作草稿本地逻辑与校验引擎
/// 承担确定性计算、来源引用校验、修改边界检查、版本保护与纯本地规则兜底。
public enum WorkingDraftEngine {

    // MARK: - 1. 草稿创建与本地规则组织

    /// 从所选材料构建工作草稿。优先使用本地结构化提炼，可无缝对接后续 LLM 增强。
    public static func createDraft(
        sources: [DraftSource],
        purpose: DraftPurpose? = nil,
        title: String? = nil
    ) -> WorkingDraft {
        let activeSources = sources.filter { $0.status == .included }
        let inferredPurpose = purpose ?? inferPurpose(from: activeSources)
        let generatedTitle = title ?? generateTitle(from: activeSources, purpose: inferredPurpose)

        // 提取事实、约束、要求与待确认项
        let extracted = extractLocalStructures(from: activeSources)

        // 构建结构化格式草稿
        let draftText = formatDraftText(purpose: inferredPurpose, extracted: extracted)

        // 发现 1~2 个关键意图/约束控件
        let controls = discoverLocalControls(from: extracted, draftText: draftText)

        // 生成初始信息层级
        let zoomLevels = generateLocalZoomLevels(draftText: draftText, extracted: extracted)

        let draft = WorkingDraft(
            id: UUID(),
            title: generatedTitle,
            purpose: inferredPurpose,
            status: .candidate,
            followCopy: false, // LLM-R13: 默认不跟随复制，需用户明确开启
            sources: sources,
            confirmedText: "",
            candidateText: draftText,
            userEditedText: nil,
            changeSummary: "根据 \(activeSources.count) 份材料自动整理",
            pendingProposals: [],
            unresolvedItems: extracted.unresolvedItems,
            controls: controls,
            zoomLevels: zoomLevels,
            currentZoom: .full,
            version: 1,
            undoStack: [],
            createdAt: Date(),
            updatedAt: Date()
        )

        return draft
    }

    // MARK: - 2. 来源与引用定位校验

    /// 校验草稿文本中的片段是否真实存在于所引用的来源材料中（防止幻觉与虚构事实）
    public static func verifySourceCitation(
        snippet: String,
        sourceID: Int64,
        in sources: [DraftSource]
    ) -> Bool {
        guard let source = sources.first(where: { $0.id == sourceID }) else { return false }
        let cleanSnippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanSnippet.isEmpty { return true }
        return source.content.contains(cleanSnippet)
    }

    // MARK: - 3. 关联修改成组采用与局部一致性检查

    private struct ResolvedChange {
        let change: DraftTextChange
        let range: Range<String.Index>
        let isInsertion: Bool
    }

    private static func resolveChanges(
        changes: [DraftTextChange],
        baseText: String,
        draft: WorkingDraft
    ) -> Result<[ResolvedChange], DraftEngineError> {
        let lockedConstraints = draft.controls.filter { $0.isHardConstraint && $0.isLocked }
        var resolved: [ResolvedChange] = []

        for change in changes {
            let cleanOrig = change.originalSnippet.trimmingCharacters(in: .whitespacesAndNewlines)

            // LLM-R05: 检查锁定硬约束
            for c in lockedConstraints {
                if !cleanOrig.isEmpty && c.relatedTextLocations.contains(where: { $0.contains(cleanOrig) || cleanOrig.contains($0) }) {
                    return .failure(.violatesHardConstraint(c.name))
                }
                if case .constraintToggle(let desc) = c.type {
                    if !cleanOrig.isEmpty && (desc.contains(cleanOrig) || cleanOrig.contains(desc)) {
                        return .failure(.violatesHardConstraint(c.name))
                    }
                }
            }

            if change.action == .insert || cleanOrig.isEmpty {
                // LLM-R01: 插入/追加逻辑
                var insertIndex = baseText.endIndex
                if !change.contextHint.isEmpty, let ctxRange = baseText.range(of: change.contextHint) {
                    insertIndex = ctxRange.upperBound
                }
                resolved.append(ResolvedChange(
                    change: change,
                    range: insertIndex..<insertIndex,
                    isInsertion: true
                ))
            } else {
                // 替换或删除
                var targetRange: Range<String.Index>?
                if !change.contextHint.isEmpty, let ctxRange = baseText.range(of: change.contextHint) {
                    targetRange = baseText.range(of: cleanOrig, range: ctxRange)
                }
                if targetRange == nil {
                    targetRange = baseText.range(of: cleanOrig)
                }

                guard let foundRange = targetRange else {
                    return .failure(.snippetNotFound(cleanOrig))
                }

                resolved.append(ResolvedChange(
                    change: change,
                    range: foundRange,
                    isInsertion: false
                ))
            }
        }

        // LLM-R03 / LLM-R04: 校验非重叠 (Non-overlapping)
        let nonInsertions = resolved.filter { !$0.isInsertion }.sorted { $0.range.lowerBound < $1.range.lowerBound }
        if nonInsertions.count > 1 {
            for i in 0..<(nonInsertions.count - 1) {
                if nonInsertions[i].range.upperBound > nonInsertions[i + 1].range.lowerBound {
                    return .failure(.overlappingChanges)
                }
            }
        }

        return .success(resolved)
    }

    private static func applyResolvedChanges(
        _ resolved: [ResolvedChange],
        to baseText: String
    ) -> String {
        // 倒序应用：从后向前修改，避免前面位移影响后面 index (LLM-R03)
        let sortedDesc = resolved.sorted {
            if $0.range.lowerBound == $1.range.lowerBound {
                return false
            }
            return $0.range.lowerBound > $1.range.lowerBound
        }

        var result = baseText
        for item in sortedDesc {
            if item.isInsertion {
                var textToInsert = item.change.proposedSnippet
                if item.range.lowerBound == result.endIndex && !result.isEmpty && !result.hasSuffix("\n") {
                    textToInsert = "\n" + textToInsert
                }
                result.insert(contentsOf: textToInsert, at: item.range.lowerBound)
            } else if item.change.action == .delete || item.change.proposedSnippet.isEmpty {
                result.removeSubrange(item.range)
            } else {
                result.replaceSubrange(item.range, with: item.change.proposedSnippet)
            }
        }
        return result
    }

    /// 采用整组建议修改（原子性事务操作）
    @discardableResult
    public static func adoptProposal(
        draft: inout WorkingDraft,
        proposalId: String
    ) -> Result<Void, DraftEngineError> {
        guard let pIndex = draft.pendingProposals.firstIndex(where: { $0.id == proposalId }) else {
            return .failure(.proposalNotFound)
        }

        let proposal = draft.pendingProposals[pIndex]

        // LLM-R02: 校验草稿版本号匹配
        if proposal.targetVersion != draft.version {
            return .failure(.versionMismatch(expected: proposal.targetVersion, actual: draft.version))
        }

        // LLM-R08: 基准文本始终使用 fullDraftText
        let baseText = draft.fullDraftText

        // 解析与校验所有变更（包含 LLM-R01, LLM-R03, LLM-R05）
        let resolution = resolveChanges(changes: proposal.changes, baseText: baseText, draft: draft)
        switch resolution {
        case .failure(let err):
            return .failure(err)
        case .success(let resolvedChanges):
            // 保存撤销快照
            draft.pushSnapshot()

            let targetText = applyResolvedChanges(resolvedChanges, to: baseText)

            // 更新状态
            draft.confirmedText = targetText
            draft.candidateText = nil
            draft.userEditedText = nil
            draft.version += 1
            draft.status = .confirmed
            draft.pendingProposals[pIndex].isAdopted = true
            draft.changeSummary = "已采用修改：\(proposal.title)"
            draft.updatedAt = Date()

            // 重新同步层级与控件 (LLM-R09)
            refreshDerivedState(draft: &draft)

            return .success(())
        }
    }

    /// 采用全部未决修改建议
    @discardableResult
    public static func adoptAllProposals(draft: inout WorkingDraft) -> Result<Void, DraftEngineError> {
        let pendingIndices = draft.pendingProposals.indices.filter {
            !draft.pendingProposals[$0].isAdopted && !draft.pendingProposals[$0].isRejected
        }
        guard !pendingIndices.isEmpty else { return .success(()) }

        // LLM-R08: 基准文本始终使用 fullDraftText
        let baseText = draft.fullDraftText

        var allResolvedChanges: [ResolvedChange] = []
        var adoptedIndices: [Int] = []

        for idx in pendingIndices {
            let proposal = draft.pendingProposals[idx]
            // LLM-R02: 校验版本号
            if proposal.targetVersion != draft.version {
                continue
            }
            if case .success(let resolved) = resolveChanges(changes: proposal.changes, baseText: baseText, draft: draft) {
                var hasOverlap = false
                for r in resolved {
                    if !r.isInsertion {
                        for existing in allResolvedChanges where !existing.isInsertion {
                            if r.range.lowerBound < existing.range.upperBound && existing.range.lowerBound < r.range.upperBound {
                                hasOverlap = true
                                break
                            }
                        }
                    }
                    if hasOverlap { break }
                }

                if !hasOverlap {
                    allResolvedChanges.append(contentsOf: resolved)
                    adoptedIndices.append(idx)
                }
            }
        }

        guard !adoptedIndices.isEmpty else {
            if let first = pendingIndices.first, draft.pendingProposals[first].targetVersion != draft.version {
                return .failure(.versionMismatch(expected: draft.pendingProposals[first].targetVersion, actual: draft.version))
            }
            return .failure(.general("暂无符合条件或无冲突的待采用建议"))
        }

        draft.pushSnapshot()
        let targetText = applyResolvedChanges(allResolvedChanges, to: baseText)

        for idx in adoptedIndices {
            draft.pendingProposals[idx].isAdopted = true
        }

        draft.confirmedText = targetText
        draft.candidateText = nil
        draft.userEditedText = nil
        draft.version += 1
        draft.status = .confirmed
        draft.changeSummary = "已采用 \(adoptedIndices.count) 项修改建议"
        draft.updatedAt = Date()
        refreshDerivedState(draft: &draft)

        return .success(())
    }

    /// 拒绝建议
    public static func rejectProposal(draft: inout WorkingDraft, proposalId: String) {
        if let index = draft.pendingProposals.firstIndex(where: { $0.id == proposalId }) {
            draft.pendingProposals[index].isRejected = true
            draft.changeSummary = "已忽略修改：\(draft.pendingProposals[index].title)"
            draft.updatedAt = Date()
        }
    }

    /// 检查局部采纳一致性（如多处承诺只改了一处）
    public static func checkPartialAdoptionConsistency(
        proposal: DraftRevisionProposal,
        adoptedChangeIDs: Set<String>,
        currentText: String
    ) -> [String] {
        var warnings: [String] = []
        let unadopted = proposal.changes.filter { !adoptedChangeIDs.contains($0.id) }

        // 如果这是一组关联修改（如同时修改正文与结尾中的日期承诺）
        if proposal.changes.count > 1 && !unadopted.isEmpty && !adoptedChangeIDs.isEmpty {
            for un in unadopted {
                warnings.append("关联修改尚未完整采用：「\(un.originalSnippet.prefix(15))...」仍保留旧表述，可能导致前后不一致")
            }
        }

        return warnings
    }

    // MARK: - 4. 目标控件与确定性计算校验

    /// 用户操作目标控件（如调节人数、起止时间）
    public static func applyControlValue(
        draft: inout WorkingDraft,
        controlID: String,
        newValue: String
    ) -> Bool {
        guard let index = draft.controls.firstIndex(where: { $0.id == controlID }) else { return false }
        var control = draft.controls[index]

        // LLM-R05: 硬约束且锁定时禁止非 toggle 修改
        if control.isHardConstraint && control.isLocked {
            if case .constraintToggle = control.type {
                // toggle 允许用户手动点击解锁或开启
            } else {
                return false
            }
        }

        // LLM-R08: 基准文本始终使用 fullDraftText
        let currentText = draft.fullDraftText
        guard !currentText.isEmpty else { return false }

        draft.pushSnapshot()

        switch control.type {
        case .stepper(_, _, _, let unit, _):
            // 数量/人数比例：尝试交由 InteractiveControlEngine 进行数值与关联食材/排期校验
            if let targetNum = Double(newValue) {
                // 如果当前文本能被 InteractiveControlEngine 解析为比例或数量模型
                if var session = InteractiveControlEngine.analyze(text: currentText) {
                    if let pVar = session.primaryVariable, let varIdx = session.variables.firstIndex(where: { $0.id == pVar.id }) {
                        session.variables[varIdx].currentValue = .number(targetNum)
                        InteractiveControlEngine.recalculate(session: &session)
                        draft.confirmedText = session.adjustedText
                        draft.candidateText = nil
                        control.currentValue = "\(Int(targetNum))"
                        draft.controls[index] = control
                        draft.changeSummary = "已将\(control.name)调整为 \(newValue)\(unit)"
                        draft.version += 1
                        refreshDerivedState(draft: &draft)
                        return true
                    }
                }

                // LLM-R06: 兜底使用整词/非数字边界正则替换，避免 bare replacingOccurrences 误伤日期如 2026-03-15
                let oldVal = control.currentValue
                let pattern: String
                let replacement: String
                if !unit.isEmpty {
                    pattern = #"(?<![0-9])"# + NSRegularExpression.escapedPattern(for: oldVal) + #"\s*"# + NSRegularExpression.escapedPattern(for: unit)
                    replacement = "\(newValue)\(unit)"
                } else {
                    pattern = #"(?<![0-9])"# + NSRegularExpression.escapedPattern(for: oldVal) + #"(?![0-9])"#
                    replacement = newValue
                }

                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(currentText.startIndex..<currentText.endIndex, in: currentText)
                    let newText = regex.stringByReplacingMatches(in: currentText, options: [], range: range, withTemplate: replacement)
                    if newText != currentText {
                        draft.confirmedText = newText
                        draft.candidateText = nil
                        control.currentValue = newValue
                        draft.controls[index] = control
                        draft.changeSummary = "已将\(control.name)调整为 \(newValue)\(unit)"
                        draft.version += 1
                        refreshDerivedState(draft: &draft)
                        return true
                    }
                }
            }

        case .constraintToggle:
            // 硬约束切换：例如“不得包含个人信息”
            control.isLocked.toggle()
            control.currentValue = control.isLocked ? "已开启" : "已关闭"
            draft.controls[index] = control
            draft.changeSummary = "\(control.name)：\(control.currentValue)"
            draft.updatedAt = Date()
            return true

        case .options(let choices):
            if choices.contains(newValue) {
                control.currentValue = newValue
                draft.controls[index] = control
                draft.changeSummary = "已切换\(control.name)为「\(newValue)」"
                draft.updatedAt = Date()
                return true
            }

        default:
            control.currentValue = newValue
            draft.controls[index] = control
            draft.updatedAt = Date()
            return true
        }

        return false
    }

    // MARK: - 5. 新材料归属评估（本地规则快速判断）

    /// 本地规则评估新复制材料是否归属于当前草稿
    public static func evaluateAttributionLocally(
        newItemText: String,
        draft: WorkingDraft
    ) -> (relation: DraftAttributionRelation, proposal: DraftRevisionProposal?, summary: String) {
        let trimmed = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (.irrelevant, nil, "") }

        // 获取草稿中的核心关键词与实体
        let draftKeywords = extractKeywords(from: draft.effectiveText)
        let newKeywords = extractKeywords(from: trimmed)
        let common = draftKeywords.intersection(newKeywords)

        // 判断是否有明确的修订/否定关系：例如“不需要...了”，“改为...”，“暂不要求离线”，“不能包含个人信息”
        let revisionPatterns = ["改为", "不需要", "暂不要求", "取消", "推迟", "调整为", "不能包含", "不得", "更新为"]
        var isRevision = false
        var matchedRevisionKey = ""
        for pat in revisionPatterns {
            if trimmed.contains(pat) {
                isRevision = true
                matchedRevisionKey = pat
                break
            }
        }

        // 若重合词足够多且包含修订词汇 -> revision
        if !common.isEmpty && isRevision {
            let change = DraftTextChange(
                originalSnippet: "",
                proposedSnippet: trimmed,
                reason: "新材料提及「\(matchedRevisionKey)」要求"
            )
            let proposal = DraftRevisionProposal(
                title: "新要求调整：\(matchedRevisionKey)",
                reason: "新复制材料更新了限制或要求",
                targetVersion: draft.version,
                changes: [change],
                relatedSourceIDs: []
            )
            return (.revision, proposal, "新增 1 条限制/修订，生成了待采用建议")
        }

        // 若重合词 >= 2 或包含核心事项词 -> addition (LLM-R16: 为补充材料生成待采用建议项)
        if common.count >= 2 || (!common.isEmpty && trimmed.count > 15) {
            let change = DraftTextChange(
                originalSnippet: "",
                proposedSnippet: "• 补充信息：\(trimmed)",
                reason: "新材料包含相关事实或要求",
                action: .insert
            )
            let proposal = DraftRevisionProposal(
                title: "补充材料事实与要求",
                reason: "新复制材料补充了相关要求",
                targetVersion: draft.version,
                changes: [change],
                relatedSourceIDs: []
            )
            return (.addition, proposal, "新复制内容可能属于当前事项，已生成补充建议")
        }

        return (.irrelevant, nil, "")
    }

    // MARK: - 6. 辅助提炼算法（纯本地文本提炼）

    private struct ExtractedInfo {
        var facts: [String] = []
        var requirements: [String] = []
        var constraints: [String] = []
        var risks: [String] = []
        var unresolvedItems: [DraftUnresolvedItem] = []
        var numbers: [(name: String, value: Double, unit: String)] = []
        var dates: [String] = []
    }

    private static func inferPurpose(from sources: [DraftSource]) -> DraftPurpose {
        let full = sources.map { $0.content }.joined(separator: "\n")
        if full.contains("回复") || full.contains("您好") || full.contains("收到") || full.contains("客户") {
            return .reply
        }
        if full.contains("待办") || full.contains("TODO") || full.contains("任务") || full.contains("步骤") {
            return .todo
        }
        if full.contains("方案") || full.contains("设计") || full.contains("架构") || full.contains("规划") {
            return .proposal
        }
        if full.contains("会议") || full.contains("纪要") || full.contains("讨论") {
            return .summary
        }
        return .general
    }

    private static func generateTitle(from sources: [DraftSource], purpose: DraftPurpose) -> String {
        guard let first = sources.first?.content else { return "整理草稿" }
        let lines = first.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let line = lines.first {
            let clean = line.prefix(18).replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
            if !clean.isEmpty {
                return "\(clean) - \(purpose.title)"
            }
        }
        return "\(purpose.title)草稿"
    }

    private static func extractLocalStructures(from sources: [DraftSource]) -> ExtractedInfo {
        var info = ExtractedInfo()

        for source in sources {
            let lines = source.content.components(separatedBy: .newlines)
            for rawLine in lines {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty else { continue }

                // 约束与否定条件
                if line.contains("不能") || line.contains("不得") || line.contains("禁止") || line.contains("严禁") {
                    info.constraints.append(line)
                } else if line.contains("需要") || line.contains("要求") || line.contains("必须") {
                    info.requirements.append(line)
                } else if line.contains("尚未确定") || line.contains("未确定") || line.contains("待定") || line.contains("风险") {
                    info.risks.append(line)
                } else if line.contains("？") || line.contains("?") {
                    info.unresolvedItems.append(DraftUnresolvedItem(question: line, isCritical: false))
                } else {
                    info.facts.append(line)
                }
            }
        }

        // 最多提一个最关键的未决问题
        if !info.risks.isEmpty && info.unresolvedItems.isEmpty {
            let topRisk = info.risks[0]
            info.unresolvedItems.append(DraftUnresolvedItem(
                question: "关键信息待确认：\(topRisk)",
                suggestedValues: ["已知晓并保留说明", "暂按未确定处理"],
                isCritical: true
            ))
        }

        return info
    }

    private static func formatDraftText(purpose: DraftPurpose, extracted: ExtractedInfo) -> String {
        var sections: [String] = []

        switch purpose {
        case .reply:
            sections.append("您好，针对您提出的需求与安排，反馈如下：\n")
            if !extracted.requirements.isEmpty {
                sections.append("一、确认事项与范围：")
                for req in extracted.requirements {
                    sections.append("• \(req)")
                }
                sections.append("")
            }
            if !extracted.constraints.isEmpty {
                sections.append("二、约束与注意事项：")
                for c in extracted.constraints {
                    sections.append("• \(c)")
                }
                sections.append("")
            }
            if !extracted.risks.isEmpty {
                sections.append("三、待定事项说明：")
                for r in extracted.risks {
                    sections.append("• \(r)")
                }
                sections.append("")
            }
            sections.append("如无异议我们将按此推进，感谢！")

        case .todo:
            sections.append("【执行清单与待办事项】\n")
            var idx = 1
            for req in extracted.requirements {
                sections.append("\(idx). [ ] \(req)")
                idx += 1
            }
            for c in extracted.constraints {
                sections.append("\(idx). [!] 注意约束：\(c)")
                idx += 1
            }
            for r in extracted.risks {
                sections.append("\(idx). [?] 待确认：\(r)")
                idx += 1
            }

        default:
            sections.append("【工作整理草稿】\n")
            if !extracted.requirements.isEmpty {
                sections.append("主要要求：")
                for r in extracted.requirements { sections.append("• \(r)") }
                sections.append("")
            }
            if !extracted.constraints.isEmpty {
                sections.append("关键约束：")
                for c in extracted.constraints { sections.append("• \(c)") }
                sections.append("")
            }
            if !extracted.risks.isEmpty {
                sections.append("风险与待定：")
                for risk in extracted.risks { sections.append("• \(risk)") }
                sections.append("")
            }
            if !extracted.facts.isEmpty {
                sections.append("参考信息：")
                for f in extracted.facts.prefix(5) { sections.append("• \(f)") }
            }
        }

        return sections.joined(separator: "\n")
    }

    private static func discoverLocalControls(from extracted: ExtractedInfo, draftText: String) -> [DraftGoalControl] {
        var controls: [DraftGoalControl] = []

        // 如果存在硬约束
        if !extracted.constraints.isEmpty {
            let topC = extracted.constraints[0]
            let shortName = String(topC.prefix(12))
            controls.append(DraftGoalControl(
                name: "约束：\(shortName)",
                type: .constraintToggle(description: topC),
                currentValue: "已开启",
                isHardConstraint: true,
                isLocked: true
            ))
        }

        // 如果包含人数或数量
        if let match = draftText.range(of: #"[0-9]+(?:\.[0-9]+)?\s*(?:人|件|套|份)"#, options: .regularExpression) {
            let str = String(draftText[match])
            let numStr = str.filter { $0.isNumber || $0 == "." }
            let val = Double(numStr) ?? 1.0
            controls.append(DraftGoalControl(
                name: "数量调节",
                type: .stepper(min: 1, max: 100, step: 1, unit: "", isInteger: true),
                currentValue: "\(Int(val))",
                isHardConstraint: false,
                isLocked: false
            ))
        }

        return Array(controls.prefix(2))
    }

    private static func generateLocalZoomLevels(draftText: String, extracted: ExtractedInfo) -> [ZoomLevel: String] {
        var levels: [ZoomLevel: String] = [:]
        levels[.full] = draftText

        // 核心要点
        var keyPoints: [String] = []
        if !extracted.requirements.isEmpty {
            keyPoints.append("【要点】" + extracted.requirements.prefix(3).joined(separator: "；"))
        }
        if !extracted.constraints.isEmpty {
            keyPoints.append("【限制】" + extracted.constraints.prefix(2).joined(separator: "；"))
        }
        levels[.keyPoints] = keyPoints.joined(separator: "\n")

        // 结论清单
        var actions: [String] = []
        for (i, req) in extracted.requirements.prefix(3).enumerated() {
            actions.append("\(i+1). \(req)")
        }
        for c in extracted.constraints.prefix(2) {
            actions.append("• 需满足：\(c)")
        }
        levels[.actionItems] = actions.joined(separator: "\n")

        // 一句话概括
        let oneLine = extracted.requirements.first ?? (draftText.components(separatedBy: .newlines).first ?? "工作草稿")
        levels[.oneLine] = String(oneLine.prefix(60))

        return levels
    }

    /// 重新推导或刷新全部信息层级（LLM-R09 & LLM-R17: 全量刷新 .full, .keyPoints, .actionItems, .oneLine，防止旧文本残留）
    public static func refreshDerivedState(draft: inout WorkingDraft) {
        let text = draft.fullDraftText
        draft.zoomLevels[.full] = text

        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var reqs: [String] = []
        var cons: [String] = []
        for l in lines {
            if l.contains("不能") || l.contains("不得") || l.contains("禁止") || l.contains("严禁") || l.contains("约束") || l.contains("注意") {
                cons.append(l)
            } else if l.contains("需要") || l.contains("要求") || l.contains("必须") || l.hasPrefix("•") || l.hasPrefix("-") || l.hasPrefix("1.") || l.hasPrefix("2.") {
                reqs.append(l)
            }
        }

        var keyPoints: [String] = []
        if !reqs.isEmpty {
            keyPoints.append("【要点】" + reqs.prefix(3).joined(separator: "；"))
        }
        if !cons.isEmpty {
            keyPoints.append("【限制】" + cons.prefix(2).joined(separator: "；"))
        }
        draft.zoomLevels[.keyPoints] = keyPoints.isEmpty ? String(text.prefix(120)) : keyPoints.joined(separator: "\n")

        var actions: [String] = []
        for (i, req) in reqs.prefix(3).enumerated() {
            actions.append("\(i+1). \(req)")
        }
        for c in cons.prefix(2) {
            actions.append("• 需满足：\(c)")
        }
        draft.zoomLevels[.actionItems] = actions.isEmpty ? String(text.prefix(80)) : actions.joined(separator: "\n")

        if let firstLine = lines.first(where: { !$0.isEmpty }) {
            draft.zoomLevels[.oneLine] = String(firstLine.prefix(60))
        } else {
            draft.zoomLevels[.oneLine] = "工作草稿"
        }
    }

    private static func extractKeywords(from text: String) -> Set<String> {
        var tokens = Set<String>()
        let punctuation = CharacterSet.punctuationCharacters
            .union(.whitespacesAndNewlines)
            .union(CharacterSet(charactersIn: "：，。！？、“”‘’（）《》【】；;:,!?.()[]\"'—–-"))
        let parts = text.components(separatedBy: punctuation)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for part in parts {
            let chars = Array(part)
            if chars.count >= 2 {
                for i in 0..<(chars.count - 1) {
                    tokens.insert(String(chars[i..<(i + 2)]))
                    if i + 3 <= chars.count {
                        tokens.insert(String(chars[i..<(i + 3)]))
                    }
                }
            }
            if part.count >= 2 && part.count <= 10 {
                tokens.insert(part)
            }
        }
        return tokens
    }
}
