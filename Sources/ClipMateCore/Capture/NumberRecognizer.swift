import Foundation

/// 号码类内容的细分类型（纯规则识别，零网络零成本）。
public enum NumberKind: String, CaseIterable, Sendable {
    case phone = "手机号"
    case telephone = "座机"
    case bankCard = "银行卡"
    case idCard = "身份证"
    case tracking = "快递单号"
    case ipAddress = "IP"
    case amount = "金额"
    case plain = "数字"

    /// FilterKind.number 用于匹配的标签集合。
    public static var allTags: [String] { allCases.map(\.rawValue) }
}

/// 号码识别与展示工具：判断"这串东西是不是号码、是哪一类号码"。
///
/// 号码类内容没有语义，全文/语义检索都很难命中，因此改为按类型打标签、
/// 按位数与结构过滤，并把数字按人类习惯分组展示，降低扫视成本。
public enum NumberRecognizer {
    /// 参与号码判定的最大长度（超过则视为普通文本）。
    private static let maxLength = 64
    /// 认定为号码的最少数字位数。
    private static let minDigits = 6

    // MARK: - 识别

    /// 识别整段文本的号码类型；不是号码返回 nil。
    public static func detect(_ text: String) -> NumberKind? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength, !trimmed.contains("\n") else { return nil }

        let compact = strippingSeparators(trimmed)

        if isIDCard(compact) { return .idCard }
        if isBankCard(compact) { return .bankCard }
        if isMobile(compact) { return .phone }
        if isTelephone(compact) { return .telephone }
        if isIPv4(trimmed) { return .ipAddress }
        if isTracking(trimmed) { return .tracking }
        if isAmount(trimmed) { return .amount }
        if isPlainDigits(compact) { return .plain }
        return nil
    }

    /// 号码归一化：仅保留数字（身份证校验位 X 保留为小写 x），用于相似号码聚合。
    /// 含字母、符号等非号码字符时返回 nil。
    public static func normalize(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength, !trimmed.contains("\n") else { return nil }

        var digits = ""
        var hasCheckLetter = false
        for ch in trimmed {
            if ch.isNumber {
                digits.append(ch)
            } else if ch == "X" || ch == "x" {
                hasCheckLetter = true
            } else if ch == "-" || ch == " " || ch == "+" || ch == "(" || ch == ")" {
                continue
            } else {
                return nil
            }
        }
        guard digits.count >= minDigits else { return nil }
        return hasCheckLetter ? digits + "x" : digits
    }

    /// 是否为号码类内容（用于列表展示与聚合判定）。
    public static func isNumberLike(_ text: String) -> Bool {
        detect(text) != nil
    }

    // MARK: - 展示分组

    /// 列表/详情展示用文本：号码类内容按人类习惯分组；不是号码返回 nil。
    public static func displayText(_ text: String) -> String? {
        guard let kind = detect(text) else { return nil }
        return grouped(text, kind: kind) ?? text
    }

    /// 按人类阅读习惯给数字分组（仅用于展示，不改动原始内容）。
    /// 例如手机号 13812345678 → 138 1234 5678，卡号按 4 位一组。
    public static func grouped(_ text: String, kind: NumberKind) -> String? {
        let compact = strippingSeparators(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard isAllDigits(compact) else { return nil }

        switch kind {
        case .phone where compact.count == 11:
            return split(compact, sizes: [3, 4, 4])
        case .telephone:
            return nil
        case .bankCard where compact.count >= 15 && compact.count <= 19:
            return split(compact, sizes: Array(repeating: 4, count: compact.count / 4) + (compact.count % 4 == 0 ? [] : [compact.count % 4]))
        case .idCard where compact.count == 18:
            return split(compact, sizes: [6, 8, 4])
        case .plain where compact.count > 6:
            return split(compact, sizes: Array(repeating: 3, count: compact.count / 3) + (compact.count % 3 == 0 ? [] : [compact.count % 3]))
        default:
            return nil
        }
    }

    private static func split(_ text: String, sizes: [Int]) -> String? {
        guard sizes.reduce(0, +) == text.count else { return nil }
        var result: [String] = []
        var index = text.startIndex
        for size in sizes {
            let end = text.index(index, offsetBy: size)
            result.append(String(text[index..<end]))
            index = end
        }
        return result.joined(separator: " ")
    }

    // MARK: - 判定规则

    private static func strippingSeparators(_ text: String) -> String {
        text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private static func isAllDigits(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy(\.isNumber)
    }

    private static func isMobile(_ text: String) -> Bool {
        guard isAllDigits(text), text.count == 11, text.hasPrefix("1") else { return false }
        guard let second = text.dropFirst().first?.wholeNumberValue else { return false }
        return (3...9).contains(second)
    }

    /// 座机：0 + 2~3 位区号 + 7~8 位号码（如 010-12345678、0755-88888888）。
    private static func isTelephone(_ text: String) -> Bool {
        guard isAllDigits(text), text.hasPrefix("0") else { return false }
        return (10...12).contains(text.count)
    }

    private static func isIPv4(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isNumber),
                  let value = Int(part), (0...255).contains(value) else { return false }
        }
        return true
    }

    /// 身份证：18 位 + GB 11643 校验位。
    private static func isIDCard(_ text: String) -> Bool {
        guard text.count == 18 else { return false }
        let chars = Array(text)
        let weights = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2]
        let checks: [Character] = ["1", "0", "X", "9", "8", "7", "6", "5", "4", "3", "2"]

        var sum = 0
        for index in 0..<17 {
            guard let value = chars[index].wholeNumberValue else { return false }
            sum += value * weights[index]
        }
        let expected = checks[sum % 11]
        let last = chars[17]
        return last == expected || (expected == "X" && last == "x")
    }

    /// 银行卡：16~19 位且通过 Luhn 校验。
    private static func isBankCard(_ text: String) -> Bool {
        guard isAllDigits(text), (16...19).contains(text.count) else { return false }
        var sum = 0
        for (index, digit) in text.reversed().compactMap(\.wholeNumberValue).enumerated() {
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    /// 快递/订单单号：字母数字混合，至少 6 位数字（如 SF1234567890）。
    private static func isTracking(_ text: String) -> Bool {
        guard (8...30).contains(text.count) else { return false }
        guard text.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return false }
        let digits = text.filter(\.isNumber).count
        let letters = text.filter(\.isLetter).count
        return digits >= minDigits && letters >= 1
    }

    /// 金额：带货币符号、千分位或两位小数，避免把纯整数误判为金额。
    private static func isAmount(_ text: String) -> Bool {
        var body = text
        let symbols = "¥$€£"
        let hadSymbol = body.first.map { symbols.contains($0) } ?? false
        if hadSymbol { body.removeFirst() }
        guard !body.isEmpty else { return false }
        guard body.range(of: #"^\d{1,3}(,\d{3})*(\.\d{1,2})?$"#, options: .regularExpression) != nil else { return false }
        return hadSymbol || body.contains(",") || body.contains(".")
    }

    /// 纯数字：4~24 位，作为兜底类型。
    private static func isPlainDigits(_ text: String) -> Bool {
        isAllDigits(text) && (4...24).contains(text.count)
    }
}
