import Foundation

/// 解析后的检索条件：普通关键词 + 结构化过滤。
///
/// 号码这类"记不住内容"的东西，用结构条件找比用字面找有效得多：
/// `#11`（11 位数字）、`app:微信`、`before:昨天`、`138*`（前缀）。
public struct ParsedQuery: Equatable, Sendable {
    /// 普通关键词（走全文/语义检索）。
    public var terms: [String] = []
    /// `#N`：数字位数恰好 N 位。
    public var digitCount: Int?
    /// `#>N`：数字位数大于 N。
    public var minDigits: Int?
    /// `#<N`：数字位数小于 N。
    public var maxDigits: Int?
    /// `len:N`：内容长度恰好 N。
    public var length: Int?
    /// `len:>N` / `len:<N`。
    public var minLength: Int?
    public var maxLength: Int?
    /// `app:微信`：来源应用（名称或 Bundle ID 模糊匹配）。
    public var source: String?
    /// `before:2026-09-01` / `before:昨天`。
    public var before: Date?
    /// `after:2026-09-01` / `after:本月`。
    public var after: Date?
    /// `138*`：前缀匹配。
    public var prefix: String?

    public init() {}

    /// 是否包含结构化过滤条件（含则跳过 FTS，走带条件的 LIKE 路径）。
    public var hasFilters: Bool {
        digitCount != nil || minDigits != nil || maxDigits != nil
            || length != nil || minLength != nil || maxLength != nil
            || source != nil || before != nil || after != nil || prefix != nil
    }

    /// 是否为空查询（无关键词也无条件）。
    public var isEmpty: Bool {
        terms.isEmpty && !hasFilters
    }
}

/// 检索语法解析器（对普通查询完全透明：无法识别的词一律当作关键词）。
public enum SearchQueryParser {
    public static func parse(_ raw: String) -> ParsedQuery {
        var result = ParsedQuery()
        let tokens = raw.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)

        for token in tokens {
            let lower = token.lowercased()

            if token.hasPrefix("#") {
                let value = String(token.dropFirst())
                if let count = Int(value) { result.digitCount = count; continue }
                if value.hasPrefix(">"), let count = Int(value.dropFirst()) { result.minDigits = count; continue }
                if value.hasPrefix("<"), let count = Int(value.dropFirst()) { result.maxDigits = count; continue }
            }

            if lower.hasPrefix("len:") {
                let value = String(token.dropFirst(4))
                if let count = Int(value) { result.length = count; continue }
                if value.hasPrefix(">"), let count = Int(value.dropFirst()) { result.minLength = count; continue }
                if value.hasPrefix("<"), let count = Int(value.dropFirst()) { result.maxLength = count; continue }
            }

            if lower.hasPrefix("app:") {
                let value = String(token.dropFirst(4))
                if !value.isEmpty { result.source = value; continue }
            }

            if lower.hasPrefix("before:"), let date = parseDate(String(token.dropFirst(7))) {
                result.before = date
                continue
            }
            if lower.hasPrefix("after:"), let date = parseDate(String(token.dropFirst(6))) {
                result.after = date
                continue
            }

            if token.hasSuffix("*"), token.count > 1 {
                result.prefix = String(token.dropLast())
                continue
            }

            result.terms.append(token)
        }
        return result
    }

    /// 支持 `yyyy-MM-dd` 与今天/昨天/前天/本周/本月。
    private static func parseDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let calendar = Calendar.current
        let now = Date()

        switch trimmed.lowercased() {
        case "今天", "today": return calendar.startOfDay(for: now)
        case "昨天", "yesterday": return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
        case "前天": return calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: now))
        case "本周", "thisweek": return calendar.dateInterval(of: .weekOfYear, for: now)?.start
        case "本月", "thismonth": return calendar.dateInterval(of: .month, for: now)?.start
        default: break
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: trimmed)
    }
}
