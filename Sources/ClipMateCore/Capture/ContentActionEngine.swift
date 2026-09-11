import Foundation
import NaturalLanguage
import AppKit
import SwiftUI

/// 剪贴板内容一键处理动作类型
public enum ContentActionKind: String, Codable, Equatable, Sendable, CaseIterable {
    case fixLineBreaks = "fix_line_breaks"
    case deduplicateList = "deduplicate_list"
    case formatJSON = "format_json"
    case translate = "translate"

    public var icon: String {
        switch self {
        case .fixLineBreaks: return "text.alignleft"
        case .deduplicateList: return "square.stack.3d.down.right"
        case .formatJSON: return "curlybraces"
        case .translate: return "character.book.closed"
        }
    }

    public var isLocal: Bool {
        switch self {
        case .fixLineBreaks, .deduplicateList, .formatJSON:
            return true
        case .translate:
            return false
        }
    }
}

public enum ContentActionError: LocalizedError, Equatable, Sendable {
    case invalidJSON(String)
    case failure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let msg): return msg
        case .failure(let msg): return msg
        }
    }
}

/// 推荐的处理动作模型
public struct RecommendedAction: Equatable, Identifiable, Sendable {
    public var id: String { kind.rawValue }
    public let kind: ContentActionKind
    public let title: String
    public let badge: String?
    public let icon: String
    public let isLocal: Bool
    public let targetLanguage: String?

    public init(kind: ContentActionKind, title: String, badge: String? = nil, icon: String? = nil,
                isLocal: Bool? = nil, targetLanguage: String? = nil) {
        self.kind = kind
        self.title = title
        self.badge = badge
        self.icon = icon ?? kind.icon
        self.isLocal = isLocal ?? kind.isLocal
        self.targetLanguage = targetLanguage
    }
}

/// 内容动作分析与处理引擎：提供本地优先、零门槛的就地动作推荐与纯算法处理。
public enum ContentActionEngine {

    // MARK: - 动作推荐与识别

    /// 根据所选内容推荐最相关的一个主要动作；没有明确适用动作时返回 nil。
    public static func recommendAction(
        for text: String,
        kind: ClipKind = .text,
        tags: [String] = [],
        appLanguage: AppLanguage = .system
    ) -> RecommendedAction? {
        guard kind != .image, kind != .file else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. JSON 格式化与诊断优先
        if shouldRecommendJSON(trimmed: trimmed, tags: tags) {
            let isZh = (appLanguage == .zhHans || (appLanguage == .system && Locale.preferredLanguages.first?.hasPrefix("zh") == true))
            return RecommendedAction(
                kind: .formatJSON,
                title: isZh ? "格式化 JSON" : "Format JSON",
                badge: nil,
                icon: "curlybraces",
                isLocal: true
            )
        }

        // 2. 名单去重：多行且存在完全重复项
        let dedupeCheck = checkDuplicates(text)
        if dedupeCheck.removedCount > 0 {
            let isZh = (appLanguage == .zhHans || (appLanguage == .system && Locale.preferredLanguages.first?.hasPrefix("zh") == true))
            let badge = isZh ? "发现 \(dedupeCheck.removedCount) 处重复" : "\(dedupeCheck.removedCount) duplicates"
            return RecommendedAction(
                kind: .deduplicateList,
                title: isZh ? "名单去重" : "Deduplicate",
                badge: badge,
                icon: "square.stack.3d.down.right",
                isLocal: true
            )
        }

        // 3. 修复异常断行：普通文本中被错误截断的换行
        if shouldRecommendFixLineBreaks(text, tags: tags) {
            let isZh = (appLanguage == .zhHans || (appLanguage == .system && Locale.preferredLanguages.first?.hasPrefix("zh") == true))
            return RecommendedAction(
                kind: .fixLineBreaks,
                title: isZh ? "修复断行" : "Fix Line Breaks",
                badge: nil,
                icon: "text.alignleft",
                isLocal: true
            )
        }

        // 4. 快捷翻译：识别不同于当前界面/系统的外语段落
        if let translateAction = checkTranslateRecommendation(text: trimmed, appLanguage: appLanguage, tags: tags) {
            return translateAction
        }

        return nil
    }

    // MARK: - 1. 修复异常断行算法

    /// 将从 PDF、OCR 等来源复制的断行文本重新连接，保留双换行代表的段落边界。
    public static func fixLineBreaks(_ text: String) -> String {
        // 统一换行符
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
                             .replacingOccurrences(of: "\r", with: "\n")

        // 按两个或以上换行切分段落
        let paragraphRegex = try? NSRegularExpression(pattern: #"\n\s*\n+"#)
        let totalRange = NSRange(location: 0, length: (normalized as NSString).length)
        var paragraphs: [String] = []

        if let paragraphRegex {
            var lastIndex = 0
            let matches = paragraphRegex.matches(in: normalized, options: [], range: totalRange)
            for match in matches {
                let range = NSRange(location: lastIndex, length: match.range.location - lastIndex)
                if let swiftRange = Range(range, in: normalized) {
                    paragraphs.append(String(normalized[swiftRange]))
                }
                lastIndex = match.range.location + match.range.length
            }
            if lastIndex < totalRange.length {
                let range = NSRange(location: lastIndex, length: totalRange.length - lastIndex)
                if let swiftRange = Range(range, in: normalized) {
                    paragraphs.append(String(normalized[swiftRange]))
                }
            }
        } else {
            paragraphs = normalized.components(separatedBy: "\n\n")
        }

        var processedParagraphs: [String] = []

        for p in paragraphs {
            let lines = p.components(separatedBy: "\n")
                         .map { $0.trimmingCharacters(in: .whitespaces) }
                         .filter { !$0.isEmpty }

            guard !lines.isEmpty else { continue }
            if lines.count == 1 {
                processedParagraphs.append(lines[0])
                continue
            }

            var merged = ""
            for i in 0..<lines.count {
                let current = lines[i]
                if merged.isEmpty {
                    merged = current
                    continue
                }

                // 处理上一行行尾连接
                if merged.hasSuffix("-") && !merged.hasSuffix(" -") {
                    // 英文连字符换行：如 "multi-\nplatform" -> "multiplatform"
                    let lastChar = merged.dropLast().last
                    let firstChar = current.first
                    if let l = lastChar, let f = firstChar, l.isLetter && f.isLetter {
                        merged = String(merged.dropLast()) + current
                        continue
                    }
                }

                let lastChar = merged.last ?? " "
                let nextChar = current.first ?? " "

                if isCJK(lastChar) && isCJK(nextChar) {
                    // 中日韩字符相邻直接拼接，不留空格
                    merged += current
                } else if isCJK(lastChar) || isCJK(nextChar) {
                    // 中英文混合，保持单个空格排版
                    merged += " " + current
                } else {
                    // 英文/数字之间插入一个空格
                    merged += " " + current
                }
            }
            processedParagraphs.append(merged)
        }

        return processedParagraphs.joined(separator: "\n\n")
    }

    private static func isCJK(_ char: Character) -> Bool {
        for scalar in char.unicodeScalars {
            let val = scalar.value
            // CJK 统一表意文字、扩充集、日韩字符与 CJK 全角标点符号（，。！？：；等）
            if (0x4E00...0x9FFF).contains(val) ||
               (0x3400...0x4DBF).contains(val) ||
               (0x20000...0x2A6DF).contains(val) ||
               (0x3000...0x303F).contains(val) ||
               (0xFF00...0xFFEF).contains(val) ||
               (0x3040...0x309F).contains(val) ||
               (0x30A0...0x30FF).contains(val) ||
               (0xAC00...0xD7AF).contains(val) {
                return true
            }
        }
        return false
    }

    private static func shouldRecommendFixLineBreaks(_ text: String, tags: [String]) -> Bool {
        // 排除代码、表格、已标记为代码的文本
        if tags.contains("代码") || tags.contains("JSON") || AutoTagger.isCode(text) {
            return false
        }

        let lines = text.components(separatedBy: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
        guard lines.count >= 3 else { return false }

        // 检查表格特征（如 Markdown 表格行 | ... |）
        let tableLineCount = lines.filter { $0.hasPrefix("|") && $0.hasSuffix("|") }.count
        if tableLineCount >= 2 { return false }

        // 检查列表特征（项目符号、序号列表）
        let listPrefixes = ["- ", "* ", "• ", "+ ", "[ ] ", "[x] "]
        let listLineCount = lines.filter { line in
            listPrefixes.contains(where: { line.hasPrefix($0) }) ||
            (line.range(of: #"^\d+[\.\、\)]\s+"#, options: .regularExpression) != nil)
        }.count
        if Double(listLineCount) / Double(lines.count) >= 0.4 {
            return false
        }

        // 检查断行是否发生在无标点的行尾（PDF 换行特征）
        let terminalPunctuation: Set<Character> = [".", "!", "?", "。", "！", "？", ";", "；", ":", "："]
        var brokenCount = 0

        for i in 0..<(lines.count - 1) {
            let line = lines[i]
            if let last = line.last, !terminalPunctuation.contains(last) {
                brokenCount += 1
            }
        }

        // 如果超过半数换行在无终结标点处发生，且平均行长不太短（排除诗歌），则推荐修复断行
        let avgLength = lines.map(\.count).reduce(0, +) / lines.count
        if brokenCount >= 2 && avgLength >= 12 {
            return true
        }

        return false
    }

    // MARK: - 2. 名单去重算法

    /// 移除文本中的完全重复行，保持原有首现顺序。
    public static func deduplicateList(_ text: String) -> (result: String, removedCount: Int) {
        let lines = text.components(separatedBy: "\n")
        var seen = Set<String>()
        var unique: [String] = []
        var removed = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                // 空白行保留原样，不计入去重
                unique.append(line)
                continue
            }
            if seen.contains(line) {
                removed += 1
            } else {
                seen.insert(line)
                unique.append(line)
            }
        }

        return (unique.joined(separator: "\n"), removed)
    }

    private static func checkDuplicates(_ text: String) -> (hasDuplicates: Bool, removedCount: Int) {
        let lines = text.components(separatedBy: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
        guard lines.count >= 2 else { return (false, 0) }

        var seen = Set<String>()
        var duplicates = 0
        for line in lines {
            if seen.contains(line) {
                duplicates += 1
            } else {
                seen.insert(line)
            }
        }
        return (duplicates > 0, duplicates)
    }

    // MARK: - 3. JSON 格式化与语法诊断

    /// 格式化 JSON：合法时返回缩进美化文本；非法时返回错误诊断原因。
    public static func formatJSON(_ text: String) -> Result<String, ContentActionError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
              trimmed.hasSuffix("}") || trimmed.hasSuffix("]") else {
            return .failure(.invalidJSON("内容非标准 JSON 对象或数组"))
        }

        guard let data = trimmed.data(using: .utf8) else {
            return .failure(.failure("无法以 UTF-8 编码读取 JSON 数据"))
        }

        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            let formattedData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            if let formattedString = String(data: formattedData, encoding: .utf8) {
                return .success(formattedString)
            } else {
                return .failure(.failure("格式化数据生成失败"))
            }
        } catch {
            let nsError = error as NSError
            var reason = error.localizedDescription
            if let debugDesc = nsError.userInfo["NSDebugDescription"] as? String {
                reason = debugDesc
            }
            return .failure(.invalidJSON("JSON 语法错误：\(reason)"))
        }
    }

    private static func shouldRecommendJSON(trimmed: String, tags: [String]) -> Bool {
        if tags.contains("JSON") { return true }
        guard (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
              (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) else {
            return false
        }
        guard trimmed.count >= 4 else { return false }

        // 如果只有一行，或者行数不多且缺乏缩进，推荐格式化
        if !trimmed.contains("\n") { return true }

        // 尝试测试解析，若能解析且未缩进（不含两个以上空格缩进），也推荐
        if let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil {
            if !trimmed.contains("\n  ") && !trimmed.contains("\n\t") {
                return true
            }
        } else {
            // 语法错误的 JSON 也推荐（让用户点击后看到具体报错）
            return true
        }
        return false
    }

    // MARK: - 4. 快捷翻译识别（基于 macOS 原生 NaturalLanguage）

    private static func checkTranslateRecommendation(
        text: String,
        appLanguage: AppLanguage,
        tags: [String]
    ) -> RecommendedAction? {
        // 排除代码、JSON
        if tags.contains("代码") || tags.contains("JSON") || AutoTagger.isCode(text) {
            return nil
        }
        guard text.count >= 12 else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return nil }

        let isAppChinese = (appLanguage == .zhHans || (appLanguage == .system && Locale.preferredLanguages.first?.hasPrefix("zh") == true))

        if isAppChinese {
            // 中文环境下，如果是外语（英语、日语、韩语、法语、德语、俄语、西班牙语等）
            if dominant != .simplifiedChinese && dominant != .traditionalChinese && dominant != .undetermined {
                let langName = languageDisplayName(dominant, inChinese: true)
                return RecommendedAction(
                    kind: .translate,
                    title: "翻译为中文",
                    badge: langName,
                    icon: "character.book.closed",
                    isLocal: false,
                    targetLanguage: "zh-Hans"
                )
            }
        } else {
            // 英文环境下，如果是中文、日文等
            if dominant != .english && dominant != .undetermined {
                let langName = languageDisplayName(dominant, inChinese: false)
                return RecommendedAction(
                    kind: .translate,
                    title: "Translate to English",
                    badge: langName,
                    icon: "character.book.closed",
                    isLocal: false,
                    targetLanguage: "en"
                )
            }
        }
        return nil
    }

    public static func languageDisplayName(_ lang: NLLanguage, inChinese: Bool) -> String {
        switch lang {
        case .english: return inChinese ? "英语" : "English"
        case .simplifiedChinese: return inChinese ? "简体中文" : "Chinese"
        case .traditionalChinese: return inChinese ? "繁体中文" : "Trad. Chinese"
        case .japanese: return inChinese ? "日语" : "Japanese"
        case .korean: return inChinese ? "韩语" : "Korean"
        case .french: return inChinese ? "法语" : "French"
        case .german: return inChinese ? "德语" : "German"
        case .spanish: return inChinese ? "西班牙语" : "Spanish"
        case .russian: return inChinese ? "俄语" : "Russian"
        case .italian: return inChinese ? "意大利语" : "Italian"
        default: return inChinese ? "外语" : "Foreign"
        }
    }
}
