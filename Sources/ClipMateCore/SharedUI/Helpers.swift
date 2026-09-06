import AppKit
import ImageIO
import CryptoKit

extension Notification.Name {
    /// 面板唤起后让搜索框获得焦点。
    static let clipmateFocusSearch = Notification.Name("clipmate.focusSearch")
}

/// 图片缩略图与元信息。
public enum ImageHelper {
    /// 生成 ≤ maxPixel 的 PNG 缩略图数据。
    public static func thumbnailData(from data: Data, maxPixel: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }

    /// 读取图片尺寸（用于展示"图片 WxH"）。
    public static func dimensions(of data: Data) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }
}

public enum TimeHelper {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    public static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

public enum SizeHelper {
    public static func human(_ bytes: Int) -> String {
        switch bytes {
        case ..<1024: return "\(bytes) B"
        case ..<(1024 * 1024): return String(format: "%.1f KB", Double(bytes) / 1024)
        default: return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }
}
