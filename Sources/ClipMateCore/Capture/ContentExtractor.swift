import Foundation

/// 提取出的局部字段类型
public enum FieldKind: String, CaseIterable, Sendable {
    case phone = "phone"
    case email = "email"
    case url = "url"
    case contact = "contact"
    case json = "json"
    case ocrText = "ocr"
    case other = "other"

    public var systemImage: String {
        switch self {
        case .phone: return "phone.fill"
        case .email: return "envelope.fill"
        case .url: return "link"
        case .contact: return "person.crop.circle"
        case .json: return "curlybraces"
        case .ocrText: return "text.viewfinder"
        case .other: return "doc.text"
        }
    }
}

/// 从整段剪贴板内容中提取出的局部字段
public struct ExtractedField: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let value: String
    public let kind: FieldKind
    public let sourceRange: Range<String.Index>?

    public init(label: String, value: String, kind: FieldKind, sourceRange: Range<String.Index>? = nil) {
        self.id = "\(kind.rawValue):\(label):\(value)"
        self.label = label
        self.value = value
        self.kind = kind
        self.sourceRange = sourceRange
    }
}

/// 局部内容提取引擎（纯本地、零网络、高性能）
public enum ContentExtractor {

    // MARK: - 正则表达式缓存

    private static let emailRegex = try? NSRegularExpression(
        pattern: #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#
    )

    private static let urlRegex = try? NSRegularExpression(
        pattern: #"https?://[a-zA-Z0-9\-._~:/?#\[\]@!$&'*+,;=%]+"#
    )

    // 匹配中国大陆手机号（支持 +86 前缀与空格/横杠分隔）
    private static let mobileRegex = try? NSRegularExpression(
        pattern: #"(?:\+?86[- ]?)?1[3-9]\d{1}[- ]?\d{4}[- ]?\d{4}\b"#
    )

    // 匹配座机电话（支持 010-12345678, 0755 88888888 等）
    private static let telRegex = try? NSRegularExpression(
        pattern: #"(?:\+?86[- ]?)?0\d{2,3}[- ]?\d{7,8}\b"#
    )

    // 匹配国际电话（以 + 开头，8~16 位数字）
    private static let intlPhoneRegex = try? NSRegularExpression(
        pattern: #"\+[1-9]\d{0,3}[- ]?(?:\(?\d{1,4}\)?[- ]?)?\d{3,4}[- ]?\d{3,4}\b"#
    )

    // 匹配结构化联系人标签名集合
    private static let contactLabelNames = "姓名|联系人|收件人|公司|单位|部门|职位|职务|手机|电话|座机|邮箱|邮件|地址|收货地址|微信号|微信|QQ|邮编|备注|Name|Contact|Company|Department|Title|Position|Phone|Mobile|Tel|Email|Address|WeChat|Note"

    // 匹配结构化联系人标签行（字段值结束于换行符，或紧随下一合法字段标签处，完整保留地址等内部逗号）
    private static let contactLabelRegex = try? NSRegularExpression(
        pattern: #"(?i)(?:^|[\n,，;；|]|\s)\s*(\#(contactLabelNames))\s*[:：]\s*(.+?)(?=(?:[\n,，;；|]\s*(?:\#(contactLabelNames))\s*[:：]|[\n\r]|\s*$))"#
    )

    // MARK: - 主入口

    /// 从 ClipItem 中提取局部可取用字段
    public static func extractFields(from item: ClipItem) -> [ExtractedField] {
        if item.kind == .image {
            return extractFromImage(item)
        }
        return extractFromText(item.plainText)
    }

    /// 从纯文本中提取所有候选字段
    public static func extractFromText(_ text: String) -> [ExtractedField] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // 避免对超长文本无限制正则扫描（上限 32KB）
        let scanText = trimmed.count > 32768 ? String(trimmed.prefix(32768)) : trimmed

        var results: [ExtractedField] = []
        var seenFieldIDs = Set<String>()

        func addField(_ field: ExtractedField) {
            let normalized = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return }
            // 整段内容如果就等于该字段自身，则不产生多余局部取用胶囊
            if normalized == trimmed { return }
            // 按 field.id 去重（包含 kind, label, value），不同字段允许相同值（如两个不同的 count: 0，或 billing.amount 与 shipping.amount）
            if !seenFieldIDs.contains(field.id) {
                seenFieldIDs.insert(field.id)
                results.append(field)
            }
        }

        // 1. JSON 字段提取（如果是合法 JSON 对象）
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
           (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            let jsonFields = extractJSONFields(from: trimmed)
            if !jsonFields.isEmpty {
                for f in jsonFields { addField(f) }
                return results
            }
        }

        // 2. 结构化联系人资料拆分
        let contactFields = extractContactFields(from: scanText)
        for f in contactFields {
            addField(f)
        }

        // 3. 电话号码提取（手机号、座机、国际号码）
        let phoneFields = extractPhoneNumbers(from: scanText)
        for f in phoneFields {
            addField(f)
        }

        // 4. 邮箱提取
        let emailFields = extractEmails(from: scanText)
        for f in emailFields {
            addField(f)
        }

        // 5. 链接提取
        let urlFields = extractURLs(from: scanText)
        for f in urlFields {
            addField(f)
        }

        return results
    }

    // MARK: - 图片 OCR 文字提取

    private static func extractFromImage(_ item: ClipItem) -> [ExtractedField] {
        var results: [ExtractedField] = []
        let ocrText = item.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ocrText.isEmpty else { return results }

        // 1. 显式整段 OCR 文字快捷复制项
        results.append(ExtractedField(
            label: "识别文字",
            value: ocrText,
            kind: .ocrText,
            sourceRange: ocrText.startIndex..<ocrText.endIndex
        ))

        // 2. 从 OCR 文字中继续提取结构化联系方式/链接等
        let subFields = extractFromText(ocrText)
        results.append(contentsOf: subFields)
        return results
    }

    // MARK: - 联系人资料拆分

    private static func extractContactFields(from text: String) -> [ExtractedField] {
        guard let regex = contactLabelRegex else { return [] }
        var fields: [ExtractedField] = []
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches where match.numberOfRanges >= 3 {
            let labelRange = match.range(at: 1)
            let valRange = match.range(at: 2)
            guard labelRange.location != NSNotFound, valRange.location != NSNotFound else { continue }

            let label = nsText.substring(with: labelRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = nsText.substring(with: valRange).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawValue.isEmpty else { continue }

            let sourceRange = Range(valRange, in: text)

            // 如果电话字段包含多个号码（如 "13800000000、010-88888888"），拆分为多个独立号码
            if isPhoneLabel(label) && (rawValue.contains("、") || rawValue.contains("/") || rawValue.contains(" ") || rawValue.contains(",")) {
                let parts = rawValue.components(separatedBy: CharacterSet(charactersIn: "、/,， "))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && $0.count >= 6 }
                if parts.count > 1 {
                    for (idx, part) in parts.enumerated() {
                        let subLabel = parts.count > 1 ? "\(label) \(idx + 1)" : label
                        fields.append(ExtractedField(label: subLabel, value: part, kind: .phone, sourceRange: text.range(of: part)))
                    }
                    continue
                }
            }

            let kind: FieldKind = isPhoneLabel(label) ? .phone :
                                 (isEmailLabel(label) ? .email :
                                 (isURLLabel(label) ? .url : .contact))

            fields.append(ExtractedField(label: label, value: rawValue, kind: kind, sourceRange: sourceRange))
        }

        return fields
    }

    private static func isPhoneLabel(_ label: String) -> Bool {
        let lower = label.lowercased()
        return lower == "手机" || lower == "电话" || lower == "座机" || lower == "phone" || lower == "mobile" || lower == "tel"
    }

    private static func isEmailLabel(_ label: String) -> Bool {
        let lower = label.lowercased()
        return lower == "邮箱" || lower == "邮件" || lower == "email"
    }

    private static func isURLLabel(_ label: String) -> Bool {
        let lower = label.lowercased()
        return lower == "网址" || lower == "链接" || lower == "url" || lower == "website"
    }

    // MARK: - 电话提取

    private static func extractPhoneNumbers(from text: String) -> [ExtractedField] {
        var fields: [ExtractedField] = []
        let nsText = text as NSString
        var matchedRanges: [NSRange] = []

        let regexes = [mobileRegex, telRegex, intlPhoneRegex].compactMap { $0 }
        for regex in regexes {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                let range = match.range
                // 避免子集重复匹配
                if matchedRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) {
                    continue
                }
                matchedRanges.append(range)
                let value = nsText.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                let isLandline = value.hasPrefix("0") || value.contains("-") && !value.hasPrefix("1")
                let label = isLandline ? "座机" : "手机"
                fields.append(ExtractedField(label: label, value: value, kind: .phone, sourceRange: Range(range, in: text)))
            }
        }
        return fields
    }

    // MARK: - 邮箱提取

    private static func extractEmails(from text: String) -> [ExtractedField] {
        guard let regex = emailRegex else { return [] }
        var fields: [ExtractedField] = []
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            let range = match.range
            let value = nsText.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            fields.append(ExtractedField(label: "邮箱", value: value, kind: .email, sourceRange: Range(range, in: text)))
        }
        return fields
    }

    // MARK: - 链接提取

    private static func extractURLs(from text: String) -> [ExtractedField] {
        guard let regex = urlRegex else { return [] }
        var fields: [ExtractedField] = []
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        // 常见误粘连的末尾英文/半角标点字符集
        let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?)]}\"'")

        for match in matches {
            var rawRange = match.range
            var rawValue = nsText.substring(with: rawRange)

            // 剔除末尾句尾标点符号，如 https://example.com. 中的 '.'
            while !rawValue.isEmpty, let lastChar = rawValue.unicodeScalars.last, trailingPunctuation.contains(lastChar) {
                rawValue.removeLast()
                rawRange.length -= 1
            }

            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            fields.append(ExtractedField(label: "链接", value: trimmed, kind: .url, sourceRange: Range(rawRange, in: text)))
        }
        return fields
    }

    // MARK: - JSON 字段提取（高保真保留原始字符串、前导零与长数字，支持嵌套作用域）

    private static func extractJSONFields(from text: String) -> [ExtractedField] {
        guard let data = text.data(using: .utf8) else { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return []
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        if let dict = json as? [String: Any] {
            return extractFromJSONDict(dict, path: [], searchRange: fullRange, rawText: text)
        } else if let array = json as? [[String: Any]], let first = array.first {
            return extractFromJSONDict(first, path: ["[0]"], searchRange: fullRange, rawText: text)
        }

        return []
    }

    private static func extractFromJSONDict(
        _ dict: [String: Any],
        path: [String],
        searchRange: NSRange,
        rawText: String
    ) -> [ExtractedField] {
        var list: [ExtractedField] = []
        let nsText = rawText as NSString
        let keys = dict.keys.sorted()

        for key in keys {
            let val = dict[key]
            let label = (path + [key]).joined(separator: ".")

            // 在当前 searchRange 内查找 "\"key\"\s*:"
            guard let keyMatch = findKeyInScope(key: key, in: searchRange, nsText: nsText) else {
                continue
            }
            let colonEnd = keyMatch.location + keyMatch.length
            let maxEnd = searchRange.location + searchRange.length

            if let str = val as? String {
                let sourceRange = findLiteralRange(from: colonEnd, maxEnd: maxEnd, nsText: nsText, rawText: rawText)
                list.append(ExtractedField(label: label, value: str, kind: .json, sourceRange: sourceRange))
            } else if let num = val as? NSNumber {
                let (literal, sourceRange) = extractLiteralAndRange(from: colonEnd, maxEnd: maxEnd, nsText: nsText, rawText: rawText)
                let valueStr = literal ?? num.stringValue
                list.append(ExtractedField(label: label, value: valueStr, kind: .json, sourceRange: sourceRange))
            } else if let nested = val as? [String: Any], path.count < 2 {
                // 递归深入一层嵌套对象，精准定位嵌套子块范围
                if let nestedRange = findJSONObjectRange(from: colonEnd, maxEnd: maxEnd, nsText: nsText) {
                    let sub = extractFromJSONDict(nested, path: path + [key], searchRange: nestedRange, rawText: rawText)
                    list.append(contentsOf: sub.prefix(6))
                }
            }

            if list.count >= 20 { break }
        }

        return list
    }

    private static func findKeyInScope(key: String, in scope: NSRange, nsText: NSString) -> NSRange? {
        let pattern = "\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        guard let match = regex.firstMatch(in: nsText as String, range: scope) else { return nil }
        return match.range
    }

    private static func findJSONObjectRange(from colonEnd: Int, maxEnd: Int, nsText: NSString) -> NSRange? {
        guard colonEnd < maxEnd else { return nil }
        var pos = colonEnd
        while pos < maxEnd {
            let ch = nsText.character(at: pos)
            if ch == 0x7B { // '{'
                break
            }
            pos += 1
        }
        guard pos < maxEnd else { return nil }
        let openPos = pos

        var depth = 1
        var inString = false
        var escape = false
        pos += 1

        while pos < maxEnd {
            let ch = nsText.character(at: pos)
            if inString {
                if escape {
                    escape = false
                } else if ch == 0x5C {
                    escape = true
                } else if ch == 0x22 {
                    inString = false
                }
            } else {
                if ch == 0x22 {
                    inString = true
                } else if ch == 0x7B {
                    depth += 1
                } else if ch == 0x7D {
                    depth -= 1
                    if depth == 0 {
                        return NSRange(location: openPos, length: pos - openPos + 1)
                    }
                }
            }
            pos += 1
        }
        return nil
    }

    private static func extractLiteralAndRange(
        from colonEnd: Int,
        maxEnd: Int,
        nsText: NSString,
        rawText: String
    ) -> (literal: String?, range: Range<String.Index>?) {
        guard colonEnd < maxEnd else { return (nil, nil) }
        var pos = colonEnd
        while pos < maxEnd {
            let ch = nsText.character(at: pos)
            if ch != 0x20 && ch != 0x09 && ch != 0x0A && ch != 0x0D {
                break
            }
            pos += 1
        }
        guard pos < maxEnd else { return (nil, nil) }
        let startPos = pos

        let firstCh = nsText.character(at: pos)
        if firstCh == 0x22 { // 引号字符串
            pos += 1
            var escape = false
            while pos < maxEnd {
                let ch = nsText.character(at: pos)
                if escape {
                    escape = false
                } else if ch == 0x5C {
                    escape = true
                } else if ch == 0x22 {
                    pos += 1
                    break
                }
                pos += 1
            }
            let valRange = NSRange(location: startPos, length: pos - startPos)
            var raw = nsText.substring(with: valRange)
            if raw.hasPrefix("\"") && raw.hasSuffix("\"") && raw.count >= 2 {
                raw = String(raw.dropFirst().dropLast())
            }
            return (raw, Range(valRange, in: rawText))
        } else {
            // 数字、布尔值等
            while pos < maxEnd {
                let ch = nsText.character(at: pos)
                if ch == 0x2C || ch == 0x7D || ch == 0x5D || ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D {
                    break
                }
                pos += 1
            }
            let valRange = NSRange(location: startPos, length: pos - startPos)
            let raw = nsText.substring(with: valRange).trimmingCharacters(in: .whitespacesAndNewlines)
            return (raw, Range(valRange, in: rawText))
        }
    }

    private static func findLiteralRange(
        from colonEnd: Int,
        maxEnd: Int,
        nsText: NSString,
        rawText: String
    ) -> Range<String.Index>? {
        extractLiteralAndRange(from: colonEnd, maxEnd: maxEnd, nsText: nsText, rawText: rawText).range
    }
}
