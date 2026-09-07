import SwiftUI
import AppKit

/// 主面板状态与动作。所有公开方法约定在主线程调用（SwiftUI/键盘监听/采集回调均在主线程）。
public final class PanelViewModel: ObservableObject {
    @Published public var query = ""
    @Published public var filter: FilterKind = .all
    @Published public var items: [ClipItem] = []
    @Published public var selectedIndex = 0
    /// 选中锚点：以条目 id 记录，列表重排（新采集置顶等）后选中不漂移。
    @Published public var selectedID: Int64?
    @Published public var showEditOverlay = false
    @Published public var editText = ""
    @Published public var showConfirmClear = false
    /// 粘贴队列（会话内有效，按序批量粘贴）。
    @Published public var queue: [ClipItem] = []
    /// 详情预览浮层当前条目。
    @Published public var previewItem: ClipItem?
    /// 批量多选（⇧↑↓ 扩展，存条目 id 以免列表刷新错位）。
    @Published public var multiSelectedIDs: Set<Int64> = []

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

    // MARK: - 数据

    public func reload(resetSelection: Bool = false) {
        let q = query
        let f = filter
        if q.isEmpty {
            searchTask?.cancel()
            searchTask = nil
            let results = store.search(query: q, filter: f, limit: 300)
            applySearchResults(results, resetSelection: resetSelection)
        } else {
            searchTask?.cancel()
            let store = self.store
            searchTask = Task.detached(priority: .userInitiated) { [weak self] in
                let results = store.search(query: q, filter: f, limit: 300)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self, self.query == q, self.filter == f else { return }
                    self.applySearchResults(results, resetSelection: resetSelection)
                }
            }
        }
    }

    public func queryChanged() {
        searchTask?.cancel()
        let q = query
        let f = filter
        if q.isEmpty {
            reload(resetSelection: true)
            return
        }
        let store = self.store
        searchTask = Task.detached(priority: .userInitiated) { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            let results = store.search(query: q, filter: f, limit: 300)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.query == q, self.filter == f else { return }
                self.applySearchResults(results, resetSelection: true)
            }
        }
    }

    private func applySearchResults(_ newItems: [ClipItem], resetSelection: Bool = false) {
        items = newItems
        if resetSelection || selectedID == nil {
            selectedIndex = 0
            selectedID = items.first?.id
        } else if let id = selectedID, let index = items.firstIndex(where: { $0.id == id }) {
            selectedIndex = index
        } else if selectedIndex >= items.count {
            selectedIndex = max(0, items.count - 1)
            selectedID = items.indices.contains(selectedIndex) ? items[selectedIndex].id : nil
        } else {
            selectedID = items.indices.contains(selectedIndex) ? items[selectedIndex].id : nil
        }
        // 多选只对当前可见列表有意义，清理失效引用
        let visibleIDs = Set(items.map(\.id))
        multiSelectedIDs.formIntersection(visibleIDs)
    }

    public func handleCaptured(_ item: ClipItem) {
        reload()
    }

    public var selectedItem: ClipItem? {
        if let id = selectedID, let item = items.first(where: { $0.id == id }) {
            return item
        }
        return items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    // MARK: - 选择与过滤

    public func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        let nextIndex = min(max(0, selectedIndex + delta), items.count - 1)
        selectedIndex = nextIndex
        selectedID = items[nextIndex].id
    }

    public func cycleFilter() {
        let all = FilterKind.allCases
        guard let index = all.firstIndex(of: filter) else { return }
        changeFilter(all[(index + 1) % all.count])
    }

    /// 切换分类：多选清除，选中重置到首项，刷新列表
    public func changeFilter(_ kind: FilterKind) {
        guard filter != kind else { return }
        filter = kind
        clearMultiSelection()
        selectedIndex = 0
        selectedID = nil
        reload(resetSelection: true)
    }

    /// 单选语义：点击行 = 只选中这一行，清除批量多选残留。
    public func selectOnly(at index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
        selectedID = items[index].id
        clearMultiSelection()
    }

    public func selectOnly(item: ClipItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            selectedIndex = index
            selectedID = item.id
            clearMultiSelection()
        }
    }

    // MARK: - 动作

    public func pasteSelected() {
        guard let item = selectedItem else { return }
        paste(item: item)
    }

    /// 忽略富文本格式，按纯文本粘贴/复制。
    public func pasteAsPlainText(item: ClipItem? = nil) {
        let target = item ?? selectedItem
        guard let target else { return }
        pasteContent(.text(target.plainText))
    }

    public func copyAsPlainText(item: ClipItem? = nil) {
        let target = item ?? selectedItem
        guard let target else { return }
        PasteBack.write(.text(target.plainText))
        monitor.suppress(seconds: 1.5)
    }

    public func paste(item: ClipItem) {
        pasteContent(store.pasteboardContent(for: item))
    }

    public func pasteIndex(_ index: Int) {
        guard items.indices.contains(index) else { return }
        selectOnly(at: index)
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

    // MARK: - 批量多选

    /// ⇧↑/⇧↓ 扩展多选（从当前选中行起）。
    public func extendSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        if multiSelectedIDs.isEmpty, items.indices.contains(selectedIndex) {
            multiSelectedIDs.insert(items[selectedIndex].id)
        }
        let next = min(max(0, selectedIndex + delta), items.count - 1)
        selectedIndex = next
        selectedID = items[next].id
        multiSelectedIDs.insert(items[next].id)
    }

    public func clearMultiSelection() {
        multiSelectedIDs.removeAll()
    }

    public func deleteMulti() {
        guard !multiSelectedIDs.isEmpty else { return }
        for id in multiSelectedIDs {
            try? store.delete(id)
        }
        multiSelectedIDs.removeAll()
        reload()
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
        guard item.kind == .image else { return nil }
        let key = NSNumber(value: item.id)
        if let cached = thumbCache.object(forKey: key) { return cached }
        guard let data = item.inlineData ?? store.inlineData(for: item.id) else { return nil }
        guard let image = NSImage(data: data) else { return nil }
        thumbCache.setObject(image, forKey: key)
        return image
    }
}
