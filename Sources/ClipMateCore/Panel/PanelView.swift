import SwiftUI
import AppKit

/// 主面板：搜索栏 + 分类 chips + 历史列表 + 快捷键提示条。
struct PanelView: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        panelCard
            .frame(width: 720, height: 540) // 窗口比内容大一圈：给 SwiftUI 阴影留出绘制空间
    }

    private var panelCard: some View {
        ZStack {
            VStack(spacing: 0) {
                SearchBar(viewModel: viewModel)
                FilterChips(viewModel: viewModel)
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
                    FooterBar()
                }
            }
            .disabled(viewModel.showEditOverlay || viewModel.showSnippetOverlay || viewModel.showConfirmClear || viewModel.previewItem != nil)

            if viewModel.showEditOverlay { EditOverlay(viewModel: viewModel) }
            if viewModel.showSnippetOverlay { SnippetEditOverlay(viewModel: viewModel) }
            if viewModel.showConfirmClear { ConfirmClearOverlay(viewModel: viewModel) }
            if viewModel.previewItem != nil { PreviewOverlay(viewModel: viewModel) }
        }
        .frame(width: 660, height: 480)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
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
            TextField(L10n.tr("search.placeholder"), text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))

                .focused($focused)
            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                    viewModel.reload()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(FilterKind.allCases, id: \.self) { kind in
                    Button {
                        viewModel.changeFilter(kind)
                    } label: {
                        Text(kind.title)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(
                                    viewModel.filter == kind
                                        ? Color.accentColor.opacity(0.18)
                                        : Color.primary.opacity(0.06)
                                )
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    viewModel.filter == kind ? Color.accentColor.opacity(0.45) : .clear,
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(viewModel.filter == kind ? Color.accentColor : Color.secondary)
                }
                Spacer()
                if !viewModel.queue.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "list.number")
                        Text("队列 \(viewModel.queue.count)")
                        Button {
                            viewModel.clearQueue()
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 9))
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .help("按 ⌘⇧⏎ 顺序粘贴队列内容")
                }
                if settings.pauseCapture {
                    Label("已暂停采集", systemImage: "pause.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }

            if viewModel.filter == .snippet {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        Button {
                            viewModel.changeSnippetGroup(nil)
                        } label: {
                            Text("全部片段")
                                .font(.system(size: 10.5, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2.5)
                                .background(Capsule().fill(viewModel.snippetGroup == nil ? Color.purple.opacity(0.22) : Color.primary.opacity(0.06)))
                                .foregroundStyle(viewModel.snippetGroup == nil ? Color.purple : Color.secondary)
                        }
                        .buttonStyle(.plain)

                        ForEach(viewModel.availableSnippetGroups, id: \.self) { group in
                            Button {
                                viewModel.changeSnippetGroup(group)
                            } label: {
                                Text(group)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2.5)
                                    .background(Capsule().fill(viewModel.snippetGroup == group ? Color.purple.opacity(0.22) : Color.primary.opacity(0.06)))
                                    .foregroundStyle(viewModel.snippetGroup == group ? Color.purple : Color.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            viewModel.openNewSnippet()
                        } label: {
                            Label("新建片段", systemImage: "plus")
                                .font(.system(size: 10.5, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2.5)
                                .background(Capsule().strokeBorder(Color.purple.opacity(0.4), lineWidth: 1))
                                .foregroundStyle(Color.purple)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .modernScrollbar()
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
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
                        ClipRowView(
                            item: item,
                            selected: item.id == viewModel.selectedID,
                            multiSelected: viewModel.multiSelectedIDs.contains(item.id),
                            thumbnail: viewModel.thumbnail(for: item)
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
        Button("粘贴") { viewModel.paste(item: item) }
        Button("粘贴为纯文本") { viewModel.pasteAsPlainText(item: item) }
        Button("复制") { viewModel.copy(item: item) }
        Button("复制为纯文本") { viewModel.copyAsPlainText(item: item) }
        Button(item.pinned ? "取消固定" : "固定 ★") { viewModel.togglePin(item) }
        if item.isSnippet {
            Button("编辑片段…") { viewModel.openEditSnippet(item: item) }
            Button("移出片段") { viewModel.toggleSnippet(item: item) }
        } else {
            Button("存为片段…") { viewModel.openEditSnippet(item: item) }
        }
        if item.kind != .image {
            Button("编辑…") { viewModel.beginEdit(item: item) }
        }
        Button("详情预览") { viewModel.togglePreview(item: item) }
        Button(viewModel.queue.contains { $0.id == item.id } ? "移出粘贴队列" : "加入粘贴队列") {
            _ = viewModel.toggleQueue(item: item)
        }
        Button("AI 操作…") { viewModel.openAI(item: item) }
        Divider()
        if viewModel.multiSelectedIDs.count > 1 {
            Button("合并复制选中的 \(viewModel.multiSelectedIDs.count) 条") {
                viewModel.copyMulti()
            }
            Button("批量固定 / 取消固定") {
                viewModel.togglePinMulti()
            }
            Button("批量加入粘贴队列") {
                viewModel.enqueueMulti()
            }
            Button("删除选中的 \(viewModel.multiSelectedIDs.count) 条", role: .destructive) {
                viewModel.deleteMulti()
            }
            Divider()
        }
        Button("删除", role: .destructive) { viewModel.delete(item: item) }
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
    var body: some View {
        HStack(spacing: 12) {
            KeyHint("⏎", L10n.tr("footer.paste"))
            KeyHint("⌘⏎", L10n.tr("footer.copy"))
            KeyHint("⌘I", L10n.tr("footer.preview"))
            KeyHint("⇧⏎", L10n.tr("batch.paste_queue"))
            KeyHint("⌘⌥⏎", "纯文本")
            KeyHint("⌘K", L10n.tr("footer.ai"))
            KeyHint("⌫", L10n.tr("footer.delete"))
            Spacer()
            KeyHint("Esc", L10n.tr("batch.cancel"))
        }
        .padding(.horizontal, 12)
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
            Text(L10n.tr("batch.selected", viewModel.multiSelectedIDs.count))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Spacer()

            Button {
                viewModel.copyMulti()
            } label: {
                Label(L10n.tr("batch.copy_all"), systemImage: "doc.on.doc")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                viewModel.togglePinMulti()
            } label: {
                Label(L10n.tr("batch.pin_all"), systemImage: "pin")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                viewModel.enqueueMulti()
            } label: {
                Label(L10n.tr("batch.paste_queue"), systemImage: "list.number")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(role: .destructive) {
                viewModel.deleteMulti()
            } label: {
                Label(L10n.tr("batch.delete_all"), systemImage: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                viewModel.clearMultiSelection()
            } label: {
                Label(L10n.tr("batch.cancel"), systemImage: "xmark")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.12))
    }
}


