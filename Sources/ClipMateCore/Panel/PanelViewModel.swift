import SwiftUI
import AppKit

/// AI 浮层状态机。
public struct AIOverlayState: Equatable {
    public var item: ClipItem
    public var action: AIAction?
    public var output: String = ""
    public var isRunning = false
    public var finished = false
    public var errorText: String?

    public static func == (lhs: AIOverlayState, rhs: AIOverlayState) -> Bool {
        lhs.item.id == rhs.item.id && lhs.output == rhs.output
            && lhs.isRunning == rhs.isRunning && lhs.finished == rhs.finished
            && lhs.errorText == rhs.errorText && lhs.action == rhs.action
    }
}

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
    @Published public var aiState: AIOverlayState?
    @Published public var aiCustomPrompt = ""

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
    private var aiTask: Task<Void, Never>?
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
        reload()
    }

    public func clearTransientState() {
        showEditOverlay = false
        showConfirmClear = false
        if aiState?.isRunning == true { aiTask?.cancel() }
        aiState = nil
    }

    // MARK: - AI

    public func openAI(item: ClipItem? = nil) {
        let target = item ?? selectedItem
        guard let target else { return }
        if let index = items.firstIndex(where: { $0.id == target.id }) { selectedIndex = index }
        aiState = AIOverlayState(item: target)
    }

    public func closeAI() {
        aiTask?.cancel()
        aiTask = nil
        aiState = nil
    }

    public func runAI(_ action: AIAction) {
        guard var state = aiState else { return }
        guard ai.isConfigured else {
            state.errorText = AIError.notConfigured.localizedDescription
            aiState = state
            return
        }
        state.action = action
        state.output = ""
        state.isRunning = true
        state.finished = false
        state.errorText = nil
        aiState = state

        let prompt = action.prompt(for: state.item.plainText, custom: aiCustomPrompt)
        aiTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for try await delta in self.ai.stream(prompt: prompt) {
                    self.aiState?.output += delta
                }
                if self.aiState?.isRunning == true {
                    self.aiState?.isRunning = false
                    self.aiState?.finished = true
                }
            } catch {
                self.aiState?.isRunning = false
                self.aiState?.errorText = "请求失败：\(error.localizedDescription)"
            }
        }
    }

    public func copyAIResult() {
        guard let output = aiState?.output, !output.isEmpty else { return }
        PasteBack.write(.text(output))
        monitor.suppress(seconds: 1.5)
    }

    public func replaceWithAIResult() {
        guard let state = aiState, !state.output.isEmpty else { return }
        _ = try? store.capture(
            kind: .text,
            plainText: state.output,
            sourceBundle: Bundle.main.bundleIdentifier ?? "",
            sourceName: "ClipMate",
            tags: ["AI"]
        )
        closeAI()
        reload()
    }

    public func pasteAIResult() {
        guard let state = aiState, !state.output.isEmpty else { return }
        let output = state.output
        closeAI()
        pasteContent(.text(output))
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
