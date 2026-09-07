import AppKit
import ImageIO
import Vision
import PDFKit

/// 从 NSPasteboard 读出的一次采集内容（格式优先级：文件 URL > 图片 > 富文本 > 纯文本）。
public struct CapturedContent {
    public var kind: ClipKind
    public var plainText: String
    public var tags: [String]
    public var inlineData: Data?
    public var imageOriginal: Data?
    public var meta: [String: String]
}

public enum ClipboardReader {
    /// 读取失败 / 不采集时返回 nil。ocrEnabled 时对图片做文字识别，结果并入 plainText 参与检索。
    public static func read(from pb: NSPasteboard, maxBytes: Int, ocrEnabled: Bool = true) -> CapturedContent? {
        guard let types = pb.types, !types.isEmpty else { return nil }
        // 我们自己写回剪贴板的内容不再采集（配合时间窗双重防护）。
        if types.contains(PasteBack.ownedMarker) { return nil }

        if let content = readFileURLs(pb: pb) { return content }
        if let content = readPDF(pb: pb, maxBytes: maxBytes) { return content }
        if let content = readImage(pb: pb, maxBytes: maxBytes) { return content }
        if let content = readRichText(pb: pb, maxBytes: maxBytes) { return content }
        if let content = readPlainText(pb: pb, maxBytes: maxBytes) { return content }
        return nil
    }

    /// PDF：首页缩略图 + 全文提取（可检索）。
    private static func readPDF(pb: NSPasteboard, maxBytes: Int) -> CapturedContent? {
        let types = pb.types ?? []
        guard types.contains(.pdf),
              let data = pb.data(forType: .pdf), !data.isEmpty, data.count <= maxBytes else { return nil }
        guard let thumbnail = PDFHelper.firstPageThumbnail(from: data, maxPixel: 512) else { return nil }

        var meta: [String: String] = [:]
        var extracted = ""
        if let document = PDFDocument(data: data) {
            meta["display"] = "PDF · \(document.pageCount) 页"
            extracted = String((document.string ?? "").prefix(4000))
        }

        return CapturedContent(
            kind: .pdf,
            plainText: extracted,
            tags: AutoTagger.tags(for: "", kind: .pdf),
            inlineData: thumbnail,
            imageOriginal: data,
            meta: meta
        )
    }

    private static func readFileURLs(pb: NSPasteboard) -> CapturedContent? {
        guard let nsURLs = pb.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [NSURL],
              !nsURLs.isEmpty else { return nil }
        let urls = nsURLs.map { $0 as URL }
        let display = urls.map { $0.lastPathComponent }.joined(separator: ", ")
        let paths = urls.map { $0.absoluteString }.joined(separator: "\n")
        return CapturedContent(
            kind: .file,
            plainText: paths,
            tags: AutoTagger.tags(for: display, kind: .file),
            inlineData: nil,
            imageOriginal: nil,
            meta: ["display": display]
        )
    }

    private static func readImage(pb: NSPasteboard, maxBytes: Int) -> CapturedContent? {
        guard let data = pb.data(forType: .png) ?? pb.data(forType: .tiff),
              !data.isEmpty, data.count <= maxBytes else { return nil }
        guard let thumbnail = ImageHelper.thumbnailData(from: data, maxPixel: 512) else { return nil }
        var meta: [String: String] = [:]
        if let (w, h) = ImageHelper.dimensions(of: data) {
            meta["display"] = "图片 \(w)×\(h)"
        }

        // 优化：OCR 改为入库后后台异步执行，绝不阻塞当前采集队列
        return CapturedContent(
            kind: .image,
            plainText: "",
            tags: AutoTagger.tags(for: "", kind: .image),
            inlineData: thumbnail,
            imageOriginal: data,
            meta: meta
        )
    }

    /// Vision 文字识别（中英混合）。识别失败/无文字返回 nil。
    public static func recognizeText(in imageData: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let lines = (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first?.string
        }
        let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    private static func readRichText(pb: NSPasteboard, maxBytes: Int) -> CapturedContent? {
        let types = pb.types ?? []
        guard types.contains(.rtf) || types.contains(.html) else { return nil }
        guard let plain = pb.string(forType: .string), !plain.isEmpty else { return nil }
        guard plain.utf8.count <= maxBytes else { return nil }
        let rich = pb.data(forType: .rtf) ?? pb.data(forType: .html)
        return CapturedContent(
            kind: .richText,
            plainText: plain,
            tags: AutoTagger.tags(for: plain, kind: .richText),
            inlineData: rich,
            imageOriginal: nil,
            meta: [:]
        )
    }

    private static func readPlainText(pb: NSPasteboard, maxBytes: Int) -> CapturedContent? {
        guard let plain = pb.string(forType: .string), !plain.isEmpty, plain.utf8.count <= maxBytes else { return nil }

        var meta: [String: String] = [:]
        if let sourceURL = pb.string(forType: .init("org.chromium.source-url")), !sourceURL.isEmpty {
            meta["sourceURL"] = sourceURL
        }
        let kind: ClipKind = AutoTagger.detectURL(in: plain) != nil ? .url : .text
        if let color = AutoTagger.detectColor(in: plain) {
            meta["color"] = color
        }
        return CapturedContent(
            kind: kind,
            plainText: plain,
            tags: AutoTagger.tags(for: plain, kind: kind),
            inlineData: nil,
            imageOriginal: nil,
            meta: meta
        )
    }
}
