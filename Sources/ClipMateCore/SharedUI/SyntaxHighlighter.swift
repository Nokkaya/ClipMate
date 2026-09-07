import Foundation
import AppKit
import SwiftUI

/// 原生轻量代码与 JSON 语法高亮引擎。
/// 基于 NSRegularExpression 与 AttributedString，零第三方外部依赖。
public enum SyntaxHighlighter {
    private static let maxHighlightLength = 65_536

    // MARK: - 正则表达式缓存

    private static let jsonKeyRegex = try? NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*"\s*(?=:)"#)
    private static let jsonStringValRegex = try? NSRegularExpression(pattern: #":\s*("([^"\\]|\\.)*")"#)
    private static let jsonNumberValRegex = try? NSRegularExpression(pattern: #":\s*(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"#)
    private static let jsonBoolValRegex = try? NSRegularExpression(pattern: #":\s*(true|false)\b"#)
    private static let jsonNullValRegex = try? NSRegularExpression(pattern: #":\s*(null)\b"#)

    private static let codeCommentRegex = try? NSRegularExpression(pattern: #"(?m)(//[^\n]*|/\*[\s\S]*?\*/|#[^\n]*)"#)
    private static let codeStringRegex = try? NSRegularExpression(pattern: #"("[^"\\\n]*(?:\\.[^"\\\n]*)*"|'[^'\\\n]*(?:\\.[^'\\\n]*)*'|`[^`\\]*(?:\\.[^`\\]*)*`)"#)
    private static let codeNumberRegex = try? NSRegularExpression(pattern: #"\b\d+(?:\.\d+)?\b"#)
    private static let codeKeywordRegex = try? NSRegularExpression(pattern: #"\b(func|function|class|struct|enum|protocol|extension|let|var|const|val|def|import|export|from|as|return|if|else|elif|switch|case|default|for|in|of|while|do|try|catch|finally|throw|throws|async|await|guard|self|this|super|public|private|protected|internal|fileprivate|open|static|mutating|override|final|typealias|interface|package|implements|extends|nil|null|true|false|None|True|False)\b"#)

    // MARK: - JSON 格式化与高亮

    /// 尝试格式化 JSON 字符串（2 空格缩进）；若非合法 JSON 则返回 nil
    public static func formatJSON(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["), trimmed.utf8.count <= 1_048_576 else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let result = String(data: prettyData, encoding: .utf8) else {
            return nil
        }
        return result
    }

    /// 高亮 JSON，输出格式化文本与带颜色的 AttributedString
    public static func highlightJSON(_ text: String) -> (formatted: String, attributed: AttributedString)? {
        guard let formatted = formatJSON(text) else { return nil }

        let highlightTarget = formatted.count > maxHighlightLength ? String(formatted.prefix(maxHighlightLength)) : formatted
        let mattr = NSMutableAttributedString(
            string: highlightTarget,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
        )

        let totalRange = NSRange(location: 0, length: (highlightTarget as NSString).length)

        // 1. 键名高亮：系统蓝色 / 靛蓝
        if let regex = jsonKeyRegex {
            for match in regex.matches(in: highlightTarget, options: [], range: totalRange) {
                mattr.addAttribute(.foregroundColor, value: NSColor.systemIndigo, range: match.range)
            }
        }

        // 2. 字符串值：系统绿色
        if let regex = jsonStringValRegex {
            for match in regex.matches(in: highlightTarget, options: [], range: totalRange) where match.numberOfRanges > 1 {
                mattr.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: match.range(at: 1))
            }
        }

        // 3. 数值：系统橙色
        if let regex = jsonNumberValRegex {
            for match in regex.matches(in: highlightTarget, options: [], range: totalRange) where match.numberOfRanges > 1 {
                mattr.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: match.range(at: 1))
            }
        }

        // 4. 布尔：系统紫色
        if let regex = jsonBoolValRegex {
            for match in regex.matches(in: highlightTarget, options: [], range: totalRange) where match.numberOfRanges > 1 {
                mattr.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: match.range(at: 1))
            }
        }

        // 5. null：系统灰色
        if let regex = jsonNullValRegex {
            for match in regex.matches(in: highlightTarget, options: [], range: totalRange) where match.numberOfRanges > 1 {
                mattr.addAttribute(.foregroundColor, value: NSColor.systemGray, range: match.range(at: 1))
            }
        }

        var attr = AttributedString(mattr)
        if formatted.count > maxHighlightLength {
            var tail = AttributedString("\n... [已截断显示超长内容]")
            tail.foregroundColor = .secondary
            attr.append(tail)
        }

        return (formatted, attr)
    }

    // MARK: - 代码通用语法高亮

    /// 高亮通用编程语言代码（Swift/TS/JS/Python/Go/Rust/C/Java 等）
    public static func highlightCode(_ text: String) -> AttributedString {
        let highlightTarget = text.count > maxHighlightLength ? String(text.prefix(maxHighlightLength)) : text
        let mattr = NSMutableAttributedString(
            string: highlightTarget,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
        )

        let totalRange = NSRange(location: 0, length: (highlightTarget as NSString).length)

        // 1. 数值：橙色
        if let regex = codeNumberRegex {
            for match in regex.matches(in: highlightTarget, options: [], range: totalRange) {
                mattr.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: match.range)
            }
        }

        // 2. 关键字：紫色
        if let regex = codeKeywordRegex {
            for match in regex.matches(in: highlightTarget, options: [], range: totalRange) {
                mattr.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: match.range)
            }
        }

        // 3. 字符串：绿色（后应用，可覆盖关键字如 var 在字符串内）
        if let regex = codeStringRegex {
            for match in regex.matches(in: highlightTarget, options: [], range: totalRange) {
                mattr.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: match.range)
            }
        }

        // 4. 注释：灰色（最后应用，最高优先级覆盖）
        if let regex = codeCommentRegex {
            for match in regex.matches(in: highlightTarget, options: [], range: totalRange) {
                mattr.addAttribute(.foregroundColor, value: NSColor.systemGray, range: match.range)
            }
        }

        var attr = AttributedString(mattr)
        if text.count > maxHighlightLength {
            var tail = AttributedString("\n... [已截断显示超长代码]")
            tail.foregroundColor = .secondary
            attr.append(tail)
        }

        return attr
    }
}
