import Foundation
import SwiftUI

/// 搜索关键词高亮工具：基于 macOS 原生 AttributedString 构建，支持大小写不敏感匹配。
public enum TextHighlighter {

    /// 对目标文本进行关键词高亮，返回 AttributedString。
    public static func highlight(
        text: String,
        query: String,
        highlightColor: Color = Color.yellow.opacity(0.35),
        bold: Bool = true
    ) -> AttributedString {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var attributed = AttributedString(text)
        guard !trimmedQuery.isEmpty, !text.isEmpty else { return attributed }

        var searchStartIndex = text.startIndex
        while searchStartIndex < text.endIndex,
              let range = text.range(of: trimmedQuery, options: .caseInsensitive, range: searchStartIndex..<text.endIndex) {
            if let attrRange = Range(range, in: attributed) {
                attributed[attrRange].backgroundColor = highlightColor
                if bold {
                    attributed[attrRange].inlinePresentationIntent = .stronglyEmphasized
                }
            }
            searchStartIndex = range.upperBound
        }
        return attributed
    }
}
