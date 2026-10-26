import Foundation
import AppKit

/// 链接元数据抓取器：在后台异步抓取网页标题与 Favicon 图标。
/// 严格 2.5s 超时控制，流式读取前 32KB HTML，零第三方外部依赖。
public enum URLMetadataFetcher {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.5
        config.timeoutIntervalForResource = 3.0
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8"
        ]
        return URLSession(configuration: config)
    }()

    /// 异步抓取指定链接的标题与图标
    public static func fetchMetadata(for url: URL) async -> (title: String?, favicon: Data?) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return (nil, nil)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2.5

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...399).contains(httpResponse.statusCode) else {
                return (nil, nil)
            }

            var buffer = Data()
            buffer.reserveCapacity(32768)
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 32768 { break }
            }

            let html = String(decoding: buffer, as: UTF8.self)
            let title = extractTitle(from: html)
            let iconURL = extractIconURL(from: html, baseURL: httpResponse.url ?? url)

            var faviconData: Data? = nil
            if let iconURL {
                faviconData = await downloadFavicon(from: iconURL)
            }
            if faviconData == nil, let defaultIconURL = URL(string: "/favicon.ico", relativeTo: httpResponse.url ?? url)?.absoluteURL, defaultIconURL != iconURL {
                faviconData = await downloadFavicon(from: defaultIconURL)
            }

            return (title, faviconData)
        } catch {
            return (nil, nil)
        }
    }

    /// 从 HTML 中提取 `<title>`
    public static func extractTitle(from html: String) -> String? {
        let pattern = #"(?is)<title[^>]*>(.*?)</title>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsRange = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: nsRange),
              match.numberOfRanges > 1 else { return nil }
        let titleRange = match.range(at: 1)
        guard let range = Range(titleRange, in: html) else { return nil }
        let rawTitle = String(html[range])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTitle.isEmpty else { return nil }
        return decodeHTMLEntities(rawTitle)
    }

    /// 从 HTML 中提取 Favicon 链接
    public static func extractIconURL(from html: String, baseURL: URL) -> URL? {
        let linkTagPattern = #"(?is)<link\b[^>]+>"#
        guard let tagRegex = try? NSRegularExpression(pattern: linkTagPattern, options: []) else { return nil }
        let relRegex = try? NSRegularExpression(pattern: #"(?i)rel\s*=\s*["']?([^"'>\s]+)"#, options: [])
        let hrefRegex = try? NSRegularExpression(pattern: #"(?i)href\s*=\s*["']?([^"'>\s]+)"#, options: [])

        let nsRange = NSRange(html.startIndex..., in: html)
        let matches = tagRegex.matches(in: html, options: [], range: nsRange)

        for match in matches {
            guard let linkRange = Range(match.range, in: html) else { continue }
            let linkTag = String(html[linkRange])
            let tagRange = NSRange(linkTag.startIndex..., in: linkTag)

            // 检查 rel 属性是否包含 icon
            if let relMatch = relRegex?.firstMatch(in: linkTag, options: [], range: tagRange),
               relMatch.numberOfRanges > 1,
               let relSubRange = Range(relMatch.range(at: 1), in: linkTag) {
                let relValue = String(linkTag[relSubRange]).lowercased()
                if relValue.contains("icon") {
                    if let hrefMatch = hrefRegex?.firstMatch(in: linkTag, options: [], range: tagRange),
                       hrefMatch.numberOfRanges > 1,
                       let hrefSubRange = Range(hrefMatch.range(at: 1), in: linkTag) {
                        let href = String(linkTag[hrefSubRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !href.isEmpty, let resolved = URL(string: href, relativeTo: baseURL)?.absoluteURL {
                            return resolved
                        }
                    }
                }
            }
        }
        return nil
    }

    /// 下载 Favicon 并转为小尺寸缩略图
    private static func downloadFavicon(from iconURL: URL) async -> Data? {
        var req = URLRequest(url: iconURL)
        req.timeoutInterval = 1.5
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await session.data(for: req),
              let httpResp = resp as? HTTPURLResponse,
              (200...299).contains(httpResp.statusCode),
              data.count > 0 && data.count <= 65536 else {
            return nil
        }

        // 尝试通过 ImageHelper 生成 ≤48 像素的紧凑图标
        if let thumb = ImageHelper.thumbnailData(from: data, maxPixel: 48) {
            return thumb
        }
        if NSImage(data: data) != nil {
            return data
        }
        return nil
    }

    /// 解码常见 HTML 字符实体
    public static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&middot;", with: "·")

        // 支持数字实体：&#123; 与十六进制 &#x1f600;
        let pattern = "&#(x[0-9a-fA-F]+|\\d+);"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
            for match in matches.reversed() {
                let entityRange = match.range(at: 1)
                let raw = nsString.substring(with: entityRange)
                var charCode: UInt32?
                if raw.lowercased().hasPrefix("x") {
                    let hex = String(raw.dropFirst())
                    charCode = UInt32(hex, radix: 16)
                } else {
                    charCode = UInt32(raw, radix: 10)
                }
                if let code = charCode, let scalar = UnicodeScalar(code) {
                    let replacement = String(Character(scalar))
                    result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
                }
            }
        }

        // &amp; 必须最后解码，防止 double-unescaping（如 &amp;lt; 被错误解为 <）
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        return result
    }
}
