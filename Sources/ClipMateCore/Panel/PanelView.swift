import SwiftUI
import AppKit

/// 主面板：搜索栏 + 分类 chips + 历史列表 + 快捷键提示条。
struct PanelView: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            panelCard
                .padding(.leading, 30)
                .padding(.top, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var panelCard: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                // 左侧：剪贴板列表主区域（瘦身 1/3：从 660px 缩减为 440px）
                VStack(spacing: 0) {
                    SearchBar(viewModel: viewModel)
                    FilterToolbar(viewModel: viewModel)
                    // 片段分类下展示分组栏（全部 / 各分组 / 新建片段）
                    if viewModel.filter == .snippet {
                        SnippetGroupBar(viewModel: viewModel)
                    }
                    RecommendationBar(viewModel: viewModel)
                    if viewModel.activeDraft != nil {
                        WorkingDraftCardView(viewModel: viewModel)
                    }
                    Divider().overlay(Color.primary.opacity(0.05))
                    if viewModel.items.isEmpty {
                        EmptyStateView(query: viewModel.query)
                    } else {
                        ClipList(viewModel: viewModel)
                    }
                    Divider().overlay(Color.primary.opacity(0.05))
                    if viewModel.multiSelectedIDs.count > 1 {
                        BatchActionBar(viewModel: viewModel)
                    } else {
                        FooterBar(settings: viewModel.settings)
                    }
                }
                .frame(width: 440)

                // 右侧：内置 AI 问答侧边栏（平滑展开）
                Divider().overlay(Color.primary.opacity(0.12))
                AISidebarView(viewModel: viewModel, model: viewModel.aiModel)
                    .frame(width: 439)
                    .opacity(viewModel.isAISidebarOpen ? 1 : 0)
            }
            .frame(width: 880, alignment: .leading)
            .disabled(viewModel.showEditOverlay || viewModel.showSnippetOverlay || viewModel.showRenameOverlay || viewModel.showConfirmClear || viewModel.previewItem != nil)

            if viewModel.showEditOverlay {
                EditOverlay(viewModel: viewModel)
                    .frame(width: viewModel.isAISidebarOpen ? 880 : 440, height: 520)
            }
            if viewModel.showSnippetOverlay {
                SnippetEditOverlay(viewModel: viewModel)
                    .frame(width: viewModel.isAISidebarOpen ? 880 : 440, height: 520)
            }
            if viewModel.showRenameOverlay {
                RenameOverlay(viewModel: viewModel)
                    .frame(width: viewModel.isAISidebarOpen ? 880 : 440, height: 520)
            }
            if viewModel.showConfirmClear {
                ConfirmClearOverlay(viewModel: viewModel)
                    .frame(width: viewModel.isAISidebarOpen ? 880 : 440, height: 520)
            }
            if viewModel.previewItem != nil {
                PreviewOverlay(viewModel: viewModel)
                    .frame(width: viewModel.isAISidebarOpen ? 880 : 440, height: 520)
            }
        }
        .frame(width: viewModel.isAISidebarOpen ? 880 : 440, height: 520, alignment: .leading)
        .background(
            ZStack {
                VisualEffectBackground()
                if let tint = viewModel.settings.appTheme.backgroundTint {
                    tint
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(viewModel.settings.appTheme.borderColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        .preferredColorScheme(viewModel.settings.appTheme.preferredColorScheme)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isAISidebarOpen)
    }
}

// MARK: - 搜索栏

struct SearchBar: View {
    @ObservedObject var viewModel: PanelViewModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(L10n.tr("search.placeholder", lang: viewModel.settings.appLanguage), text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .focused($focused)
                .help(L10n.tr("search.syntax_hint", lang: viewModel.settings.appLanguage))

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                    viewModel.reload()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 2)
            }

            let theme = viewModel.settings.appTheme
            // AI 问答侧边栏快速展开/收起切换按钮 (精致现代胶囊)
            Button {
                viewModel.toggleAISidebar()
            } label: {
                HStack(spacing: 3.5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                    Text("AI")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(
                    Capsule()
                        .fill(viewModel.isAISidebarOpen ? theme.accent.opacity(0.18) : Color.primary.opacity(0.05))
                )
                .foregroundStyle(viewModel.isAISidebarOpen ? theme.accent : Color.secondary)
                .overlay(
                    Capsule()
                        .strokeBorder(viewModel.isAISidebarOpen ? theme.accent.opacity(0.35) : Color.clear, lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
            .help(L10n.tr("search.help", lang: viewModel.settings.appLanguage))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .onAppear { focused = true }
        .onReceive(NotificationCenter.default.publisher(for: .clipmateFocusSearch)) { _ in
            focused = true
        }
        .onChange(of: viewModel.query) { _ in
            viewModel.queryChanged()
        }
    }
}

// MARK: - 统一极简筛选工具栏（单行横向胶囊 + 紧凑情境下拉）

struct FilterToolbar: View {
    @ObservedObject var viewModel: PanelViewModel
    @ObservedObject var settings: AppSettings

    init(viewModel: PanelViewModel) {
        self.viewModel = viewModel
        self.settings = viewModel.settings
    }

    var body: some View {
        HStack(spacing: 6) {
            // 1. 分类横向轻量胶囊条
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(FilterKind.allCases) { kind in
                        FilterChip(kind: kind, selected: viewModel.filter == kind, lang: settings.appLanguage) {
                            viewModel.changeFilter(kind)
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            // 2. 右侧紧凑情境筛选与状态
            HStack(spacing: 4) {
                // 如果当前有时段或来源过滤激活，展示小巧激活标签与快捷清除
                if viewModel.contextFilter.isActive {
                    HStack(spacing: 3) {
                        Text(activeFilterTitle)
                            .font(.system(size: 9.5, weight: .medium))
                            .lineLimit(1)
                        Button {
                            viewModel.clearContextFilter()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
                    .help(L10n.tr("filter.clear_context", lang: settings.appLanguage))
                }

                // 综合情境过滤下拉菜单 (时间 + 来源)
                Menu {
                    Section {
                        ForEach(TimeFilter.allCases) { time in
                            Button {
                                viewModel.setTimeFilter(time)
                            } label: {
                                if viewModel.timeFilter == time {
                                    Label(L10n.timeTitle(time, lang: settings.appLanguage), systemImage: "checkmark")
                                } else {
                                    Text(L10n.timeTitle(time, lang: settings.appLanguage))
                                }
                            }
                        }
                    } header: {
                        Text(L10n.tr("filter.time_scope", lang: settings.appLanguage))
                    }

                    Section {
                        Button {
                            viewModel.setSourceFilter(nil)
                        } label: {
                            if viewModel.sourceFilter == nil {
                                Label(L10n.tr("filter.all_sources", lang: settings.appLanguage), systemImage: "checkmark")
                            } else {
                                Text(L10n.tr("filter.all_sources", lang: settings.appLanguage))
                            }
                        }
                        if !viewModel.availableSources.isEmpty {
                            Divider()
                            ForEach(viewModel.availableSources) { source in
                                Button {
                                    viewModel.setSourceFilter(source.bundle)
                                } label: {
                                    if viewModel.sourceFilter == source.bundle {
                                        Label("\(source.name) (\(source.count))", systemImage: "checkmark")
                                    } else {
                                        Text("\(source.name) (\(source.count))")
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(L10n.tr("filter.source_scope", lang: settings.appLanguage))
                    }
                } label: {
                    Image(systemName: viewModel.contextFilter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 11.5))
                        .foregroundStyle(viewModel.contextFilter.isActive ? Color.accentColor : Color.secondary)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(viewModel.contextFilter.isActive ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                        )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L10n.tr("filter.context_tooltip", lang: settings.appLanguage))

                // 暂停采集指示灯
                if settings.pauseCapture {
                    HStack(spacing: 3) {
                        Circle().fill(Color.orange).frame(width: 5, height: 5)
                        Text(L10n.tr("filter.paused", lang: settings.appLanguage))
                            .font(.system(size: 9.5))
                            .foregroundStyle(Color.orange)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
                }
            }
            .padding(.trailing, 10)
        }
        .padding(.vertical, 3)
    }

    private var activeFilterTitle: String {
        var parts: [String] = []
        if viewModel.timeFilter != .all {
            parts.append(L10n.timeTitle(viewModel.timeFilter, lang: settings.appLanguage))
        }
        if let sourceName = viewModel.sourceFilterName {
            parts.append(sourceName)
        }
        return parts.joined(separator: " / ")
    }
}

private struct FilterChip: View {
    let kind: FilterKind
    let selected: Bool
    var lang: AppLanguage = .system
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3.5) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 9.5))
                Text(L10n.filterTitle(kind, lang: lang))
                    .font(.system(size: 11, weight: selected ? .medium : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(selected ? Color.accentColor.opacity(0.15) : (hovered ? Color.primary.opacity(0.05) : Color.clear))
            )
            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - 常用片段子分组栏

struct SnippetGroupBar: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button {
                    viewModel.changeSnippetGroup(nil)
                } label: {
                    Text(L10n.tr("snippets.all_groups", lang: viewModel.settings.appLanguage))
                        .font(.system(size: 10.5, weight: viewModel.snippetGroup == nil ? .semibold : .regular))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(viewModel.snippetGroup == nil ? Palette.snippet.opacity(0.18) : Color.primary.opacity(0.06)))
                        .foregroundStyle(viewModel.snippetGroup == nil ? Palette.snippet : Color.secondary)
                }
                .buttonStyle(.plain)

                ForEach(viewModel.availableSnippetGroups, id: \.self) { group in
                    Button {
                        viewModel.changeSnippetGroup(group)
                    } label: {
                        Text(group)
                            .font(.system(size: 10.5, weight: viewModel.snippetGroup == group ? .semibold : .regular))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(viewModel.snippetGroup == group ? Palette.snippet.opacity(0.18) : Color.primary.opacity(0.06)))
                            .foregroundStyle(viewModel.snippetGroup == group ? Palette.snippet : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 4)

                Button {
                    viewModel.openNewSnippet()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                        Text(L10n.tr("snippets.new", lang: viewModel.settings.appLanguage))
                            .font(.system(size: 10))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Capsule().strokeBorder(Palette.snippet.opacity(0.35), lineWidth: 1))
                    .foregroundStyle(Palette.snippet)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
        }
    }
}

// MARK: - 历史列表

struct ClipList: View {
    @ObservedObject var viewModel: PanelViewModel
    @State private var lastClickTime: TimeInterval = 0
    @State private var lastClickID: Int64 = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ModernScrollViewConfigurator()
                    .frame(width: 0, height: 0)
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.items) { item in
                        let isSelected = item.id == viewModel.selectedID
                        let fields = isSelected ? viewModel.fields(for: item) : []
                        let recAction = isSelected ? viewModel.recommendedAction(for: item) : nil
                        let actionResult = isSelected ? viewModel.activeActionResult : nil
                        ClipRowView(
                            item: item,
                            selected: isSelected,
                            multiSelected: viewModel.multiSelectedIDs.contains(item.id),
                            thumbnail: viewModel.thumbnail(for: item),
                            searchHighlight: viewModel.query,
                            language: viewModel.settings.appLanguage,
                            theme: viewModel.settings.appTheme,
                            fields: fields,
                            selectedFieldIndex: isSelected ? viewModel.selectedFieldIndex : nil,
                            isExpanded: viewModel.isFieldsExpanded(for: item.id),
                            onToggleExpand: { viewModel.toggleExpandFields(for: item.id) },
                            onPasteField: { field in viewModel.pasteField(field) },
                            onCopyField: { field in viewModel.copyField(field) },
                            onCopyOCR: { viewModel.copyFieldText(item.plainText) },
                            recommendedAction: recAction,
                            activeActionResult: actionResult,
                            onExecuteAction: { action in viewModel.executeAction(action, on: item) },
                            onCancelAction: { viewModel.cancelAction() },
                            onRetryAction: { viewModel.retryAction() },
                            onToggleOriginal: { viewModel.toggleActionResultOriginal() },
                            onDismissAction: { viewModel.dismissActionResult() },
                            onPasteActionResult: { viewModel.pasteActionResult() },
                            onCopyActionResult: { viewModel.copyActionResult() },
                            onChangeTargetLanguage: { lang in viewModel.executeAction(.translate, on: item, targetLanguage: lang) },
                            onMuteAction: { action in viewModel.muteAction(action) },
                            interactiveSessionBinding: isSelected ? viewModel.bindingForInteractiveSession(for: item) : nil,
                            onPasteInteractive: { viewModel.pasteInteractiveResult(for: item.id) },
                            onCopyInteractive: { viewModel.copyInteractiveResult(for: item.id) },
                            onResetInteractive: { viewModel.resetInteractiveSession(itemID: item.id) },
                            onToggleInteractiveLock: { depId in viewModel.toggleInteractiveLock(itemID: item.id, dependentID: depId) },
                            onResolveInteractiveMissing: { val in viewModel.resolveMissingConstraint(itemID: item.id, baseValue: val) }
                        )
                        .equatable()

                        .id(item.id)
                        .onTapGesture {
                            let now = ProcessInfo.processInfo.systemUptime
                            if now - lastClickTime < 0.35 && lastClickID == item.id {
                                viewModel.paste(item: item)
                            } else {
                                viewModel.selectOnly(item: item)
                            }
                            lastClickTime = now
                            lastClickID = item.id
                        }
                        .contextMenu { ContextMenuItems(viewModel: viewModel, item: item) }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            // 切换分类时重置滚动视图至顶部，避免旧偏移量导致的白屏/列表内容出界
            .id(viewModel.filter)
            .onChange(of: viewModel.selectedID) { newID in
                guard let newID else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo(newID)
                }
            }
            .modernScrollbar()
        }
    }
}

struct ContextMenuItems: View {
    let viewModel: PanelViewModel
    let item: ClipItem

    var body: some View {
        Button(L10n.tr("action.paste")) { viewModel.paste(item: item) }
        Button(L10n.tr("action.paste_plain")) { viewModel.pasteAsPlainText(item: item) }
        Button(L10n.tr("action.copy")) { viewModel.copy(item: item) }
        Button(L10n.tr("action.copy_plain")) { viewModel.copyAsPlainText(item: item) }
        Button(item.pinned ? L10n.tr("action.unpin") : L10n.tr("action.pin")) { viewModel.togglePin(item) }
        if item.isSnippet {
            Button(L10n.tr("action.edit_snippet")) { viewModel.openEditSnippet(item: item) }
            Button(L10n.tr("action.remove_snippet")) { viewModel.toggleSnippet(item: item) }
        } else {
            Button(L10n.tr("action.save_snippet")) { viewModel.openEditSnippet(item: item) }
        }
        if item.kind != .image {
            Button(L10n.tr("action.edit_item")) { viewModel.beginEdit(item: item) }
        }
        Button(L10n.tr("action.rename")) { viewModel.beginRename(item: item) }
        if item.isUserTitled {
            Button(L10n.tr("action.clear_title")) { viewModel.clearTitle(item: item) }
        }
        Button(L10n.tr("action.preview")) { viewModel.togglePreview(item: item) }
        Button(viewModel.queue.contains { $0.id == item.id } ? L10n.tr("action.queue_remove") : L10n.tr("action.queue_add")) {
            _ = viewModel.toggleQueue(item: item)
        }
        Button(L10n.tr("action.ai_actions")) { viewModel.openAI(item: item) }
        Button(L10n.tr("action.create_draft")) {
            viewModel.selectOnly(item: item)
            viewModel.createDraftFromSelected()
        }
        if viewModel.activeDraft != nil {
            Button(L10n.tr("action.add_to_draft")) {
                viewModel.addSourceToActiveDraft(item: item)
            }
        }
        Divider()
        if viewModel.multiSelectedIDs.count > 1 {
            Button(L10n.tr("batch.create_draft")) {
                viewModel.createDraftFromSelected()
            }
            Button(L10n.tr("batch.copy_count", viewModel.multiSelectedIDs.count)) {
                viewModel.copyMulti()
            }
            Button(L10n.tr("batch.toggle_pin")) {
                viewModel.togglePinMulti()
            }
            Button(L10n.tr("batch.add_queue")) {
                viewModel.enqueueMulti()
            }
            Button(L10n.tr("batch.delete_count", viewModel.multiSelectedIDs.count), role: .destructive) {
                viewModel.deleteMulti()
            }
            Divider()
        }
        Button(L10n.tr("action.delete"), role: .destructive) { viewModel.delete(item: item) }
    }
}

// MARK: - 空态

struct EmptyStateView: View {
    let query: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.quaternary)
            Text(query.isEmpty ? L10n.tr("empty.title") : L10n.tr("empty.no_match"))
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(query.isEmpty ? L10n.tr("empty.subtitle") : L10n.tr("empty.no_match_sub"))
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

// MARK: - 底部快捷键提示

struct FooterBar: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 9) {
            KeyHint("⏎", L10n.tr("footer.paste", lang: settings.appLanguage))
            KeyHint("⌘⏎", L10n.tr("footer.copy", lang: settings.appLanguage))
            KeyHint("⌘I", L10n.tr("footer.preview", lang: settings.appLanguage))
            KeyHint("⌘K", L10n.tr("footer.ai", lang: settings.appLanguage))
            KeyHint("⌘⌫", L10n.tr("footer.delete", lang: settings.appLanguage))
            Spacer()
            KeyHint("Esc", L10n.tr("footer.cancel", lang: settings.appLanguage))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.02))
    }
}

private struct KeyHint: View {
    let key: String
    let action: String

    init(_ key: String, _ action: String) {
        self.key = key
        self.action = action
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .foregroundStyle(.secondary)
            Text(action)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - 批量操作栏

struct BatchActionBar: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        HStack(spacing: 6) {
            Text(L10n.tr("batch.selected", viewModel.multiSelectedIDs.count, lang: viewModel.settings.appLanguage))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Capsule().fill(Color.accentColor.opacity(0.12)))

            Spacer()

            Button {
                viewModel.copyMulti()
            } label: {
                Label(L10n.tr("batch.copy_all", lang: viewModel.settings.appLanguage), systemImage: "doc.on.doc")
            }
            .clipMateGlass(size: .small)

            Button {
                viewModel.createDraftFromSelected()
            } label: {
                Label(L10n.tr("batch.create_draft", lang: viewModel.settings.appLanguage), systemImage: "square.and.pencil")
            }
            .clipMateAccent(size: .small)

            HStack(spacing: 2) {
                Button {
                    viewModel.togglePinMulti()
                } label: {
                    Image(systemName: "pin")
                }
                .clipMateIconButton(size: 22)
                .help(L10n.tr("batch.pin_all", lang: viewModel.settings.appLanguage))

                Button {
                    viewModel.enqueueMulti()
                } label: {
                    Image(systemName: "list.number")
                }
                .clipMateIconButton(size: 22)
                .help(L10n.tr("batch.paste_queue", lang: viewModel.settings.appLanguage))

                Button(role: .destructive) {
                    viewModel.deleteMulti()
                } label: {
                    Image(systemName: "trash")
                }
                .clipMateIconButton(size: 22, tint: .red)
                .help(L10n.tr("batch.delete_all", lang: viewModel.settings.appLanguage))

                Button {
                    viewModel.clearMultiSelection()
                } label: {
                    Image(systemName: "xmark")
                }
                .clipMateIconButton(size: 22)
                .help(L10n.tr("batch.cancel", lang: viewModel.settings.appLanguage))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4.5)
        .background(Color.accentColor.opacity(0.08))
        .overlay(
            Rectangle()
                .frame(height: 0.8)
                .foregroundStyle(Color.accentColor.opacity(0.15)),
            alignment: .top
        )
    }
}

