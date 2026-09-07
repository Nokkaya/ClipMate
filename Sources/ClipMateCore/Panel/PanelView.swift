import SwiftUI
import AppKit

/// 主面板：搜索栏 + 分类 chips + 历史列表 + 快捷键提示条。
struct PanelView: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        ZStack {
            mainContent
            if viewModel.showEditOverlay { EditOverlay(viewModel: viewModel) }
            if viewModel.showConfirmClear { ConfirmClearOverlay(viewModel: viewModel) }
            if viewModel.previewItem != nil { PreviewOverlay(viewModel: viewModel) }
        }
        .frame(width: 660, height: 480)
    }

    private var mainContent: some View {
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
            FooterBar()
        }
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
            TextField("搜索剪贴板历史…", text: $viewModel.query)
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
        HStack(spacing: 6) {
            ForEach(FilterKind.allCases, id: \.self) { kind in
                Button {
                    viewModel.filter = kind
                    viewModel.reload()
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
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - 历史列表

struct ClipList: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                        ClipRowView(
                            item: item,
                            selected: index == viewModel.selectedIndex,
                            hovered: viewModel.hoverIndex == index,
                            multiSelected: viewModel.multiSelectedIDs.contains(item.id),
                            thumbnail: viewModel.thumbnail(for: item)
                        )
                        .id(index)
                        .onTapGesture(count: 2) {
                            viewModel.selectedIndex = index
                            viewModel.pasteIndex(index)
                        }
                        .onTapGesture {
                            viewModel.selectedIndex = index
                        }
                        .onHover { hovering in
                            viewModel.hoverIndex = hovering ? index : (viewModel.hoverIndex == index ? nil : viewModel.hoverIndex)
                        }
                        .contextMenu { ContextMenuItems(viewModel: viewModel, item: item) }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .onChange(of: viewModel.selectedIndex) { newValue in
                proxy.scrollTo(newValue, anchor: .center)
            }
            .scrollIndicators(.hidden)
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
        Button(item.tags.contains(FilterKind.snippetTag) ? "移出片段" : "存为片段") {
            viewModel.toggleSnippet(item: item)
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
            Button("删除选中的 \(viewModel.multiSelectedIDs.count) 条", role: .destructive) {
                viewModel.deleteMulti()
            }
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
            Text(query.isEmpty ? "暂无剪贴板历史" : "没有匹配的结果")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text(query.isEmpty ? "复制任意内容后会自动出现在这里" : "换个关键词试试")
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
            KeyHint("⏎", "粘贴")
            KeyHint("⌘⏎", "复制")
            KeyHint("⌘I", "预览")
            KeyHint("⇧⏎", "入队")
            KeyHint("⌘⇧⏎", "连贴")
            KeyHint("⌘⌥⏎", "纯文本")
            KeyHint("⌘K", "AI")
            KeyHint("⇧↑↓", "多选")
            KeyHint("⌫", "删除")
            Spacer()
            KeyHint("Esc", "隐藏")
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
