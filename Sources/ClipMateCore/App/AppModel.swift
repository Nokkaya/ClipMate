import AppKit
import Combine
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
    private(set) var embeddingBackfill: EmbeddingBackfill?
    private let onboarding: OnboardingController

    /// 自动标签规则版本：升级规则（如新增号码识别）后 +1，启动时回填存量条目。
    private static let tagRulesVersionKey = "tagRulesVersion"
    private static let currentTagRulesVersion = 1

    private var hotkeyObserver: NSObjectProtocol?
    private var retentionTimer: Timer?
    private var semanticObserver: AnyCancellable?
    private let baseURL: URL

    init() throws {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipMate", isDirectory: true)
        baseURL = base
        blobStore = BlobStore(directory: base.appendingPathComponent("blobs"))
        settings = AppSettings()
        let database = try Database(url: base.appendingPathComponent("clipmate.sqlite"))
        // 语义搜索开关：开启且系统具备句向量能力时挂载向量生成器
        let embeddingEnabled = settings.semanticSearchEnabled && EmbeddingService.isAvailable
        store = try ClipStore(
            database: database,
            blobStore: blobStore,
            embeddingProvider: embeddingEnabled ? { EmbeddingService.embed(text: $0) } : nil
        )
        ai = AIService(settings: settings)
        monitor = ClipboardMonitor(settings: settings, store: store)
        frontApps = FrontAppTracker()
        hotkey = HotkeyManager()
        panel = PanelController(store: store, settings: settings, monitor: monitor, frontApps: frontApps, ai: ai)
        settingsWindow = SettingsWindowController(settings: settings, store: store, ai: ai, frontApps: frontApps)
        menuBar = MenuBarController(settings: settings, store: store)
        onboarding = OnboardingController(settings: settings)

        if embeddingEnabled {
            configureEmbeddingBackfill()
        }
        // 语义搜索开关即时生效：运行中切换会重建/拆除向量生成器与后台补算
        semanticObserver = settings.$semanticSearchEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reconfigureSemanticSearch() }
    }

    /// 挂载后台向量补算：独立数据库连接（WAL 多连接），避免补算写入与主线程查询争抢。
    private func configureEmbeddingBackfill() {
        guard embeddingBackfill == nil else { return }
        do {
            let database = try Database(url: baseURL.appendingPathComponent("clipmate.sqlite"))
            let backfillStore = try ClipStore(database: database, blobStore: blobStore)
            embeddingBackfill = EmbeddingBackfill(store: backfillStore) { [weak self] in
                self?.store.invalidateEmbeddingCache()
            }
        } catch {
            embeddingBackfill = nil
        }
    }

    /// 语义检索开关：开启则挂载生成器并补算存量，关闭则卸载（已算好的向量保留在库中）。
    private func reconfigureSemanticSearch() {
        let enabled = settings.semanticSearchEnabled && EmbeddingService.isAvailable
        guard enabled != (embeddingBackfill != nil) else { return }
        if enabled {
            store.setEmbeddingProvider { EmbeddingService.embed(text: $0) }
            configureEmbeddingBackfill()
            embeddingBackfill?.backfillAll()
        } else {
            embeddingBackfill = nil
            store.setEmbeddingProvider(nil)
        }
    }

    func start() {
        frontApps.start()

        monitor.onCaptured = { [weak self] item in
            guard let self else { return }
            self.panel.viewModel.handleCaptured(item)
            if self.settings.soundOnCapture {
                NSSound(named: "Tink")?.play()
            }
            // 新文本条目后台补算语义向量
            if item.kind == .text || item.kind == .url, !item.plainText.isEmpty {
                self.embeddingBackfill?.embedIfNeeded(id: item.id, text: item.plainText)
            }
        }
        monitor.onItemUpdated = { [weak self] item in
            self?.panel.viewModel.handleItemUpdated(item)
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

        // 保留策略：启动与每小时在后台 utility 队列执行，绝不阻塞主线程
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            try? self.store.enforceRetention(
                maxItems: self.settings.retentionMaxItems,
                maxAgeDays: self.settings.retentionMaxAgeDays
            )
        }
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return }
                try? self.store.enforceRetention(
                    maxItems: self.settings.retentionMaxItems,
                    maxAgeDays: self.settings.retentionMaxAgeDays
                )
            }
        }
        // 存量数据向量补算（后台，低优先级）
        embeddingBackfill?.backfillAll()
        // 存量号码归一化键回填（迁移 v4 后一次性，后台执行）
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.store.backfillNumberKeys()
        }
        // 标签规则升级后回填存量条目的自动标签（如新增的号码识别）
        if UserDefaults.standard.integer(forKey: Self.tagRulesVersionKey) < Self.currentTagRulesVersion {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let updated = self?.store.backfillAutoTags() ?? 0
                DispatchQueue.main.async {
                    UserDefaults.standard.set(Self.currentTagRulesVersion, forKey: Self.tagRulesVersionKey)
                    if updated > 0 { self?.panel.viewModel.reload() }
                }
            }
        }
        // 首次启动引导（含辅助功能授权引导）
        onboarding.showIfNeeded()
        // 自动检查更新（静默异步，距离上次检查 > 24h 时触发）
        UpdateManager.shared.checkOnLaunch(settings: settings)
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

    deinit {
        retentionTimer?.invalidate()
        if let hotkeyObserver {
            NotificationCenter.default.removeObserver(hotkeyObserver)
        }
    }
}
