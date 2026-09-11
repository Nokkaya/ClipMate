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
                    FilterChips(viewModel: viewModel)
                    ContextFilterBar(viewModel: viewModel)
                    // 片段分类下展示分组栏（全部 / 各分组 / 新建片段）
                    if viewModel.filter == .snippet {
                        SnippetGroupBar(viewModel: viewModel)
                    }
                    Divider().overlay(Color.primary.opacity(0.08))
                    if viewModel.items.isEmpty {
                        EmptyStateView(query: viewModel.query)
                    } else {
                        ClipList(viewModel: viewModel)
                    }
                    Divider().overlay(Color.primary.opacity(0.08))
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
                .foregroundStyle(.secondary)
            TextField(L10n.tr("search.placeholder", lang: viewModel.settings.appLanguage), text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focused)
                .help(L10n.tr("search.syntax_hint", lang: viewModel.settings.appLanguage))

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                    viewModel.reload()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .clipMateIconButton(size: 20)
            }

            let theme = viewModel.settings.appTheme
            // AI 问答侧边栏快速展开/收起切换按钮
            Button {
                viewModel.toggleAISidebar()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                    Text("AI")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(viewModel.isAISidebarOpen ? theme.accent.opacity(0.18) : Color.primary.opacity(0.06))
                )
                .foregroundStyle(viewModel.isAISidebarOpen ? theme.accent : Color.secondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(viewModel.isAISidebarOpen ? theme.accent.opacity(0.4) : Color.clear, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help(L10n.tr("search.help", lang: viewModel.settings.appLanguage))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onAppear { focused = true }
        .onReceive(NotificationCenter.default.publisher(for: .clipmateFocusSearch)) { _ in
            focused = true
        }
        .onChange(of: viewModel.query) { _ in
            viewModel.queryChanged()
        }
    }
}

// MARK: - 分类过滤

struct FilterChips: View {
    @ObservedObject var viewModel: PanelViewModel
    @ObservedObject var settings: AppSettings

    init(viewModel: PanelViewModel) {
        self.viewModel = viewModel
        self.settings = viewModel.settings
    }

    var body: some View {
        // 固定 4 列网格：分类增至 8 个后仍能全部可见可点（横向滚动在面板里不可用）
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4),
            spacing: 4
        ) {
            ForEach(FilterKind.allCases) { kind in
                FilterChip(kind: kind, selected: viewModel.filter == kind, lang: settings.appLanguage) {
                    viewModel.changeFilter(kind)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

// MARK: - 情境过滤（来源应用 + 时间范围）

/// 把"我记得是昨天从微信复制的"变成可点选的条件。
struct ContextFilterBar: View {
    @ObservedObject var viewModel: PanelViewModel
    @ObservedObject var settings: AppSettings

    init(viewModel: PanelViewModel) {
        self.viewModel = viewModel
        self.settings = viewModel.settings
    }

    var body: some View {
        HStack(spacing: 6) {
            Menu {
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
            } label: {
                menuLabel(
                    icon: "clock",
                    text: L10n.timeTitle(viewModel.timeFilter, lang: settings.appLanguage),
                    active: viewModel.timeFilter != .all
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Menu {
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
            } label: {
                menuLabel(
                    icon: "app.badge",
                    text: viewModel.sourceFilterName ?? L10n.tr("filter.all_sources", lang: settings.appLanguage),
                    active: viewModel.sourceFilter != nil
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            if viewModel.contextFilter.isActive {
                Button {
                    viewModel.clearContextFilter()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                }
                .clipMateIconButton(size: 18)
                .help(L10n.tr("filter.clear_context", lang: settings.appLanguage))
            }

            Spacer()

            if settings.pauseCapture {
                HStack(spacing: 3) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text(L10n.tr("filter.paused", lang: settings.appLanguage))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.orange)
                }
                .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    private func menuLabel(icon: String, text: String, active: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9.5))
            Text(text)
                .font(.system(size: 10.5, weight: active ? .medium : .regular))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(active ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05)))
        .foregroundStyle(active ? Color.accentColor : Color.secondary)
        .contentShape(Capsule())
    }
}

private struct FilterChip: View {
    let kind: FilterKind
    let selected: Bool
    var lang: AppLanguage = .system
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 10))
                Text(L10n.filterTitle(kind, lang: lang))
                    .font(.system(size: 11, weight: selected ? .medium : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04))
            )
            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
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
                            onChangeTargetLanguage: { lang in viewModel.executeAction(.translate, on: item, targetLanguage: lang) }
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
        Divider()
        if viewModel.multiSelectedIDs.count > 1 {
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
        VStack(spacing: 8) {
            Image(systemName: query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 34))
                .foregroundStyle(.quaternary)
            Text(query.isEmpty ? L10n.tr("empty.title") : L10n.tr("empty.no_match"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text(query.isEmpty ? L10n.tr("empty.subtitle") : L10n.tr("empty.no_match_sub"))
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 底部快捷键提示

struct FooterBar: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 8) {
            KeyHint("⏎", L10n.tr("footer.paste", lang: settings.appLanguage))
            KeyHint("⌘⏎", L10n.tr("footer.copy", lang: settings.appLanguage))
            KeyHint("⌘I", L10n.tr("footer.preview", lang: settings.appLanguage))
            KeyHint("⌘K", L10n.tr("footer.ai", lang: settings.appLanguage))
            KeyHint("⌫", L10n.tr("footer.delete", lang: settings.appLanguage))
            Spacer()
            KeyHint("Esc", L10n.tr("footer.cancel", lang: settings.appLanguage))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.04))
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
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.09)))
            Text(action)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 批量操作栏

struct BatchActionBar: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        HStack(spacing: 8) {
            Text(L10n.tr("batch.selected", viewModel.multiSelectedIDs.count, lang: viewModel.settings.appLanguage))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Spacer()

            Button {
                viewModel.copyMulti()
            } label: {
                Label(L10n.tr("batch.copy_all", lang: viewModel.settings.appLanguage), systemImage: "doc.on.doc")
            }
            .clipMateAccent(size: .small)

            Button {
                viewModel.togglePinMulti()
            } label: {
                Label(L10n.tr("batch.pin_all", lang: viewModel.settings.appLanguage), systemImage: "pin")
            }
            .clipMateGlass(size: .small)

            Button {
                viewModel.enqueueMulti()
            } label: {
                Label(L10n.tr("batch.paste_queue", lang: viewModel.settings.appLanguage), systemImage: "list.number")
            }
            .clipMateGlass(size: .small)

            Button(role: .destructive) {
                viewModel.deleteMulti()
            } label: {
                Label(L10n.tr("batch.delete_all", lang: viewModel.settings.appLanguage), systemImage: "trash")
            }
            .clipMateDanger(prominent: false, size: .small)

            Button {
                viewModel.clearMultiSelection()
            } label: {
                Label(L10n.tr("batch.cancel", lang: viewModel.settings.appLanguage), systemImage: "xmark")
            }
            .clipMateGlass(size: .small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.12))
    }
}

