import AppKit
import SwiftUI

/// 独立设置窗口（标准 macOS 样式）。
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: AppSettings
    private let store: ClipStore
    private let ai: AIService
    private let frontApps: FrontAppTracker

    init(settings: AppSettings, store: ClipStore, ai: AIService, frontApps: FrontAppTracker) {
        self.settings = settings
        self.store = store
        self.ai = ai
        self.frontApps = frontApps
    }

    func show() {
        if window == nil {
            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 670, height: 540),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            newWindow.title = "ClipMate 设置"
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            newWindow.contentView = NSHostingView(
                rootView: SettingsView(settings: settings, store: store, ai: ai, frontApps: frontApps)
            )
            window = newWindow
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
