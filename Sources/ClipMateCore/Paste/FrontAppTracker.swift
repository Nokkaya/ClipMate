import AppKit

/// 跟踪最近一个非本应用的前台应用，作为粘贴回写的目标。
public final class FrontAppTracker {
    private var observer: NSObjectProtocol?
    public private(set) var lastNonSelfApp: NSRunningApplication?

    public init() {}

    public func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self?.lastNonSelfApp = app
        }
        if let current = NSWorkspace.shared.frontmostApplication,
           current.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastNonSelfApp = current
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
