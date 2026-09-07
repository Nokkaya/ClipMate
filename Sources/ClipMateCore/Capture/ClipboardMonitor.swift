import AppKit
import Carbon.HIToolbox

/// 剪贴板监听：0.5s 轮询 changeCount（业界标准做法，可靠且省电），
/// 命中变化后在后台队列读取，回到主线程入库并回调 UI。
public final class ClipboardMonitor {
    private let settings: AppSettings
    private let store: ClipStore
    private let captureQueue = DispatchQueue(label: "clipmate.capture", qos: .utility)
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var suppressUntil = Date.distantPast
    private var screenLocked = false
    private var lockObservers: [NSObjectProtocol] = []

    /// 采集成功回调（主线程）。
    public var onCaptured: ((ClipItem) -> Void)?

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
            do {
                let result = try self.store.capture(
                    kind: content.kind,
                    plainText: content.plainText,
                    sourceBundle: bundleID,
                    sourceName: appName,
                    tags: content.tags,
                    inlineData: content.inlineData,
                    imageOriginal: content.imageOriginal,
                    meta: content.meta
                )
                DispatchQueue.main.async {
                    self.onCaptured?(result.item)
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
