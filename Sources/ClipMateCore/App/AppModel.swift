import AppKit
import UniformTypeIdentifiers

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
    let embeddingBackfill: EmbeddingBackfill?
    private(set) var aiWorkspace: AIWorkspaceController!

    private var hotkeyObserver: NSObjectProtocol?
    private var retentionTimer: Timer?
    private var captureCount = 0

    init() throws {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipMate", isDirectory: true)
        blobStore = BlobStore(directory: base.appendingPathComponent("blobs"))
        settings = AppSettings()
        let database = try Database(url: base.appendingPathComponent("clipmate.sqlite"))
        // 语义搜索开关：开启且系统具备句向量能力时挂载向量生成器
        let embeddingProvider: ((String) -> Data?)? = settings.semanticSearchEnabled && EmbeddingService.isAvailable
            ? { EmbeddingService.embed(text: $0) }
            : nil
        store = try ClipStore(database: database, blobStore: blobStore, embeddingProvider: embeddingProvider)
        embeddingBackfill = embeddingProvider == nil ? nil : EmbeddingBackfill(store: store)
        ai = AIService(settings: settings)
        monitor = ClipboardMonitor(settings: settings, store: store)
        frontApps = FrontAppTracker()
        hotkey = HotkeyManager()
        panel = PanelController(store: store, settings: settings, monitor: monitor, frontApps: frontApps, ai: ai)
        settingsWindow = SettingsWindowController(settings: settings, store: store, ai: ai, frontApps: frontApps)
        menuBar = MenuBarController(settings: settings, store: store)
        aiWorkspace = AIWorkspaceController(ai: ai, store: store, monitor: monitor, settings: settings)
        aiWorkspace.model.pasteTargetProvider = { [weak self] in self?.panel.viewModel.pasteTarget }
        aiWorkspace.model.hidePanel = { [weak self] in self?.panel.hidePanel() }
        aiWorkspace.mainFrameProvider = { [weak self] in self?.panel.panel.frame }
        aiWorkspace.onClosed = { [weak self] in self?.panel.reassertKey() }
        panel.aiWorkspace = aiWorkspace
        panel.viewModel.aiWorkspace = aiWorkspace
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
            // 新文本条目后台补算语义向量
            if item.kind == .text || item.kind == .url, !item.plainText.isEmpty {
                self.embeddingBackfill?.embedIfNeeded(id: item.id, text: item.plainText)
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
        menuBar.onExportHistory = { [weak self] in self?.exportHistory() }
        menuBar.onImportHistory = { [weak self] in self?.importHistory() }
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
        // 存量数据向量补算（后台，低优先级）
        embeddingBackfill?.backfillAll()
    }

    private func applyHotkey() {
        let preset = settings.currentPreset
        hotkey.onHotkey = { [weak self] in self?.panel.togglePanel() }
        hotkey.register(keyCode: preset.keyCode, modifiers: preset.modifiers)
    }

    // MARK: - 导入导出

    func exportHistory() {
        let panel = NSSavePanel()
        panel.title = "导出剪贴板历史"
        panel.nameFieldStringValue = "clipmate-export.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try store.exportJSON()
            try data.write(to: url, options: .atomic)
            alert("导出完成", "已导出 \(store.itemCount()) 条到 \(url.lastPathComponent)")
        } catch {
            alert("导出失败", error.localizedDescription)
        }
    }

    func importHistory() {
        let openPanel = NSOpenPanel()
        openPanel.title = "导入剪贴板历史"
        openPanel.allowedContentTypes = [.json]
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        guard openPanel.runModal() == .OK, let url = openPanel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let count = try store.importJSON(data)
            panel.viewModel.reload()
            alert("导入完成", "新入库 \(count) 条（重复内容已自动跳过）")
        } catch {
            alert("导入失败", error.localizedDescription)
        }
    }

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
