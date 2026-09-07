import SwiftUI
import AppKit

/// 主面板状态与动作。所有公开方法约定在主线程调用（SwiftUI/键盘监听/采集回调均在主线程）。
public final class PanelViewModel: ObservableObject {
    @Published public var query = ""
    @Published public var filter: FilterKind = .all
    @Published public var items: [ClipItem] = []
    @Published public var selectedIndex = 0
    @Published public var hoverIndex: Int?
    @Published public var showEditOverlay = false
    @Published public var editText = ""
    @Published public var showConfirmClear = false
    /// 粘贴队列（会话内有效，按序批量粘贴）。
    @Published public var queue: [ClipItem] = []
    /// 详情预览浮层当前条目。
    @Published public var previewItem: ClipItem?

    /// AI 工作台独立窗口（⌘K），由 AppModel 装配注入。
    weak var aiWorkspace: AIWorkspaceController?

    public let store: ClipStore
    public let settings: AppSettings
    public let ai: AIService
    let monitor: ClipboardMonitor
    let frontApps: FrontAppTracker

    /// 面板可见期间记录的粘贴目标（唤起前的前台应用）。
    public var pasteTarget: NSRunningApplication?
    var dismiss: (() -> Void)?
    var openSettings: (() -> Void)?

    private var searchTask: Task<Void, Never>?
    private let thumbCache = NSCache<NSNumber, NSImage>()

    public init(store: ClipStore, settings: AppSettings, monitor: ClipboardMonitor,
                frontApps: FrontAppTracker, ai: AIService) {
        self.store = store
        self.settings = settings
        self.monitor = monitor
        self.frontApps = frontApps
        self.ai = ai
    }

    // MARK: - 数据

    public func reload() {
        items = store.search(query: query, filter: filter, limit: 300)
        if selectedIndex >= items.count {
            selectedIndex = max(0, items.count - 1)
        }
    }

    public func queryChanged() {
        searchTask?.cancel()
        searchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    public func handleCaptured(_ item: ClipItem) {
        reload()
    }

    public var selectedItem: ClipItem? {
        items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    // MARK: - 选择与过滤

    public func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = min(max(0, selectedIndex + delta), items.count - 1)
    }

    public func cycleFilter() {
        let all = FilterKind.allCases
        guard let index = all.firstIndex(of: filter) else { return }
        filter = all[(index + 1) % all.count]
        reload()
    }

    // MARK: - 动作

    public func pasteSelected() {
        guard let item = selectedItem else { return }
        paste(item: item)
    }

    public func paste(item: ClipItem) {
        pasteContent(store.pasteboardContent(for: item))
    }

    public func pasteIndex(_ index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
        paste(item: items[index])
    }

    private func pasteContent(_ content: PasteboardContent?) {
        guard let content else { return }
        let target = pasteTarget
        dismiss?()
        PasteBack.paste(content: content, toPID: target?.processIdentifier) { [weak self] seconds in
            self?.monitor.suppress(seconds: seconds)
        }
        if target == nil || !PasteBack.isAccessibilityGranted() {
            NSSound(named: "Basso")?.play() // 降级：仅写入剪贴板，提示用户手动 ⌘V
        }
    }

    public func copySelected() {
        guard let item = selectedItem else { return }
        copy(item: item)
    }

    public func copy(item: ClipItem) {
        guard let content = store.pasteboardContent(for: item) else { return }
        PasteBack.write(content)
        monitor.suppress(seconds: 1.5)
    }

    public func togglePin(_ item: ClipItem? = nil) {
        let target = item ?? selectedItem
        guard let target else { return }
        try? store.setPinned(target.id, !target.pinned)
        reload()
    }

    public func delete(item: ClipItem? = nil) {
        let target = item ?? selectedItem
        guard let target else { return }
        try? store.delete(target.id)
        reload()
    }

    public func beginEdit(item: ClipItem? = nil) {
        let target = item ?? selectedItem
        guard let target, target.kind != .image else { return }
        editText = target.plainText
        showEditOverlay = true
    }

    public func saveEdit() {
        guard let target = selectedItem else { return }
        try? store.updateText(target.id, editText)
        showEditOverlay = false
        reload()
        copy(item: store.item(id: target.id) ?? target)
    }

    public func requestClearAll() {
        showConfirmClear = true
    }

    public func confirmClearAll() {
        try? store.deleteAll(keepPinned: true)
        showConfirmClear = false
        queue.removeAll()
        reload()
    }

    // MARK: - 粘贴队列

    @discardableResult
    public func toggleQueue(item: ClipItem? = nil) -> Bool {
        let target = item ?? selectedItem
        guard let target else { return false }
        if let index = queue.firstIndex(where: { $0.id == target.id }) {
            queue.remove(at: index)
            return false
        }
        guard queue.count < 9 else { return false }
        queue.append(target)
        return true
    }

    public func clearQueue() {
        queue.removeAll()
    }

    /// 顺序粘贴队列内容，完成后清空队列。
    public func pasteQueue() {
        guard !queue.isEmpty else { return }
        let contents = queue.compactMap { store.pasteboardContent(for: $0) }
        let target = pasteTarget
        queue.removeAll()
        dismiss?()
        guard !contents.isEmpty else { return }
        PasteBack.pasteSequence(contents: contents, toPID: target?.processIdentifier) { [weak self] seconds in
            self?.monitor.suppress(seconds: seconds)
        }
        if target == nil || !PasteBack.isAccessibilityGranted() {
            NSSound(named: "Basso")?.play()
        }
    }

    // MARK: - 详情预览

    public func togglePreview(item: ClipItem? = nil) {
        let target = item ?? selectedItem
        if previewItem != nil, target == nil || target?.id == previewItem?.id {
            previewItem = nil
        } else if let target {
            previewItem = target
        }
    }

    // MARK: - 片段收藏（标签驱动）

    @discardableResult
    public func toggleSnippet(item: ClipItem? = nil) -> Bool {
        let target = item ?? selectedItem
        guard let target else { return false }
        let isSnippet = target.tags.contains(FilterKind.snippetTag)
        try? store.mutateTag(target.id, tag: FilterKind.snippetTag, add: !isSnippet)
        reload()
        return !isSnippet
    }

    public func clearTransientState() {
        showEditOverlay = false
        showConfirmClear = false
        previewItem = nil
    }

    // MARK: - AI 工作台（独立悬浮窗口，不覆盖主面板）

    public func openAI(item: ClipItem? = nil) {
        let target = item ?? selectedItem
        guard let target else { return }
        if let index = items.firstIndex(where: { $0.id == target.id }) { selectedIndex = index }
        aiWorkspace?.openOrFocus(item: target)
    }

    // MARK: - 缩略图

    public func thumbnail(for item: ClipItem) -> NSImage? {
        guard item.kind == .image, let data = item.inlineData else { return nil }
        let key = NSNumber(value: item.id)
        if let cached = thumbCache.object(forKey: key) { return cached }
        guard let image = NSImage(data: data) else { return nil }
        thumbCache.setObject(image, forKey: key)
        return image
    }
}
