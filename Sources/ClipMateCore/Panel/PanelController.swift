import AppKit
import SwiftUI

/// borderless NSPanel 默认不能成为 key window，需要子类放开。
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 自动监听布局并将内部任意 NSScrollView 改造为透明毛玻璃现代滚动条的 HostingView
final class AutoConfiguringHostingView<Content: View>: NSHostingView<Content> {
    override func layout() {
        super.layout()
        ModernScrollViewConfigurator.configureAllScrollViews(in: self)
    }
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
    private var moveObserver: NSObjectProtocol?

    init(store: ClipStore, settings: AppSettings, monitor: ClipboardMonitor,
         frontApps: FrontAppTracker, ai: AIService) {
        self.frontApps = frontApps
        viewModel = PanelViewModel(store: store, settings: settings, monitor: monitor, frontApps: frontApps, ai: ai)
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 580),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // 系统窗口阴影在透明窗口上每次内容变化都要整体重算（卡顿源之一），
        // 改由 SwiftUI 在窗口内绘制阴影（见 PanelView 的边距设计）。
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        viewModel.dismiss = { [weak self] in self?.hidePanel() }
        viewModel.openSettings = { [weak self] in self?.onOpenSettings?() }
        viewModel.onAISidebarToggled = { [weak self] isOpen in
            self?.updatePanelFrame(forSidebarOpen: isOpen, animated: true)
        }

        let hosting = AutoConfiguringHostingView(rootView: PanelView(viewModel: viewModel))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.hidePanel()
        }

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.panel.isVisible else { return }
            let origin = self.panel.frame.origin
            self.viewModel.settings.lastPanelPositionX = origin.x
            self.viewModel.settings.lastPanelPositionY = origin.y
        }
    }

    deinit {
        removeKeyMonitor()
        if let resignKeyObserver {
            NotificationCenter.default.removeObserver(resignKeyObserver)
        }
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
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
        let targetWidth: CGFloat = viewModel.isAISidebarOpen ? 940 : 500
        let targetHeight: CGFloat = 580
        var currentFrame = panel.frame
        currentFrame.size = NSSize(width: targetWidth, height: targetHeight)
        panel.setFrame(currentFrame, display: false)
        positionPanel()
        if let contentView = panel.contentView {
            ModernScrollViewConfigurator.configureAllScrollViews(in: contentView)
        }
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
        let mouseLoc = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first { NSMouseInRect(mouseLoc, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen = activeScreen else { return }

        let size = panel.frame.size
        let visible = screen.visibleFrame

        switch viewModel.settings.panelPositionMode {
        case .center:
            let x = visible.midX - size.width / 2
            let y = visible.midY - size.height * 0.58
            panel.setFrameOrigin(NSPoint(x: x, y: y))

        case .followCursor:
            let targetX = mouseLoc.x - size.width / 2
            var targetY = mouseLoc.y - size.height - 12

            if targetY < visible.minY {
                targetY = mouseLoc.y + 12
            }
            let minX = visible.minX + 8
            let maxX = max(minX, visible.maxX - size.width - 8)
            let minY = visible.minY + 8
            let maxY = max(minY, visible.maxY - size.height - 8)
            let clampedX = min(max(targetX, minX), maxX)
            let clampedY = min(max(targetY, minY), maxY)
            panel.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))

        case .remember:
            if let lastX = viewModel.settings.lastPanelPositionX,
               let lastY = viewModel.settings.lastPanelPositionY {
                let targetOrigin = NSPoint(x: lastX, y: lastY)
                let panelRect = NSRect(origin: targetOrigin, size: size)
                // 确保记忆的坐标在某块屏幕的可视区域内，防止外接屏拔掉后窗口移出屏幕
                if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panelRect) }) {
                    panel.setFrameOrigin(targetOrigin)
                    return
                }
            }
            let x = visible.midX - size.width / 2
            let y = visible.midY - size.height * 0.58
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }


    /// 当 AI 侧边栏展开/收起时平滑变更窗口尺寸
    func updatePanelFrame(forSidebarOpen isOpen: Bool, animated: Bool = true) {
        let targetWidth: CGFloat = isOpen ? 940 : 500
        let targetHeight: CGFloat = 580
        var frame = panel.frame
        let widthDelta = targetWidth - frame.width
        if abs(widthDelta) < 1 { return }

        guard panel.isVisible else {
            frame.size = NSSize(width: targetWidth, height: targetHeight)
            panel.setFrame(frame, display: true)
            return
        }

        var newX = frame.origin.x
        let newY = frame.origin.y
        if let screen = panel.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            if newX + targetWidth > visible.maxX - 8 {
                newX = max(visible.minX + 8, visible.maxX - targetWidth - 8)
            }
        }

        let newFrame = NSRect(x: newX, y: newY, width: targetWidth, height: targetHeight)
        if animated {
            if isOpen {
                // 展开时：由于窗口底色全透明（.clear），立即将透明画板拓宽到 940，
                // 彻底消除窗口服务器重分配 backing store 和连续缩放时的卡顿与左侧抖动；
                // 若靠近屏幕右侧需要平移，则平移动画
                if newX != frame.origin.x {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.25
                        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        context.allowsImplicitAnimation = true
                        self.panel.animator().setFrame(newFrame, display: true)
                    }
                } else {
                    panel.setFrame(newFrame, display: true)
                }
            } else {
                // 收起时：等 SwiftUI 卡片在 0.25s 内平滑收回至 440px 后，再将透明窗口尺寸还原为 500
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [weak self] in
                    guard let self = self, !self.viewModel.isAISidebarOpen else { return }
                    self.panel.setFrame(newFrame, display: true)
                }
            }
        } else {
            panel.setFrame(newFrame, display: true)
        }
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
            && !flags.contains(.option) && !flags.contains(.control) && !flags.contains(.shift)
        let cmdShiftOnly = flags.contains(.command) && flags.contains(.shift)
            && !flags.contains(.option) && !flags.contains(.control)

        let optOnly = flags.contains(.option)
            && !flags.contains(.command) && !flags.contains(.control) && !flags.contains(.shift)
        let optShiftOnly = flags.contains(.option) && flags.contains(.shift)
            && !flags.contains(.command) && !flags.contains(.control)

        // ⌥1 ~ ⌥9：极速粘贴选中条目的局部字段（如手机号、邮箱、JSON 键）
        if optOnly, let chars = event.charactersIgnoringModifiers,
           let number = Int(chars), (1...9).contains(number) {
            viewModel.pasteField(at: number - 1)
            return true
        }

        // ⌥⇧1 ~ ⌥⇧9：极速复制选中条目的局部字段
        if optShiftOnly, let chars = event.charactersIgnoringModifiers,
           let number = Int(chars), (1...9).contains(number) {
            viewModel.copyField(at: number - 1)
            return true
        }

        // ⌥[ / ⌥- 与 ⌥] / ⌥+：调节内容控件主变量（如份数、时间）
        if optOnly, let session = viewModel.activeInteractiveSession, session.missingConstraint == nil {
            if event.keyCode == 30 || event.keyCode == 24 { // ] 或 =/+
                viewModel.adjustPrimaryVariable(delta: 1)
                return true
            } else if event.keyCode == 33 || event.keyCode == 27 { // [ 或 -
                viewModel.adjustPrimaryVariable(delta: -1)
                return true
            }
        }

        // 草稿微调正文编辑态：除 Esc 外放行给 TextEditor (BUG-01 / BUG-02)
        if viewModel.isDraftEditingText {
            if event.keyCode == 53 { viewModel.isDraftEditingText = false; return true }
            return false
        }
        // 编辑浮层：除 Esc 外放行给 TextEditor
        if viewModel.showEditOverlay {
            if event.keyCode == 53 { viewModel.showEditOverlay = false; return true }
            return false
        }
        // 重命名浮层：除 Esc 外放行给输入框
        if viewModel.showRenameOverlay {
            if event.keyCode == 53 { viewModel.showRenameOverlay = false; return true }
            return false
        }
        // 片段编辑浮层：除 Esc 外放行给表单控件
        if viewModel.showSnippetOverlay {
            if event.keyCode == 53 { viewModel.showSnippetOverlay = false; return true }
            return false
        }
        // 确认清空浮层
        if viewModel.showConfirmClear {
            if event.keyCode == 53 { viewModel.showConfirmClear = false; return true }
            return false
        }
        // 预览浮层：Esc/⌘I 关闭，其余放行（文本可选中复制）
        if viewModel.previewItem != nil {
            if event.keyCode == 53 || (event.keyCode == 34 && cmdOnly) {
                viewModel.previewItem = nil
                return true
            }
            return false
        }

        switch event.keyCode {
        case 125, 126: // 上下方向键；Shift 组合为批量多选扩展
            if flags.contains(.shift) {
                viewModel.extendSelection(event.keyCode == 125 ? 1 : -1)
            } else {
                viewModel.moveSelection(event.keyCode == 125 ? 1 : -1)
            }
            return true
        case 123, 124: // 左右方向键
            // CM-05: 检查当前文本输入焦点，未处于字段焦点时交还系统文本光标移动
            let isTextViewFocused = (panel.firstResponder is NSTextView)
            if viewModel.selectedFieldIndex != nil || flags.contains(.option) || !isTextViewFocused {
                if event.keyCode == 124 {
                    viewModel.moveFieldSelection(1)
                } else {
                    viewModel.moveFieldSelection(-1)
                }
                return true
            }
            return false // 允许在搜索框等文本控件中进行正常的字符左右光标移动

        case 36: // Return
            // BUG-01: 若处于 AI 追问、草稿指令或输入框中，放行由原生控件 onSubmit/onCommit 消费
            if viewModel.isAIPromptFocused {
                return false
            }
            // CM-05: 优先处理带有修饰键（⌘、⇧、⌥等）的快捷键，保证已有组合键原有语义不受破坏
            if flags.contains(.command) && flags.contains(.shift) {
                viewModel.pasteQueue()          // ⌘⇧⏎ 顺序粘贴队列
            } else if flags.contains(.command) && flags.contains(.option) {
                viewModel.pasteAsPlainText()    // ⌘⌥⏎ 粘贴为纯文本
            } else if cmdOnly {
                if viewModel.multiSelectedIDs.count > 1 {
                    viewModel.copyMulti()       // ⌘⏎ 多选时合并复制
                } else {
                    viewModel.copySelected()    // ⌘⏎ 仅复制
                }
            } else if flags.contains(.option) {
                viewModel.beginEdit()           // ⌥⏎ 编辑
            } else if flags.contains(.shift) {
                if viewModel.multiSelectedIDs.count > 1 {
                    viewModel.enqueueMulti()    // ⇧⏎ 多选时批量入队
                } else {
                    _ = viewModel.toggleQueue() // ⇧⏎ 加入/移出队列
                }
            } else if let fieldIdx = viewModel.selectedFieldIndex {
                // 仅在明确进入字段高亮且无修饰键时，纯 Return 粘贴选中字段
                viewModel.pasteField(at: fieldIdx)
            } else {
                viewModel.pasteSelected()       // ⏎ 粘贴
            }
            return true
        case 51: // Delete (退格键)
            // 无论输入框是否有文字，单按退格键（⌫ 无 Command）一律放行给文本系统处理，绝对不误删历史条目
            if !flags.contains(.command) {
                return false
            }
            // 仅当用户明确按下 ⌘⌫ (Command + Delete) 且非正文编辑态时，才执行条目删除（符合 macOS 标准快捷键规范）
            if cmdOnly && !viewModel.isDraftEditingText {
                if viewModel.multiSelectedIDs.count > 1 {
                    viewModel.deleteMulti()     // 批量删除
                } else {
                    viewModel.delete()
                }
                return true
            }
            return false
        case 30, 24: // ] 或 +
            let isTextViewFocused = (panel.firstResponder is NSTextView)
            if !isTextViewFocused, let session = viewModel.activeInteractiveSession, session.missingConstraint == nil {
                viewModel.adjustPrimaryVariable(delta: 1)
                return true
            }
            return false
        case 33, 27: // [ 或 -
            let isTextViewFocused = (panel.firstResponder is NSTextView)
            if !isTextViewFocused, let session = viewModel.activeInteractiveSession, session.missingConstraint == nil {
                viewModel.adjustPrimaryVariable(delta: -1)
                return true
            }
            return false
        case 6 where cmdOnly: // ⌘Z 优先撤销工作草稿修改，其次撤销内容控件单步调节 (BUG-05)
            if let draft = viewModel.activeDraft, !draft.undoStack.isEmpty {
                viewModel.undoDraft()
                return true
            } else if let session = viewModel.activeInteractiveSession, !session.undoStack.isEmpty {
                viewModel.undoInteractiveSession(itemID: session.itemID)
                return true
            }
            return false
        case 53: // Esc：退字段焦点 → 收起草稿差异对比/错误横幅 → 复位控件修改 → 清多选 → 收起 AI 侧边栏 → 清搜索词 → 隐藏 (BUG-06)
            if viewModel.selectedFieldIndex != nil {
                viewModel.selectedFieldIndex = nil
            } else if viewModel.isDraftReviewingDiff {
                viewModel.isDraftReviewingDiff = false
            } else if viewModel.draftErrorMessage != nil {
                viewModel.draftErrorMessage = nil
            } else if let session = viewModel.activeInteractiveSession, session.isModified {
                viewModel.resetInteractiveSession(itemID: session.itemID)
            } else if viewModel.multiSelectedIDs.count > 0 {
                viewModel.clearMultiSelection()
            } else if viewModel.isAISidebarOpen {
                viewModel.toggleAISidebar()
            } else if !viewModel.query.isEmpty {
                viewModel.query = ""
                viewModel.reload()
            } else {
                hidePanel()
            }
            return true
        case 48: // Tab：循环切换分类
            viewModel.cycleFilter()
            return true
        case 0 where cmdOnly: // ⌘A 全选可见条目
            if viewModel.query.isEmpty {
                viewModel.selectAllVisible()
                return true
            }
            return false
        case 0 where cmdShiftOnly: // ⌘⇧A 切换 AI 侧边栏
            viewModel.toggleAISidebar()
            return true
        case 8 where cmdOnly: // ⌘C 复制 / 合并复制
            if let fieldIdx = viewModel.selectedFieldIndex {
                viewModel.copyField(at: fieldIdx)
                return true
            } else if viewModel.multiSelectedIDs.count > 1 {
                viewModel.copyMulti()
                return true
            } else if viewModel.query.isEmpty {
                viewModel.copySelected()
                return true
            }
            return false
        case 35 where cmdOnly: // ⌘P 固定 / 批量固定
            if viewModel.multiSelectedIDs.count > 1 {
                viewModel.togglePinMulti()
            } else {
                viewModel.togglePin()
            }
            return true
        case 34 where cmdOnly: // ⌘I 详情预览
            viewModel.togglePreview()
            return true
        case 15 where cmdOnly: // ⌘R 重命名
            viewModel.beginRename()
            return true
        case 40 where cmdOnly: // ⌘K 切换 AI 侧边栏
            viewModel.toggleAISidebar()
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
