import AppKit
import ApplicationServices
import CoreGraphics

/// 写回剪贴板的内容形态。
public enum PasteboardContent {
    case text(String)
    case richText(rtf: Data, plain: String)
    case image(data: Data)
    case files([URL])
    case pdf(data: Data, plain: String)
}

/// 粘贴回退原因
public enum PasteFallbackReason: Equatable {
    case permissionDenied
    case targetUnavailable
    case pasteFailed
    case newCopyDetected
}

/// 粘贴回写：写剪贴板 → 对前台应用合成 ⌘V → 恢复原剪贴板（不污染用户剪贴板）。
/// 合成按键依赖辅助功能权限；未授权时降级为"仅写入剪贴板"。
public enum PasteBack {
    public static let ownedMarker = NSPasteboard.PasteboardType("com.clipmate.owned")

    public static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// 弹出系统授权引导（系统设置 → 隐私与安全性 → 辅助功能）。
    @discardableResult
    public static func promptAccessibility() -> Bool {
        AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
        ] as CFDictionary)
    }

    // MARK: - 写入

    @discardableResult
    public static func write(_ content: PasteboardContent) -> Int {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch content {
        case .text(let string):
            pb.declareTypes([ownedMarker, .string], owner: nil)
            pb.setString(string, forType: .string)
        case .richText(let rtf, let plain):
            pb.declareTypes([ownedMarker, .string, .rtf], owner: nil)
            pb.setString(plain, forType: .string)
            pb.setData(rtf, forType: .rtf)
        case .image(let data):
            if let image = NSImage(data: data) {
                pb.writeObjects([image])
                pb.setData(Data("1".utf8), forType: ownedMarker)
            } else {
                pb.declareTypes([ownedMarker, .png], owner: nil)
                pb.setData(data, forType: .png)
            }
        case .files(let urls):
            pb.declareTypes([ownedMarker], owner: nil)
            pb.writeObjects(urls.map { $0 as NSURL })
        case .pdf(let data, let plain):
            pb.declareTypes([ownedMarker, .pdf, .string], owner: nil)
            pb.setData(data, forType: .pdf)
            if !plain.isEmpty { pb.setString(plain, forType: .string) }
        }
        return pb.changeCount
    }

    // MARK: - 剪贴板快照（粘贴后恢复，不覆盖用户剪贴板）

    public static func snapshotPasteboard() -> [NSPasteboard.PasteboardType: Data]? {
        guard let types = NSPasteboard.general.types, !types.isEmpty else { return nil }
        var data: [NSPasteboard.PasteboardType: Data] = [:]
        for type in types {
            if let d = NSPasteboard.general.data(forType: type) { data[type] = d }
        }
        return data.isEmpty ? nil : data
    }

    public static func restorePasteboard(_ snapshot: [NSPasteboard.PasteboardType: Data]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes(Array(snapshot.keys), owner: nil)
        for (type, data) in snapshot {
            pb.setData(data, forType: type)
        }
    }

    /// 校验是否允许恢复旧快照：
    /// 只有当剪贴板当前的 changeCount 仍等于本次写入后的 changeCount，
    /// 且仍带有 ClipMate 自身的 ownedMarker 标记时，才恢复旧快照。
    /// 若用户或第三方在粘贴期间新复制了内容，必须坚决放弃恢复，完好保护新内容。
    public static func shouldRestorePasteboard(writtenChangeCount: Int, pb: NSPasteboard = .general) -> Bool {
        guard pb.changeCount == writtenChangeCount else { return false }
        guard pb.types?.contains(ownedMarker) == true else { return false }
        return true
    }

    // MARK: - 合成 ⌘V

    @discardableResult
    public static func pasteToFrontmost(pid: pid_t, completion: ((Bool) -> Void)? = nil) -> Bool {
        guard isAccessibilityGranted() else {
            promptAccessibility()
            completion?(false)
            return false
        }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else {
            completion?(false)
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(pid)
        // 优化：避免 usleep(25_000) 阻塞主线程，采用非阻塞延迟派发 keyUp
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
            up.postToPid(pid)
            completion?(true)
        }
        return true
    }

    /// 完整粘贴流程（主线程调用）：写 → 粘贴 → 延迟恢复原剪贴板。
    /// 当目标不可用、缺少辅助功能权限或事件派发失败时，保留内容在剪贴板并回调 fallback。
    public static func paste(
        content: PasteboardContent,
        toPID pid: pid_t?,
        targetApp: NSRunningApplication? = nil,
        suppress: ((TimeInterval) -> Void)? = nil,
        onFallback: ((PasteFallbackReason) -> Void)? = nil
    ) {
        let snapshot = snapshotPasteboard()
        let writtenChangeCount = write(content)
        suppress?(1.8)

        if let targetApp, targetApp.isTerminated {
            onFallback?(.targetUnavailable)
            return
        }
        guard let pid, pid > 0 else {
            onFallback?(.targetUnavailable)
            return
        }

        guard isAccessibilityGranted() else {
            promptAccessibility()
            onFallback?(.permissionDenied)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let targetApp, targetApp.isTerminated {
                onFallback?(.targetUnavailable)
                return
            }
            pasteToFrontmost(pid: pid) { success in
                if !success {
                    onFallback?(.pasteFailed)
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    if let snapshot, shouldRestorePasteboard(writtenChangeCount: writtenChangeCount) {
                        restorePasteboard(snapshot)
                    }
                }
            }
        }
    }

    /// 粘贴队列：按顺序逐条粘贴（每条间隔 0.55s），结束后恢复原剪贴板。
    /// 无目标/无 AX 权限时降级为把全部内容按行拼接写入剪贴板。
    public static func pasteSequence(
        contents: [PasteboardContent],
        toPID pid: pid_t?,
        targetApp: NSRunningApplication? = nil,
        suppress: ((TimeInterval) -> Void)? = nil,
        onFallback: ((PasteFallbackReason) -> Void)? = nil
    ) {
        guard !contents.isEmpty else { return }

        if let targetApp, targetApp.isTerminated {
            writePlainTextFallback(contents: contents, suppress: suppress)
            onFallback?(.targetUnavailable)
            return
        }
        guard let pid, pid > 0 else {
            writePlainTextFallback(contents: contents, suppress: suppress)
            onFallback?(.targetUnavailable)
            return
        }
        guard isAccessibilityGranted() else {
            writePlainTextFallback(contents: contents, suppress: suppress)
            promptAccessibility()
            onFallback?(.permissionDenied)
            return
        }

        let snapshot = snapshotPasteboard()
        suppress?(2.0 + Double(contents.count))
        var delay = 0.15
        var isCancelled = false
        var lastWrittenChangeCount = NSPasteboard.general.changeCount

        for content in contents {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard !isCancelled else { return }
                if let targetApp, targetApp.isTerminated {
                    isCancelled = true
                    onFallback?(.targetUnavailable)
                    return
                }

                // CM-07: 每次写入前核验剪贴板归属；若外部产生新复制，立刻终止队列写入并保护用户新内容
                if NSPasteboard.general.changeCount != lastWrittenChangeCount {
                    isCancelled = true
                    onFallback?(.newCopyDetected)
                    return
                }

                lastWrittenChangeCount = write(content)
                let posted = pasteToFrontmost(pid: pid)
                if !posted {
                    onFallback?(.pasteFailed)
                }
            }
            delay += 0.55
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.4) {
            guard !isCancelled else { return }
            if let snapshot, shouldRestorePasteboard(writtenChangeCount: lastWrittenChangeCount) {
                restorePasteboard(snapshot)
            }
        }
    }

    private static func writePlainTextFallback(contents: [PasteboardContent], suppress: ((TimeInterval) -> Void)?) {
        let texts = contents.compactMap { plainText($0) }
        if !texts.isEmpty {
            _ = write(.text(texts.joined(separator: "\n")))
            suppress?(1.5)
        }
    }

    private static func plainText(_ content: PasteboardContent) -> String? {
        switch content {
        case .text(let string): return string
        case .richText(_, let plain): return plain
        case .pdf(_, let plain): return plain
        case .image, .files: return nil
        }
    }
}
