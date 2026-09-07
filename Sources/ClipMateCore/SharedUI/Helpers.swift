import AppKit
import ImageIO
import PDFKit
import CryptoKit

extension Notification.Name {
    /// 面板唤起后让搜索框获得焦点。
    static let clipmateFocusSearch = Notification.Name("clipmate.focusSearch")
}

/// PDF 首页渲染。
public enum PDFHelper {
    public static func firstPageThumbnail(from data: Data, maxPixel: Int) -> Data? {
        guard let document = PDFDocument(data: data), let page = document.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale = min(2, max(0.3, CGFloat(maxPixel) / max(bounds.width, bounds.height)))
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { return nil }
        return png
    }

    public static func firstPageImage(from data: Data) -> NSImage? {
        guard let thumbnail = firstPageThumbnail(from: data, maxPixel: 1024) else { return nil }
        return NSImage(data: thumbnail)
    }
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
    private static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    /// 手写相对时间：RelativeDateTimeFormatter 每次调用开销大（列表渲染热点）。
    public static func relative(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        switch interval {
        case ..<0: return "刚刚"
        case ..<60: return "刚刚"
        case ..<3600: return "\(Int(interval / 60))分钟前"
        case ..<86400: return "\(Int(interval / 3600))小时前"
        case ..<(86400 * 30): return "\(Int(interval / 86400))天前"
        default: return shortFormatter.string(from: date)
        }
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
