import AppKit
import Carbon.HIToolbox

/// 剪贴板监听：0.5s 轮询 changeCount（业界标准做法，可靠且省电），
/// 命中变化后在后台队列读取，回到主线程入库并回调 UI。
public final class ClipboardMonitor {
    private let settings: AppSettings
    private let store: ClipStore
    private let captureQueue = DispatchQueue(label: "clipmate.capture", qos: .utility)
    private let ocrQueue = DispatchQueue(label: "clipmate.ocr", qos: .utility)
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var suppressUntil = Date.distantPast
    private var screenLocked = false
    private var lockObservers: [NSObjectProtocol] = []

    /// 采集成功回调（主线程）。
    public var onCaptured: ((ClipItem) -> Void)?
    /// 条目内容异步更新回调（如 OCR 识别完成，主线程）。
    public var onItemUpdated: ((ClipItem) -> Void)?

    public init(settings: AppSettings, store: ClipStore) {
        self.settings = settings
        self.store = store
    }

    public func start() {
        guard timer == nil else { return }
        observeScreenLock()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 自己写回剪贴板（粘贴回写/复制动作）后短时间抑制采集，避免把写入的内容当作用户复制。
    public func suppress(seconds: TimeInterval) {
        suppressUntil = Date().addingTimeInterval(seconds)
    }

    private func tick() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        guard !screenLocked, !settings.pauseCapture, Date() >= suppressUntil else { return }
        // 密码框等安全输入场景跳过采集。
        guard !IsSecureEventInputEnabled() else { return }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        if frontApp.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
        if let bundle = frontApp.bundleIdentifier, settings.excludedApps.contains(bundle) { return }

        let bundleID = frontApp.bundleIdentifier ?? ""
        let appName = frontApp.localizedName ?? ""
        let changeCount = pb.changeCount
        captureQueue.async { [weak self] in
            guard let self else { return }
            guard let content = ClipboardReader.read(from: pb, maxBytes: self.settings.maxCaptureBytes,
                                                     ocrEnabled: self.settings.imageOCREnabled) else { return }
            // 读取期间剪贴板又变了：放弃本次，交给下一轮。
            guard NSPasteboard.general.changeCount == changeCount else { return }

            // 优化：大文件落盘、哈希计算、SQLite 插入与 FTS5 分词在后台完成，避免主线程磁盘 I/O 阻塞
            let smartTitle: String? = self.settings.smartTitleEnabled
                ? SmartTitleGenerator.generate(for: content.plainText, kind: content.kind)
                : nil

            do {
                let result = try self.store.capture(
                    kind: content.kind,
                    plainText: content.plainText,
                    sourceBundle: bundleID,
                    sourceName: appName,
                    tags: content.tags,
                    title: smartTitle,
                    inlineData: content.inlineData,
                    imageOriginal: content.imageOriginal,
                    meta: content.meta
                )
                DispatchQueue.main.async {
                    self.onCaptured?(result.item)
                }

                // 优化：图片入库后后台异步 OCR，绝不阻塞采集与主线程，识别完成后异步更新 DB 与 UI
                if content.kind == .image && self.settings.imageOCREnabled && result.isNew,
                   let originalData = content.imageOriginal ?? content.inlineData {
                    let itemId = result.item.id
                    self.ocrQueue.async { [weak self] in
                        guard let self else { return }
                        guard let text = ClipboardReader.recognizeText(in: originalData) else { return }
                        let ocrText = String(text.prefix(4000))
                        let ocrTitle: String? = self.settings.smartTitleEnabled
                            ? (SmartTitleGenerator.generate(for: ocrText, kind: .text)
                               ?? ocrText.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }).map { String($0.prefix(40)) })
                            : nil
                        do {
                            if let updatedItem = try self.store.updateOCR(itemId, text: ocrText, title: ocrTitle) {
                                DispatchQueue.main.async {
                                    self.onItemUpdated?(updatedItem)
                                }
                            }
                        } catch {
                            NSLog("ClipMate OCR update failed: \(error)")
                        }
                    }
                }


                // 链接元数据抓取（标题 + Favicon）：后台异步低优先级任务，失败静默降级
                if content.kind == .url && self.settings.fetchLinkMetadata && (result.isNew || result.item.title == nil),
                   let url = URL(string: content.plainText) {
                    let itemId = result.item.id
                    Task.detached(priority: .utility) { [weak self] in
                        guard let self else { return }
                        let (title, favicon) = await URLMetadataFetcher.fetchMetadata(for: url)
                        guard title != nil || favicon != nil else { return }
                        do {
                            if let updated = try self.store.updateURLMetadata(itemId, title: title, faviconData: favicon) {
                                DispatchQueue.main.async { [weak self] in
                                    self?.onItemUpdated?(updated)
                                }
                            }
                        } catch {
                            NSLog("ClipMate link metadata update failed: \(error)")
                        }
                    }
                }
            } catch {
                NSLog("ClipMate capture failed: \(error)")
            }
        }
    }

    private func observeScreenLock() {
        let center = DistributedNotificationCenter.default()
        let locked = center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = true
        }
        let unlocked = center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = false
        }
        lockObservers.append(contentsOf: [locked, unlocked])
    }

    deinit {
        stop()
        lockObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
    }
}
