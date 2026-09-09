import Foundation

/// 规则引擎：零成本的自动标签与内容识别（链接/邮箱/色值/代码/JSON）。
public enum AutoTagger {
    public static let urlRegex = try? NSRegularExpression(pattern: #"https?://[^\s<>"']+"#)
    public static let emailRegex = try? NSRegularExpression(pattern: #"[\w.+-]+@[\w-]+\.[\w.-]+"#)
    public static let hexColorRegex = try? NSRegularExpression(pattern: #"(?<![\w#])#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b"#)
    public static let rgbColorRegex = try? NSRegularExpression(pattern: #"rgba?\s*\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})(?:\s*,\s*[0-9.]+)?\s*\)"#, options: .caseInsensitive)
    public static let hslColorRegex = try? NSRegularExpression(pattern: #"hsla?\s*\(\s*(\d{1,3})\s*,\s*(\d{1,3})%\s*,\s*(\d{1,3})%(?:\s*,\s*[0-9.]+)?\s*\)"#, options: .caseInsensitive)

    public static func tags(for text: String, kind: ClipKind) -> [String] {
        switch kind {
        case .image: return ["图片"]
        case .file: return ["文件"]
        case .richText: return ["富文本"]
        case .url: return ["链接"]
        case .pdf: return ["PDF"]
        case .text: return textTags(for: text)
        }
    }

    private static func textTags(for text: String) -> [String] {
        var tags: [String] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return tags }

        // 优化：对于超长文本采样前 16KB 字符，避免对大体积日志/数据做全量正则扫描与关键字过滤
        let scanLimit = min(trimmed.count, 16384)
        let sampleIndex = trimmed.index(trimmed.startIndex, offsetBy: scanLimit)
        let sample = String(trimmed[..<sampleIndex])
        let sampleRange = NSRange(sample.startIndex..., in: sample)

        if trimmed.contains("\n") {
            if isJSON(trimmed) { tags.append("JSON") }
            else if isCode(sample) { tags.append("代码") }
            else { tags.append("长文本") }
        } else {
            if sample.count <= 512, emailRegex?.firstMatch(in: sample, range: sampleRange) != nil { tags.append("邮箱") }
        }
        if urlRegex?.firstMatch(in: sample, range: sampleRange) != nil { tags.append("含链接") }
        if sample.count <= 64, detectColor(in: sample) != nil { tags.append("颜色") }
        // 号码类内容无语义，靠类型标签 + 分类过滤找回（手机号/银行卡/身份证/快递单号…）
        if let numberKind = NumberRecognizer.detect(sample) {
            tags.append(numberKind.rawValue)
        }
        return tags
    }

    /// 整段文本是单个 URL 时返回该 URL。
    public static func detectURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains("\n"), trimmed.count <= 2048 else { return nil }
        guard let regex = urlRegex,
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              match.range == NSRange(trimmed.startIndex..., in: trimmed) else { return nil }
        return URL(string: trimmed)
    }

    /// 支持全格式色值检测（#RGB, #RRGGBB, #RRGGBBAA, rgb(...), rgba(...), hsl(...)），返回归一化 #RRGGBB。
    public static func detectColor(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 64 else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)

        // 1. Hex: #RGB / #RRGGBB / #RRGGBBAA
        if let regex = hexColorRegex, let match = regex.firstMatch(in: trimmed, range: range) {
            let matched = String(trimmed[Range(match.range, in: trimmed)!]).uppercased()
            let rawHex = matched.dropFirst() // 剥去 #
            if rawHex.count == 3 {
                return "#" + rawHex.map { "\($0)\($0)" }.joined()
            } else if rawHex.count == 6 {
                return "#" + rawHex
            } else if rawHex.count == 8 {
                return "#" + String(rawHex.prefix(6))
            }
        }

        // 2. rgb(r, g, b) / rgba(r, g, b, a)
        if let regex = rgbColorRegex, let match = regex.firstMatch(in: trimmed, range: range), match.numberOfRanges >= 4 {
            let nsStr = trimmed as NSString
            let rStr = nsStr.substring(with: match.range(at: 1))
            let gStr = nsStr.substring(with: match.range(at: 2))
            let bStr = nsStr.substring(with: match.range(at: 3))
            if let r = Int(rStr), let g = Int(gStr), let b = Int(bStr) {
                let cr = min(max(r, 0), 255)
                let cg = min(max(g, 0), 255)
                let cb = min(max(b, 0), 255)
                return String(format: "#%02X%02X%02X", cr, cg, cb)
            }
        }

        // 3. hsl(h, s%, l%)
        if let regex = hslColorRegex, let match = regex.firstMatch(in: trimmed, range: range), match.numberOfRanges >= 4 {
            let nsStr = trimmed as NSString
            let hStr = nsStr.substring(with: match.range(at: 1))
            let sStr = nsStr.substring(with: match.range(at: 2))
            let lStr = nsStr.substring(with: match.range(at: 3))
            if let h = Double(hStr), let s = Double(sStr), let l = Double(lStr) {
                let (r, g, b) = hslToRGB(h: h / 360.0, s: s / 100.0, l: l / 100.0)
                return String(format: "#%02X%02X%02X", r, g, b)
            }
        }

        return nil
    }

    /// 根据十六进制色值生成直观易懂的中文色彩语义名称
    public static func friendlyColorName(for hex: String) -> String? {
        let cleanHex = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "").uppercased()
        guard cleanHex.count == 6, let value = UInt32(cleanHex, radix: 16) else { return nil }

        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0

        // 常见特殊色值精准匹配
        let exactMatches: [UInt32: String] = [
            0x000000: "纯黑", 0xFFFFFF: "纯白", 0xFF0000: "纯红", 0x00FF00: "纯绿",
            0x0000FF: "纯蓝", 0xFFFF00: "黄色", 0x00FFFF: "青色", 0xFF00FF: "洋红",
            0x808080: "中度灰", 0xC0C0C0: "银白灰", 0x4A90D9: "主题蓝", 0x3B82F6: "科技蓝",
            0x10B981: "翡翠绿", 0xF59E0B: "活力橙", 0xEF4444: "珊瑚红", 0x8B5CF6: "紫罗兰"
        ]
        if let exact = exactMatches[value] { return exact }

        let maxVal = max(r, g, b)
        let minVal = min(r, g, b)
        let delta = maxVal - minVal
        let l = (maxVal + minVal) / 2.0

        if delta < 0.04 {
            if l < 0.15 { return "暗黑色" }
            if l > 0.88 { return "浅白灰" }
            return "灰色系"
        }

        var h: Double = 0.0
        if maxVal == r {
            h = (g - b) / delta + (g < b ? 6 : 0)
        } else if maxVal == g {
            h = (b - r) / delta + 2
        } else {
            h = (r - g) / delta + 4
        }
        h *= 60.0

        switch h {
        case 345...360, 0..<15: return "红色系"
        case 15..<45: return "橙色系"
        case 45..<70: return "黄色系"
        case 70..<165: return "绿色系"
        case 165..<200: return "青绿系"
        case 200..<260: return "蓝色系"
        case 260..<315: return "紫色系"
        default: return "粉红系"
        }
    }

    private static func hslToRGB(h: Double, s: Double, l: Double) -> (Int, Int, Int) {
        if s == 0 {
            let v = Int(l * 255.0)
            return (v, v, v)
        }
        let q = l < 0.5 ? l * (1.0 + s) : l + s - l * s
        let p = 2.0 * l - q
        let r = hue2rgb(p: p, q: q, t: h + 1.0 / 3.0)
        let g = hue2rgb(p: p, q: q, t: h)
        let b = hue2rgb(p: p, q: q, t: h - 1.0 / 3.0)
        return (Int(r * 255.0), Int(g * 255.0), Int(b * 255.0))
    }

    private static func hue2rgb(p: Double, q: Double, t: Double) -> Double {
        var t = t
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1.0 / 6.0 { return p + (q - p) * 6.0 * t }
        if t < 1.0 / 2.0 { return q }
        if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6.0 }
        return p
    }


    public static func isCode(_ text: String) -> Bool {
        let markers = ["func ", "def ", "class ", "import ", "const ", "return ", "};", ");",
                       "->", "=>", "==", "<!--", "SELECT ", "public ", "#include", "```"]
        return markers.filter { text.contains($0) }.count >= 2
    }

    public static func isJSON(_ text: String) -> Bool {
        guard text.hasPrefix("{") || text.hasPrefix("[") else { return false }
        // 优化：超过 256KB 的文本避免调用 JSONSerialization 尝试全量解析，防止内存与 CPU 暴涨
        guard text.utf8.count <= 262_144 else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil
    }
}
