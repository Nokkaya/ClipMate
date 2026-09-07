import AppKit
import Combine

/// 菜单栏常驻入口：最近条目快捷复制 + 暂停/清空/设置。
final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let settings: AppSettings
    private let store: ClipStore
    private var cancellables: Set<AnyCancellable> = []

    var onTogglePanel: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onHistoryChanged: (() -> Void)?
    var onSuppressCapture: (() -> Void)?
    var onExportHistory: (() -> Void)?
    var onImportHistory: (() -> Void)?

    init(settings: AppSettings, store: ClipStore) {
        self.settings = settings
        self.store = store
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "ClipMate 剪贴板历史"
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
        updateIcon()

        settings.$pauseCapture
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
    }

    public func updateIcon() {
        statusItem?.button?.image = Self.makeMenuBarIcon(isPaused: settings.pauseCapture)
    }

    /// 定制专属高精度矢量菜单栏图标（层叠剪贴板 + 灵动星芒 / 暂停徽标）
    public static func makeMenuBarIcon(isPaused: Bool = false) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()

            let color = NSColor.black

            // 1. 后层剪贴板/卡片轮廓（象征多级历史与片段）
            let backRect = NSRect(x: 4.6, y: 3.4, width: 10.2, height: 11.8)
            let backPath = NSBezierPath(roundedRect: backRect, xRadius: 2.2, yRadius: 2.2)
            color.withAlphaComponent(0.42).setStroke()
            backPath.lineWidth = 1.1
            backPath.stroke()

            // 2. 前层主剪贴板板身
            let frontRect = NSRect(x: 2.0, y: 1.5, width: 10.2, height: 11.8)
            let frontPath = NSBezierPath(roundedRect: frontRect, xRadius: 2.2, yRadius: 2.2)
            color.setStroke()
            frontPath.lineWidth = 1.25
            frontPath.stroke()

            // 3. 顶部金属夹具 (Clip)
            let clipRect = NSRect(x: 4.6, y: 12.0, width: 5.0, height: 2.6)
            let clipPath = NSBezierPath(roundedRect: clipRect, xRadius: 1.2, yRadius: 1.2)
            color.setFill()
            clipPath.fill()

            // 4. 前板线条（首行长，次行短）
            let line1 = NSBezierPath(roundedRect: NSRect(x: 4.0, y: 7.8, width: 6.2, height: 1.2), xRadius: 0.6, yRadius: 0.6)
            line1.fill()

            let line2 = NSBezierPath(roundedRect: NSRect(x: 4.0, y: 4.8, width: 4.2, height: 1.2), xRadius: 0.6, yRadius: 0.6)
            line2.fill()

            // 5. 右上角特征点：星芒（正常状态）或暂停徽标（暂停状态）
            if isPaused {
                let pauseRect = NSRect(x: 12.8, y: 11.8, width: 4.5, height: 1.5)
                let pausePath = NSBezierPath(roundedRect: pauseRect, xRadius: 0.75, yRadius: 0.75)
                color.setFill()
                pausePath.fill()
            } else {
                let cx: CGFloat = 14.6
                let cy: CGFloat = 13.0
                let r: CGFloat = 2.4
                let sparkle = NSBezierPath()
                sparkle.move(to: CGPoint(x: cx, y: cy + r))
                sparkle.curve(to: CGPoint(x: cx + r, y: cy), controlPoint1: CGPoint(x: cx, y: cy + r * 0.25), controlPoint2: CGPoint(x: cx + r * 0.25, y: cy))
                sparkle.curve(to: CGPoint(x: cx, y: cy - r), controlPoint1: CGPoint(x: cx + r * 0.25, y: cy), controlPoint2: CGPoint(x: cx, y: cy - r * 0.25))
                sparkle.curve(to: CGPoint(x: cx - r, y: cy), controlPoint1: CGPoint(x: cx, y: cy - r * 0.25), controlPoint2: CGPoint(x: cx - r * 0.25, y: cy))
                sparkle.curve(to: CGPoint(x: cx, y: cy + r), controlPoint1: CGPoint(x: cx - r * 0.25, y: cy), controlPoint2: CGPoint(x: cx, y: cy + r * 0.25))
                sparkle.close()
                color.setFill()
                sparkle.fill()
            }

            ctx.restoreGState()
            return true
        }
        img.isTemplate = true
        return img
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: "ClipMate", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let recents = store.search(query: "", filter: .all, limit: 5)
        if recents.isEmpty {
            let empty = NSMenuItem(title: "  （暂无历史记录）", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for recent in recents {
                let label = recent.displayText.replacingOccurrences(of: "\n", with: " ")
                let item = NSMenuItem(
                    title: "  " + String(label.prefix(46)),
                    action: #selector(copyRecentItem(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.isEnabled = true
                item.representedObject = NSNumber(value: recent.id)
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())

        let panelItem = NSMenuItem(title: "打开主面板", action: #selector(togglePanelAction), keyEquivalent: "")
        panelItem.target = self
        panelItem.isEnabled = true
        menu.addItem(panelItem)

        let pauseItem = NSMenuItem(
            title: settings.pauseCapture ? "恢复采集" : "暂停采集",
            action: #selector(togglePause),
            keyEquivalent: ""
        )
        pauseItem.target = self
        pauseItem.isEnabled = true
        menu.addItem(pauseItem)

        let clearItem = NSMenuItem(title: "清空历史（保留固定）", action: #selector(clearAll), keyEquivalent: "")
        clearItem.target = self
        clearItem.isEnabled = true
        menu.addItem(clearItem)

        let exportItem = NSMenuItem(title: "导出历史…", action: #selector(exportHistoryAction), keyEquivalent: "")
        exportItem.target = self
        exportItem.isEnabled = true
        menu.addItem(exportItem)

        let importItem = NSMenuItem(title: "导入历史…", action: #selector(importHistoryAction), keyEquivalent: "")
        importItem.target = self
        importItem.isEnabled = true
        menu.addItem(importItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.isEnabled = true
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem(title: "退出 ClipMate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    // MARK: - Actions

    @objc private func copyRecentItem(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber,
              let item = store.item(id: number.int64Value),
              let content = store.pasteboardContent(for: item) else { return }
        PasteBack.write(content)
        onSuppressCapture?()
        onHistoryChanged?()
    }

    @objc private func togglePanelAction() { onTogglePanel?() }
    @objc private func togglePause() { settings.pauseCapture.toggle() }

    @objc private func clearAll() {
        try? store.deleteAll(keepPinned: true)
        onHistoryChanged?()
    }

    @objc private func exportHistoryAction() { onExportHistory?() }
    @objc private func importHistoryAction() { onImportHistory?() }

    @objc private func openSettingsAction() { onOpenSettings?() }
}
