import Foundation

/// 剪贴条目类型。url 是 text 的语义子类，用于分类过滤与 UI 呈现。
public enum ClipKind: String, CaseIterable, Codable, Sendable {
    case text
    case url
    case richText
    case image
    case file
    case pdf

    public var title: String {
        switch self {
        case .text: return "文本"
        case .url: return "链接"
        case .richText: return "富文本"
        case .image: return "图片"
        case .file: return "文件"
        case .pdf: return "PDF"
        }
    }
}
