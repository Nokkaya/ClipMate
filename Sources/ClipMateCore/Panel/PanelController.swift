import AppKit
import SwiftUI

/// borderless NSPanel 默认不能成为 key window，需要子类放开。
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 非激活式悬浮面板：唤起时激活本 App 以接收键盘（accessory 应用无 Dock 图标），
/// 关闭时 hide() 把焦点还给上一个应用；粘贴目标在唤起前就已记录。
final class PanelController {
    let panel: KeyablePanel
    let viewModel: PanelViewModel
    let frontApps: FrontAppTracker
    var onOpenSettings: (() -> Void)?

    private var keyMonitor: Any?
    private var resignKeyObserver: NSObjectProtocol?

    init(store: ClipStore, settings: AppSettings, monitor: ClipboardMonitor,
         frontApps: FrontAppTracker, ai: AIService) {
        self.frontApps = frontApps
        viewModel = PanelViewModel(store: store, settings: settings, monitor: monitor, frontApps: frontApps, ai: ai)
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 480),
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        viewModel.dismiss = { [weak self] in self?.hidePanel() }
        viewModel.openSettings = { [weak self] in self?.onOpenSettings?() }

        let hosting = NSHostingView(rootView: PanelView(viewModel: viewModel))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.hidePanel()
        }
    }

    func togglePanel() {
        panel.isVisible ? hidePanel() : showPanel()
    }

    func showPanel() {
        // 先记录粘贴目标（唤起会激活本 App，frontmost 将变成自己）。
        if let last = frontApps.lastNonSelfApp, !last.isTerminated {
            viewModel.pasteTarget = last
        } else if let current = NSWorkspace.shared.frontmostApplication,
                  current.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            viewModel.pasteTarget = current
        }
        viewModel.reload()
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installKeyMonitor()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: .clipmateFocusSearch, object: nil)
        }
    }

    func hidePanel() {
        guard panel.isVisible else { return }
        removeKeyMonitor()
        viewModel.clearTransientState()
        panel.orderOut(nil)
        if NSApp.isActive {
            NSApp.hide(nil) // 焦点还给上一个应用
        }
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        let x = visible.midX - size.width / 2
        let y = visible.midY - size.height * 0.58
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - 键盘（键盘优先交互的核心）

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible, self.panel.isKeyWindow else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    /// 返回 true 表示事件已消费（monitor 闭包固定在主线程回调）。
    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmdOnly = flags.contains(.command)
            && !flags.contains(.option) && !flags.contains(.control)

        // 编辑浮层：除 Esc 外放行给 TextEditor
        if viewModel.showEditOverlay {
            if event.keyCode == 53 { viewModel.showEditOverlay = false; return true }
            return false
        }
        // 确认清空浮层
        if viewModel.showConfirmClear {
            if event.keyCode == 53 { viewModel.showConfirmClear = false; return true }
            return false
        }
        // AI 浮层：Esc 关闭，其余放行（自定义指令输入框）
        if viewModel.aiState != nil {
            if event.keyCode == 53 { viewModel.closeAI(); return true }
            return false
        }

        switch event.keyCode {
        case 125, 126: // 上下方向键
            viewModel.moveSelection(event.keyCode == 125 ? 1 : -1)
            return true
        case 36: // Return
            if cmdOnly { viewModel.copySelected() }
            else if flags.contains(.option) { viewModel.beginEdit() }
            else { viewModel.pasteSelected() }
            return true
        case 51: // Delete
            if !flags.contains(.command) && !flags.contains(.option) && !flags.contains(.control)
                && viewModel.query.isEmpty {
                viewModel.delete()
                return true
            }
            return false
        case 53: // Esc：先清搜索词，再隐藏
            if !viewModel.query.isEmpty {
                viewModel.query = ""
                viewModel.reload()
            } else {
                hidePanel()
            }
            return true
        case 48: // Tab：循环切换分类
            viewModel.cycleFilter()
            return true
        case 35 where cmdOnly: // ⌘P 固定
            viewModel.togglePin()
            return true
        case 40 where cmdOnly: // ⌘K AI
            viewModel.openAI()
            return true
        default:
            if cmdOnly, let chars = event.charactersIgnoringModifiers,
               let number = Int(chars), (1...9).contains(number) {
                viewModel.pasteIndex(number - 1)
                return true
            }
            return false
        }
    }
}
