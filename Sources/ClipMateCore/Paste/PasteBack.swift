import AppKit
import ApplicationServices
import CoreGraphics

/// 写回剪贴板的内容形态。
public enum PasteboardContent {
    case text(String)
    case richText(rtf: Data, plain: String)
    case image(data: Data)
    case files([URL])
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

    public static func write(_ content: PasteboardContent) {
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
        }
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

    // MARK: - 合成 ⌘V

    public static func pasteToFrontmost(pid: pid_t) -> Bool {
        guard isAccessibilityGranted() else {
            promptAccessibility()
            return false
        }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(pid)
        usleep(25_000)
        up.postToPid(pid)
        return true
    }

    /// 完整粘贴流程（主线程调用）：写 → 粘贴 → 延迟恢复原剪贴板。
    public static func paste(content: PasteboardContent,
                             toPID pid: pid_t?,
                             suppress: ((TimeInterval) -> Void)? = nil) {
        let snapshot = snapshotPasteboard()
        write(content)
        suppress?(1.8)
        guard let pid, pid > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let posted = pasteToFrontmost(pid: pid)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                if posted, let snapshot { restorePasteboard(snapshot) }
            }
        }
    }

    /// 粘贴队列：按顺序逐条粘贴（每条间隔 0.55s），结束后恢复原剪贴板。
    /// 无目标/无 AX 权限时降级为把全部内容按行拼接写入剪贴板。
    public static func pasteSequence(contents: [PasteboardContent],
                                     toPID pid: pid_t?,
                                     suppress: ((TimeInterval) -> Void)? = nil) {
        guard !contents.isEmpty else { return }
        guard let pid, pid > 0, isAccessibilityGranted() else {
            let texts = contents.compactMap { plainText($0) }
            if !texts.isEmpty {
                write(.text(texts.joined(separator: "\n")))
                suppress?(1.5)
            }
            return
        }
        let snapshot = snapshotPasteboard()
        suppress?(2.0 + Double(contents.count))
        var delay = 0.15
        for content in contents {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                write(content)
                _ = pasteToFrontmost(pid: pid)
            }
            delay += 0.55
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.4) {
            if let snapshot { restorePasteboard(snapshot) }
        }
    }

    private static func plainText(_ content: PasteboardContent) -> String? {
        switch content {
        case .text(let string): return string
        case .richText(_, let plain): return plain
        case .image, .files: return nil
        }
    }
}
