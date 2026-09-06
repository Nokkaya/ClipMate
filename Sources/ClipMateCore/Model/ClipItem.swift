import Foundation

/// 一条剪贴板历史。
/// inlineData 存小对象（富文本 RTF/HTML、图片缩略图）；大对象走 BlobStore（blobName）。
public struct ClipItem: Identifiable, Equatable {
    public let id: Int64
    public var kind: ClipKind
    public var plainText: String
    public var sourceBundle: String
    public var sourceName: String
    public var byteSize: Int
    public var createdAt: Date
    public var lastUsedAt: Date
    public var useCount: Int
    public var pinned: Bool
    public var tags: [String]
    public var title: String?
    public var meta: [String: String]
    public var inlineData: Data?
    public var blobName: String?

    /// 列表行的单行展示文本。
    public var displayText: String {
        switch kind {
        case .image:
            return meta["display"] ?? "图片"
        case .file:
            return meta["display"] ?? (plainText.components(separatedBy: "\n").first ?? "文件")
        default:
            let line = plainText
                .components(separatedBy: .newlines)
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
            return String(line.prefix(300))
        }
    }
}

/// 列表过滤维度（对应 UI 上的分类 chip）。
public enum FilterKind: String, CaseIterable {
    case all, text, image, file, link, pinned

    public var title: String {
        switch self {
        case .all: return "全部"
        case .text: return "文本"
        case .image: return "图片"
        case .file: return "文件"
        case .link: return "链接"
        case .pinned: return "已固定"
        }
    }

    /// 映射到 SQL 的 kind 过滤子句；nil 表示不过滤。
    var kindClause: String? {
        switch self {
        case .all, .pinned: return nil
        case .text: return "kind IN ('text','richText')"
        case .image: return "kind = 'image'"
        case .file: return "kind = 'file'"
        case .link: return "kind = 'url'"
        }
    }
}
