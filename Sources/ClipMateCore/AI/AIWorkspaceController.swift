import AppKit
import SwiftUI

/// AI 工作台状态（独立于主面板的窗口）。
final class AIWorkspaceModel: ObservableObject {
    @Published var item: ClipItem?
    @Published var output = ""
    @Published var isRunning = false
    @Published var finished = false
    @Published var errorText: String?
    @Published var customPrompt = ""

    let ai: AIService
    let store: ClipStore
    let monitor: ClipboardMonitor
    let settings: AppSettings

    var pasteTargetProvider: (() -> NSRunningApplication?)?
    var hidePanel: (() -> Void)?
    private var task: Task<Void, Never>?

    init(ai: AIService, store: ClipStore, monitor: ClipboardMonitor, settings: AppSettings) {
        self.ai = ai
        self.store = store
        self.monitor = monitor
        self.settings = settings
    }

    var scriptList: [ScriptAction] { settings.customScripts }

    var statusText: String {
        ai.isConfigured ? "OpenAI 兼容端点" : "未配置（设置 → AI）"
    }

    /// 打开/切换条目：重置结果区，保留自定义指令。
    func load(item: ClipItem) {
        cancel()
        self.item = item
        output = ""
        finished = false
        errorText = nil
        isRunning = false
    }

    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func beginRun() -> ClipItem? {
        guard let item else { return nil }
        cancel()
        output = ""
        finished = false
        errorText = nil
        isRunning = true
        return item
    }

    private func endRun(success: Bool) {
        if isRunning {
            isRunning = false
            finished = success
        }
    }

    func runAI(_ action: AIAction) {
        guard let item = beginRun() else { return }
        guard ai.isConfigured else {
            isRunning = false
            errorText = AIError.notConfigured.localizedDescription
            return
        }
        let prompt = action.prompt(for: item.plainText, custom: customPrompt)
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for try await delta in self.ai.stream(prompt: prompt) {
                    self.output += delta
                }
                self.endRun(success: true)
            } catch {
                self.isRunning = false
                self.errorText = "请求失败：\(error.localizedDescription)"
            }
        }
    }

    func runScript(_ script: ScriptAction) {
        guard let item = beginRun() else { return }
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let output = try await ScriptRunner.run(script, input: item.plainText)
                if self.isRunning {
                    self.output = output
                    self.isRunning = false
                    self.finished = true
                }
            } catch {
                self.isRunning = false
                self.errorText = "脚本失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - 结果处置

    var hasResult: Bool { finished && !output.isEmpty }

    func copyResult() {
        guard hasResult else { return }
        PasteBack.write(.text(output))
        monitor.suppress(seconds: 1.5)
    }

    /// 结果作为新条目入库（原内容保留在历史中）。
    func replaceAsNewItem() {
        guard hasResult else { return }
        _ = try? store.capture(
            kind: .text,
            plainText: output,
            sourceBundle: Bundle.main.bundleIdentifier ?? "",
            sourceName: "ClipMate",
            tags: ["AI"]
        )
    }

    /// 直接粘贴到唤起面板前的目标应用，随后关闭工作台与主面板。
    func pasteResult() {
        guard hasResult else { return }
        let target = pasteTargetProvider?()
        let content = PasteboardContent.text(output)
        hidePanel?()
        PasteBack.paste(content: content, toPID: target?.processIdentifier) { [weak self] seconds in
            self?.monitor.suppress(seconds: seconds)
        }
        if target == nil || !PasteBack.isAccessibilityGranted() {
            NSSound(named: "Basso")?.play()
        }
    }
}

/// 独立悬浮窗口：不覆盖主面板、可拖动、记忆位置。
final class AIWorkspaceController {
    let model: AIWorkspaceModel
    let panel: KeyablePanel

    /// 供定位：主面板当前 frame。
    var mainFrameProvider: (() -> NSRect?)?
    /// 窗口关闭后的回调（主面板重新聚焦）。
    var onClosed: (() -> Void)?

    private var observers: [NSObjectProtocol] = []
    private static let frameKey = "aiWorkspaceFrame"

    init(ai: AIService, store: ClipStore, monitor: ClipboardMonitor, settings: AppSettings) {
        model = AIWorkspaceModel(ai: ai, store: store, monitor: monitor, settings: settings)
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 640),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: AIWorkspaceView(model: model))

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { [weak self] _ in
            self?.model.cancel()
            self?.onClosed?()
        })
        observers.append(center.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            self?.saveFrame()
        })
        observers.append(center.addObserver(
            forName: NSWindow.didEndLiveResizeNotification, object: panel, queue: .main
        ) { [weak self] _ in
            self?.saveFrame()
        })

        // 直接粘贴时：先关工作台再隐藏主面板
        model.hidePanel = { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.model.hidePanel?()
        }
    }

    var isVisible: Bool { panel.isVisible }

    /// ⌘K 语义：同一目标再按一次则关闭，否则打开/刷新内容。
    func openOrFocus(item: ClipItem) {
        if panel.isVisible, model.item?.id == item.id {
            close()
            return
        }
        open(item: item)
    }

    func open(item: ClipItem) {
        model.load(item: item)
        position()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        panel.orderOut(nil) // 触发 willCloseNotification → cancel + onClosed
    }

    private func position() {
        // 记忆位置优先（且必须在当前屏幕范围内）
        if let saved = savedFrame() {
            panel.setFrame(saved, display: true)
            return
        }
        let size = panel.frame.size
        guard let mainFrame = mainFrameProvider?(),
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(mainFrame) }) else {
            if let main = NSScreen.main {
                let visible = main.visibleFrame
                panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                             y: visible.midY - size.height / 2))
            }
            return
        }
        let visible = screen.visibleFrame
        // 默认贴在主面板右侧；放不下则放左侧
        var x = mainFrame.maxX + 12
        if x + size.width > visible.maxX {
            x = mainFrame.minX - size.width - 12
        }
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let y = min(max(mainFrame.midY - size.height / 2, visible.minY + 8),
                    visible.maxY - size.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func saveFrame() {
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: Self.frameKey)
    }

    private func savedFrame() -> NSRect? {
        guard let string = UserDefaults.standard.string(forKey: Self.frameKey) else { return nil }
        let rect = NSRectFromString(string)
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(rect) }
        return onScreen && rect.width > 100 ? rect : nil
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
