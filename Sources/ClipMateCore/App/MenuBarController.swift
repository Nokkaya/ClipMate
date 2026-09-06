import AppKit

/// 菜单栏常驻入口：最近条目快捷复制 + 暂停/清空/设置。
final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let settings: AppSettings
    private let store: ClipStore

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
        item.button?.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "ClipMate")
        item.button?.toolTip = "ClipMate 剪贴板历史"
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
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
