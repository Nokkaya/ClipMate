import Foundation

/// 智能标题生成器：对无显式标题的文本、代码、JSON、Markdown、命令行指令及 OCR 结果，
/// 在极低时间预算内（<= 1024 字符探测）提取高度结构化、具有辨识度的单行标题。
public enum SmartTitleGenerator {

    /// 为指定文本提取智能标题；若无高辨识度结构则返回 nil。
    public static func generate(for text: String, kind: ClipKind) -> String? {
        guard kind == .text || kind == .richText else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. 色值识别优先
        if let hex = AutoTagger.detectColor(in: trimmed) {
            if let name = AutoTagger.friendlyColorName(for: hex) {
                return "🎨 \(hex) · \(name)"
            }
            return "🎨 \(hex)"
        }

        // 截取前 1024 字符作为轻量扫描窗口
        let sample = String(trimmed.prefix(1024))

        // 2. Markdown 标题提取（# / ## / ###）
        if let mdTitle = extractMarkdownTitle(from: sample) {
            return mdTitle
        }

        // 3. 命令行指令识别（git/docker/npm/curl...）
        if let cliTitle = extractCLICommand(from: sample) {
            return cliTitle
        }

        // 4. SQL 语句识别
        if let sqlTitle = extractSQL(from: sample) {
            return sqlTitle
        }

        // 5. 代码函数 / 类 / 结构体 / 接口定义提取
        if let codeTitle = extractCodeSignature(from: sample) {
            return codeTitle
        }

        // 6. JSON 顶层关键字段提取
        if let jsonTitle = extractJSONSummary(from: sample) {
            return jsonTitle
        }

        return nil
    }

    // MARK: - 私有提取逻辑

    private static func extractMarkdownTitle(from sample: String) -> String? {
        let lines = sample.split(whereSeparator: \.isNewline)
        for rawLine in lines.prefix(5) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("# ") {
                let title = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { return truncate(title, max: 45) }
            } else if line.hasPrefix("## ") {
                let title = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { return truncate(title, max: 45) }
            } else if line.hasPrefix("### ") {
                let title = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { return truncate(title, max: 45) }
            }
        }
        return nil
    }

    private static func extractCLICommand(from sample: String) -> String? {
        let firstLine = sample.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !firstLine.isEmpty else { return nil }

        let prefixes = ["git ", "docker ", "kubectl ", "brew ", "npm ", "yarn ", "pnpm ",
                        "cargo ", "swift ", "curl ", "ssh ", "make "]
        for prefix in prefixes {
            if firstLine.hasPrefix(prefix) || firstLine.hasPrefix("$ " + prefix) {
                let clean = firstLine.hasPrefix("$ ") ? String(firstLine.dropFirst(2)) : firstLine
                return "⚡️ " + truncate(clean, max: 45)
            }
        }
        return nil
    }

    private static func extractSQL(from sample: String) -> String? {
        let upper = sample.uppercased()
        let sqlKeywords = ["SELECT ", "INSERT INTO ", "UPDATE ", "DELETE FROM ", "CREATE TABLE ", "ALTER TABLE "]
        for kw in sqlKeywords {
            if let range = upper.range(of: kw) {
                let start = range.lowerBound
                let remaining = sample[start...]
                let line = remaining.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
                let cleaned = line.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty {
                    return "🗄 " + truncate(cleaned, max: 45)
                }
            }
        }
        return nil
    }

    private static func extractCodeSignature(from sample: String) -> String? {
        let lines = sample.split(whereSeparator: \.isNewline)
        let patterns = [
            // Swift / Go / JS / Python / Rust / Java
            #"^\s*(?:(?:public|private|fileprivate|internal|open|static|final|override|async|export|default|pub)\s+)*(?:func|def|fn|function)\s+([A-Za-z0-9_]+(?:\s*\([^)]*\))?)"#,
            #"^\s*(?:(?:public|private|internal|open|final|abstract|export)\s+)*(?:class|struct|interface|enum|protocol|type)\s+([A-Za-z0-9_]+)"#,
        ]

        for rawLine in lines.prefix(15) {
            let line = String(rawLine)
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                    let fullMatched = (line as NSString).substring(with: match.range).trimmingCharacters(in: .whitespaces)
                    return "💻 " + truncate(fullMatched, max: 45)
                }
            }
        }
        return nil
    }

    private static func extractJSONSummary(from sample: String) -> String? {
        guard sample.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") else { return nil }
        let keyPatterns = ["action", "event", "name", "title", "type", "id", "command"]
        for key in keyPatterns {
            let pattern = "\"\(key)\"\\s*:\\s*\"([^\"]{1,30})\""
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: sample, range: NSRange(sample.startIndex..., in: sample)),
               match.numberOfRanges >= 2 {
                let valRange = match.range(at: 1)
                let val = (sample as NSString).substring(with: valRange)
                return "JSON · \(key): \"\(val)\""
            }
        }
        return nil
    }

    private static func truncate(_ text: String, max: Int) -> String {
        if text.count <= max { return text }
        return String(text.prefix(max)) + "…"
    }
}
