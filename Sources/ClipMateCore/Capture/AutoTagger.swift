import Foundation

/// 规则引擎：零成本的自动标签与内容识别（链接/邮箱/色值/代码/JSON）。
public enum AutoTagger {
    public static let urlRegex = try? NSRegularExpression(pattern: #"https?://[^\s<>"']+"#)
    public static let emailRegex = try? NSRegularExpression(pattern: #"[\w.+-]+@[\w-]+\.[\w.-]+"#)
    public static let hexColorRegex = try? NSRegularExpression(pattern: #"(?<![\w#])#[0-9a-fA-F]{6}\b"#)

    public static func tags(for text: String, kind: ClipKind) -> [String] {
        switch kind {
        case .image: return ["图片"]
        case .file: return ["文件"]
        case .richText: return ["富文本"]
        case .url: return ["链接"]
        case .text: return textTags(for: text)
        }
    }

    private static func textTags(for text: String) -> [String] {
        var tags: [String] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)

        if trimmed.contains("\n") {
            if isJSON(trimmed) { tags.append("JSON") }
            else if isCode(trimmed) { tags.append("代码") }
            else { tags.append("长文本") }
        } else {
            if emailRegex?.firstMatch(in: trimmed, range: range) != nil { tags.append("邮箱") }
        }
        if urlRegex?.firstMatch(in: trimmed, range: range) != nil { tags.append("含链接") }
        if detectColor(in: trimmed) != nil { tags.append("颜色") }
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

    /// 文本为纯色值（#RRGGBB）时返回大写色值。
    public static func detectColor(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 64, let regex = hexColorRegex,
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) else { return nil }
        return String(trimmed[Range(match.range, in: trimmed)!]).uppercased()
    }

    public static func isCode(_ text: String) -> Bool {
        let markers = ["func ", "def ", "class ", "import ", "const ", "return ", "};", ");",
                       "->", "=>", "==", "<!--", "SELECT ", "public ", "#include", "```"]
        return markers.filter { text.contains($0) }.count >= 2
    }

    public static func isJSON(_ text: String) -> Bool {
        guard text.hasPrefix("{") || text.hasPrefix("[") else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil
    }
}
