import AppKit

/// 组装根：初始化各服务并接线。
final class AppModel {
    let settings: AppSettings
    let store: ClipStore
    let blobStore: BlobStore
    let monitor: ClipboardMonitor
    let hotkey: HotkeyManager
    let frontApps: FrontAppTracker
    let ai: AIService
    let panel: PanelController
    let menuBar: MenuBarController
    let settingsWindow: SettingsWindowController

    private var hotkeyObserver: NSObjectProtocol?
    private var retentionTimer: Timer?
    private var captureCount = 0

    init() throws {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipMate", isDirectory: true)
        blobStore = BlobStore(directory: base.appendingPathComponent("blobs"))
        settings = AppSettings()
        let database = try Database(url: base.appendingPathComponent("clipmate.sqlite"))
        store = try ClipStore(database: database, blobStore: blobStore)
        ai = AIService(settings: settings)
        monitor = ClipboardMonitor(settings: settings, store: store)
        frontApps = FrontAppTracker()
        hotkey = HotkeyManager()
        panel = PanelController(store: store, settings: settings, monitor: monitor, frontApps: frontApps, ai: ai)
        settingsWindow = SettingsWindowController(settings: settings, store: store, ai: ai, frontApps: frontApps)
        menuBar = MenuBarController(settings: settings, store: store)
    }

    func start() {
        frontApps.start()

        monitor.onCaptured = { [weak self] item in
            guard let self else { return }
            self.panel.viewModel.handleCaptured(item)
            self.captureCount += 1
            if self.captureCount % 10 == 0 {
                try? self.store.enforceRetention(
                    maxItems: self.settings.retentionMaxItems,
                    maxAgeDays: self.settings.retentionMaxAgeDays
                )
            }
            if self.settings.soundOnCapture {
                NSSound(named: "Tink")?.play()
            }
        }
        monitor.start()

        applyHotkey()
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: AppSettings.hotkeyChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyHotkey()
        }

        panel.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        menuBar.onTogglePanel = { [weak self] in self?.panel.togglePanel() }
        menuBar.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        menuBar.onHistoryChanged = { [weak self] in self?.panel.viewModel.reload() }
        menuBar.onSuppressCapture = { [weak self] in self?.monitor.suppress(seconds: 1.5) }
        menuBar.install()

        try? store.enforceRetention(
            maxItems: settings.retentionMaxItems,
            maxAgeDays: settings.retentionMaxAgeDays
        )
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            guard let self else { return }
            try? self.store.enforceRetention(
                maxItems: self.settings.retentionMaxItems,
                maxAgeDays: self.settings.retentionMaxAgeDays
            )
        }
    }

    private func applyHotkey() {
        let preset = settings.currentPreset
        hotkey.onHotkey = { [weak self] in self?.panel.togglePanel() }
        hotkey.register(keyCode: preset.keyCode, modifiers: preset.modifiers)
    }
}
