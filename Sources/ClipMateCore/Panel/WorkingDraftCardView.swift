import SwiftUI
import AppKit

/// 工作草稿卡片（置顶嵌入在历史列表上方，提供无缝的材料整理、跟随更新与意图修改）
public struct WorkingDraftCardView: View {
    @ObservedObject public var viewModel: PanelViewModel
    @State private var naturalLanguageInput: String = ""
    @State private var isShowingSources: Bool = false
    @State private var isEditingTitle: Bool = false
    @State private var tempTitle: String = ""
    @State private var isEditingContent: Bool = false
    @State private var tempContent: String = ""
    @State private var isContentExpanded: Bool = true
    @FocusState private var isPromptFocused: Bool

    public init(viewModel: PanelViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        if let draft = viewModel.activeDraft {
            VStack(alignment: .leading, spacing: 8) {
                // 0. 多草稿切换标签（LLM-R19）
                if viewModel.drafts.count > 1 {
                    draftTabsView(activeId: draft.id)
                }

                // 0.5 错误信息提示横幅（LLM-C03）
                if let errorMsg = viewModel.draftErrorMessage {
                    errorBannerView(message: errorMsg)
                }

                // 1. 顶部栏：标题 + 用途 + 来源统计 + 跟随复制开关 + 关闭
                headerView(draft)

                // 2. 状态说明：AI 生成中进度 / 最新变化摘要
                statusBanner(draft)

                // 3. 信息层级变焦切换器（LLM-C04）
                zoomLevelPicker(draft)

                // 4. 草稿正文预览与微调编辑器（LLM-C01）
                contentPreviewOrEditor(draft)

                // 5. 意图与目标控件行（1~2 个最相关控件）
                if !draft.controls.isEmpty {
                    controlsView(draft)
                }

                // 6. 自然语言修改指令输入条
                naturalLanguageBar(draft)

                // 7. 待决修改对比抽屉（当有待采用建议或正在查看时）
                if viewModel.isDraftReviewingDiff || draft.hasPendingProposals {
                    proposalsReviewView(draft)
                }

                // 8. 来源材料查看与管理抽屉
                if isShowingSources {
                    sourcesListView(draft)
                }

                // 9. 未决确认问题抽屉（LLM-C03）
                if !draft.unresolvedItems.isEmpty {
                    unresolvedItemsView(draft)
                }

                // 10. 底部操作按钮栏（包含确认采用按钮 LLM-C02）
                actionBar(draft)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(viewModel.settings.appTheme.accent.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(viewModel.settings.appTheme.accent.opacity(0.20), lineWidth: 0.8)
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .onChange(of: viewModel.activeDraft?.id) { _ in
                isEditingContent = false
                tempContent = ""
                isEditingTitle = false
                tempTitle = ""
                viewModel.isDraftEditingText = false
            }
            .onChange(of: isEditingContent) { editing in
                viewModel.isDraftEditingText = editing || isEditingTitle
            }
            .onChange(of: isEditingTitle) { editing in
                viewModel.isDraftEditingText = editing || isEditingContent
            }
            .onChange(of: viewModel.isDraftEditingText) { isEditing in
                if !isEditing {
                    isEditingContent = false
                    isEditingTitle = false
                }
            }
            .onDisappear {
                viewModel.isDraftEditingText = false
                viewModel.isAIPromptFocused = false
            }
        }
    }

    // MARK: - 0. 多草稿标签栏 (LLM-R19)

    private func draftTabsView(activeId: UUID) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(viewModel.drafts) { d in
                    let isActive = (d.id == activeId)
                    HStack(spacing: 4) {
                        Button {
                            viewModel.selectDraft(id: d.id)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: d.purpose.icon)
                                    .font(.system(size: 9))
                                Text(d.title)
                                    .font(.system(size: 10, weight: isActive ? .bold : .regular))
                                    .lineLimit(1)
                                if isActive {
                                    Circle()
                                        .fill(viewModel.settings.appTheme.accent)
                                        .frame(width: 4, height: 4)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Button {
                            viewModel.removeDraft(id: d.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(isActive ? viewModel.settings.appTheme.accent : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.tr("draft.close_tab", lang: viewModel.settings.appLanguage))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isActive ? viewModel.settings.appTheme.accent.opacity(0.18) : Color.primary.opacity(0.04))
                    )
                }
            }
        }
    }

    // MARK: - 0.5 错误横幅 (LLM-C03)

    private func errorBannerView(message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.red)
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.red)
                .lineLimit(2)
            Spacer()
            Button {
                viewModel.draftErrorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.1)))
    }

    // MARK: - 1. 头部

    private func headerView(_ draft: WorkingDraft) -> some View {
        HStack(spacing: 6) {
            // 用途分类图标与名称
            HStack(spacing: 3) {
                Image(systemName: draft.purpose.icon)
                    .font(.system(size: 10, weight: .bold))
                Text(draft.purpose.title)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(viewModel.settings.appTheme.accent.opacity(0.2)))
            .foregroundStyle(viewModel.settings.appTheme.accent)

            // 草稿标题（支持点击重命名）
            if isEditingTitle {
                TextField("", text: $tempTitle, onCommit: {
                    if !tempTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                        viewModel.activeDraft?.title = tempTitle
                    }
                    isEditingTitle = false
                })
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .bold))
                .frame(maxWidth: 160)
            } else {
                Text(draft.title)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                    .onTapGesture {
                        tempTitle = draft.title
                        isEditingTitle = true
                    }
            }

            // 来源材料数量
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isShowingSources.toggle()
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "folder")
                        .font(.system(size: 9))
                    Text(L10n.tr("draft.sources_count", draft.activeSourcesCount, lang: viewModel.settings.appLanguage))
                        .font(.system(size: 10))
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)

            Spacer()

            // 跟随复制开关 (Follow Copy Toggle)
            Button {
                viewModel.toggleDraftFollowCopy()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: draft.followCopy ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath.circle")
                        .font(.system(size: 11))
                    Text(L10n.tr("draft.follow_copy", lang: viewModel.settings.appLanguage))
                        .font(.system(size: 10))
                }
                .foregroundStyle(draft.followCopy ? viewModel.settings.appTheme.accent : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("开启后，新复制的关联内容将自动提出草稿修改建议")

            // 关闭草稿
            Button {
                viewModel.closeDraft()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.tr("draft.close", lang: viewModel.settings.appLanguage))
        }
    }

    // MARK: - 2. 状态与变化说明

    private func statusBanner(_ draft: WorkingDraft) -> some View {
        HStack(spacing: 6) {
            if viewModel.isDraftGenerating {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                Text("智能分析与关联更新中…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if !draft.changeSummary.isEmpty {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundStyle(viewModel.settings.appTheme.accent)
                Text(draft.changeSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()

            // 状态标记（已确认 / 初始候选 / 编辑中）
            Text(draft.isCandidate ? "初始候选" : (draft.status == .editing ? "编辑中" : "已确认"))
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Capsule().fill(draft.isCandidate ? Color.orange.opacity(0.15) : Color.green.opacity(0.15)))
                .foregroundStyle(draft.isCandidate ? Color.orange : Color.green)

            // 草稿版本标记
            Text("v\(draft.version)")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 3. 信息层级变焦切换器 (LLM-C04)

    private func zoomLevelPicker(_ draft: WorkingDraft) -> some View {
        HStack(spacing: 4) {
            zoomButton(title: "全部", level: .full, current: draft.currentZoom)
            zoomButton(title: "要点", level: .keyPoints, current: draft.currentZoom)
            zoomButton(title: "结论", level: .actionItems, current: draft.currentZoom)
            zoomButton(title: "一句话", level: .oneLine, current: draft.currentZoom)
            Spacer()
        }
    }

    private func zoomButton(title: String, level: ZoomLevel, current: ZoomLevel) -> some View {
        let isSelected = (level == current)
        return Button {
            viewModel.setDraftZoomLevel(level: level)
        } label: {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? viewModel.settings.appTheme.accent.opacity(0.2) : Color.primary.opacity(0.04))
                )
                .foregroundStyle(isSelected ? viewModel.settings.appTheme.accent : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 4. 草稿正文预览与微调编辑器 (LLM-C01)

    private func contentPreviewOrEditor(_ draft: WorkingDraft) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("草稿内容预览")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if isEditingContent {
                    Button("保存") {
                        viewModel.updateDraftText(newText: tempContent)
                        isEditingContent = false
                    }
                    .clipMateAccent(size: .small)

                    Button("取消") {
                        isEditingContent = false
                    }
                    .clipMateGlass(size: .small)
                } else {
                    Button {
                        tempContent = draft.fullDraftText
                        isEditingContent = true
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "pencil")
                                .font(.system(size: 9))
                            Text("微调")
                                .font(.system(size: 10))
                        }
                    }
                    .clipMateGlass(size: .small)

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isContentExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isContentExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isEditingContent {
                TextEditor(text: $tempContent)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minHeight: 90, maxHeight: 160)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(viewModel.settings.appTheme.accent.opacity(0.5), lineWidth: 1))
            } else if isContentExpanded {
                let displayText = draft.effectiveText
                ScrollView(.vertical) {
                    Text(displayText.isEmpty ? "（草稿正文为空）" : displayText)
                        .font(.system(size: 11))
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 120)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
            }
        }
    }

    // MARK: - 5. 目标与约束控件

    private func controlsView(_ draft: WorkingDraft) -> some View {
        HStack(spacing: 8) {
            ForEach(draft.controls) { control in
                HStack(spacing: 4) {
                    switch control.type {
                    case .stepper(let minVal, let maxVal, let stepVal, let unit, _):
                        Text("\(control.name):")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 2) {
                            Button {
                                if let curr = Double(control.currentValue), curr - stepVal >= minVal {
                                    viewModel.updateDraftControl(controlId: control.id, newValue: "\(Int(curr - stepVal))")
                                }
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 9, weight: .bold))
                                    .frame(width: 16, height: 16)
                            }
                            .clipMateGlass(size: .small)

                            Text("\(control.currentValue)\(unit)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .frame(minWidth: 24)

                            Button {
                                if let curr = Double(control.currentValue), curr + stepVal <= maxVal {
                                    viewModel.updateDraftControl(controlId: control.id, newValue: "\(Int(curr + stepVal))")
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 9, weight: .bold))
                                    .frame(width: 16, height: 16)
                            }
                            .clipMateGlass(size: .small)
                        }

                    case .constraintToggle:
                        Button {
                            viewModel.updateDraftControl(controlId: control.id, newValue: "")
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: control.isLocked ? "lock.fill" : "lock.open")
                                    .font(.system(size: 9))
                                Text(control.name)
                                    .font(.system(size: 10.5))
                            }
                        }
                        .clipMateGlass(size: .small)

                    default:
                        Text("\(control.name): \(control.currentValue)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
            }
            Spacer()
        }
    }

    // MARK: - 4. 自然语言修改指令

    private func naturalLanguageBar(_ draft: WorkingDraft) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 11))
                .foregroundStyle(viewModel.settings.appTheme.accent)

            TextField(L10n.tr("draft.prompt_placeholder", lang: viewModel.settings.appLanguage), text: $naturalLanguageInput, onCommit: {
                submitNL()
            })
            .textFieldStyle(.plain)
            .font(.system(size: 11.5))
            .focused($isPromptFocused)
            .onChange(of: isPromptFocused) { focused in
                viewModel.isAIPromptFocused = focused
            }

            if !naturalLanguageInput.isEmpty {
                Button {
                    submitNL()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(viewModel.settings.appTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    private func submitNL() {
        let input = naturalLanguageInput
        naturalLanguageInput = ""
        viewModel.submitDraftRevision(instruction: input)
    }

    // MARK: - 5. 待决修改审查抽屉

    private func proposalsReviewView(_ draft: WorkingDraft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("待确认修改建议 (\(draft.pendingProposals.filter { !$0.isAdopted && !$0.isRejected }.count))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(viewModel.settings.appTheme.accent)
                Spacer()
                Button(L10n.tr("draft.adopt_all", lang: viewModel.settings.appLanguage)) {
                    viewModel.adoptAllDraftProposals()
                }
                .clipMateAccent(size: .small)
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(draft.pendingProposals.filter { !$0.isAdopted && !$0.isRejected }) { proposal in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(proposal.title)
                                    .font(.system(size: 11, weight: .medium))
                                Spacer()
                                Button("采用") {
                                    viewModel.adoptDraftProposal(proposalId: proposal.id)
                                }
                                .clipMateGlass(size: .small)

                                Button("忽略") {
                                    viewModel.rejectDraftProposal(proposalId: proposal.id)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            }

                            if !proposal.reason.isEmpty {
                                Text(proposal.reason)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }

                            // 修改详情 Diff
                            ForEach(proposal.changes) { change in
                                HStack(alignment: .top, spacing: 4) {
                                    if !change.originalSnippet.isEmpty {
                                        Text("— \(change.originalSnippet)")
                                            .strikethrough()
                                            .foregroundStyle(Color.red.opacity(0.7))
                                    }
                                    Text("+ \(change.proposedSnippet)")
                                        .foregroundStyle(Color.green)
                                }
                                .font(.system(size: 10, design: .monospaced))
                            }
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                    }
                }
            }
            .frame(maxHeight: 140)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.windowBackgroundColor).opacity(0.7)))
    }

    // MARK: - 6. 来源列表抽屉

    private func sourcesListView(_ draft: WorkingDraft) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("已纳入的材料来源：")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(draft.sources) { source in
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)

                            Text(source.sourceName.isEmpty ? "剪贴板材料" : source.sourceName)
                                .font(.system(size: 10.5, weight: .medium))
                                .lineLimit(1)

                            Text(source.content.prefix(40))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Spacer()

                            Button {
                                viewModel.removeSourceFromDraft(sourceId: source.id)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("从当前草稿移出并重新整理")
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxHeight: 120)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
    }

    // MARK: - 9. 未决问题与交互确认 (LLM-C03)

    private func unresolvedItemsView(_ draft: WorkingDraft) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(draft.unresolvedItems) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.orange)
                            Text(item.question)
                                .font(.system(size: 11, weight: .medium))
                            if let res = item.resolvedValue {
                                Text("（已选：\(res)）")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        // 快速交互确认选项按钮 (LLM-C03)
                        if item.resolvedValue == nil && !item.suggestedValues.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(item.suggestedValues, id: \.self) { val in
                                    Button(val) {
                                        viewModel.resolveUnresolvedItem(itemId: item.id, answer: val)
                                    }
                                    .clipMateGlass(size: .small)
                                    .font(.system(size: 10))
                                }
                            }
                            .padding(.leading, 18)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 120)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.08)))
    }

    // MARK: - 10. 底部主操作区 (包含 LLM-C02 确认采用按钮)

    private func actionBar(_ draft: WorkingDraft) -> some View {
        HStack(spacing: 8) {
            // 确认采用候选草稿按钮 (LLM-C02)
            if draft.isCandidate || draft.status == .candidate {
                Button {
                    viewModel.confirmAdoptDraft()
                } label: {
                    Label("确认采用", systemImage: "checkmark.circle.fill")
                }
                .clipMateAccent(size: .small)
            }

            // 查看修改按钮
            if draft.hasPendingProposals {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.isDraftReviewingDiff.toggle()
                    }
                } label: {
                    Label(
                        L10n.tr("draft.review_proposals", draft.pendingProposals.filter { !$0.isAdopted && !$0.isRejected }.count, lang: viewModel.settings.appLanguage),
                        systemImage: "doc.badge.gearshape"
                    )
                }
                .clipMateAccent(size: .small)
            }

            Spacer()

            // 撤销按钮
            if !draft.undoStack.isEmpty {
                Button {
                    viewModel.undoDraft()
                } label: {
                    Label(L10n.tr("draft.undo", lang: viewModel.settings.appLanguage), systemImage: "arrow.uturn.backward")
                }
                .clipMateGlass(size: .small)
            }

            // 复制草稿
            Button {
                viewModel.copyDraft()
            } label: {
                Label(L10n.tr("draft.copy", lang: viewModel.settings.appLanguage), systemImage: "doc.on.doc")
            }
            .clipMateGlass(size: .small)

            // 粘贴草稿
            Button {
                viewModel.pasteDraft()
            } label: {
                Label(L10n.tr("draft.paste", lang: viewModel.settings.appLanguage), systemImage: "arrow.right.doc.on.clipboard")
            }
            .clipMateAccent(size: .small)
        }
    }
}
