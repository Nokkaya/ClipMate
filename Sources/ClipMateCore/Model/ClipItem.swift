import Foundation

/// 一条剪贴板历史。
/// inlineData 存小对象（富文本 RTF/HTML、图片缩略图）；大对象走 BlobStore（blobName）。
public struct ClipItem: Identifiable, Equatable, Sendable {
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
    public let displayText: String

    public init(id: Int64, kind: ClipKind, plainText: String, sourceBundle: String, sourceName: String,
                byteSize: Int, createdAt: Date, lastUsedAt: Date, useCount: Int, pinned: Bool,
                tags: [String], title: String? = nil, meta: [String: String],
                inlineData: Data? = nil, blobName: String? = nil,
                displayText: String? = nil) {
        self.id = id
        self.kind = kind
        self.plainText = plainText
        self.sourceBundle = sourceBundle
        self.sourceName = sourceName
        self.byteSize = byteSize
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
        self.pinned = pinned
        self.tags = tags
        self.title = title
        self.meta = meta
        self.inlineData = inlineData
        self.blobName = blobName
        self.displayText = displayText ?? Self.computeDisplayText(kind: kind, plainText: plainText, meta: meta, title: title)
    }

    /// 预计算列表行的单行展示文本。
    public static func computeDisplayText(kind: ClipKind, plainText: String, meta: [String: String], title: String? = nil) -> String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        switch kind {
        case .image:
            return meta["display"] ?? "图片"
        case .file:
            if let display = meta["display"], !display.isEmpty { return display }
            let prefix = plainText.prefix(500)
            if let newlineIndex = prefix.firstIndex(where: { $0.isNewline }) {
                let first = String(prefix[..<newlineIndex])
                return first.isEmpty ? "文件" : first
            }
            return prefix.isEmpty ? "文件" : String(prefix)
        default:
            // 避免对整段大文本（如数 MB 的日志/JSON）进行全量 components(separatedBy:) 内存切片，
            // 仅在首部有限前缀内快速寻找首个非空行，O(1) 内存开销
            let prefix = plainText.prefix(2000)
            var start = prefix.startIndex
            while start < prefix.endIndex {
                let remainder = prefix[start...]
                let lineEnd = remainder.firstIndex(where: { $0.isNewline }) ?? prefix.endIndex
                let line = prefix[start..<lineEnd].trimmingCharacters(in: .whitespaces)
                if !line.isEmpty {
                    return String(line.prefix(300))
                }
                if lineEnd == prefix.endIndex { break }
                start = prefix.index(after: lineEnd)
            }
            return ""
        }
    }
}

/// 列表过滤维度（对应 UI 上的分类 chip）。
public enum FilterKind: String, CaseIterable {
    case all, text, image, file, link, snippet, pinned

    /// 片段收藏的标记标签。
    public static let snippetTag = "片段"

    public var title: String {
        switch self {
        case .all: return "全部"
        case .text: return "文本"
        case .image: return "图片"
        case .file: return "文件"
        case .link: return "链接"
        case .snippet: return "片段"
        case .pinned: return "已固定"
        }
    }

    /// 映射到 SQL 的 kind 过滤子句；nil 表示不过滤。
    var kindClause: String? {
        switch self {
        case .all, .pinned, .snippet: return nil
        case .text: return "kind IN ('text','richText','pdf')"
        case .image: return "kind = 'image'"
        case .file: return "kind = 'file'"
        case .link: return "kind = 'url'"
        }
    }

    /// 非 kind 维度的附加 SQL 子句。
    var extraClause: String? {
        switch self {
        case .snippet: return "tags LIKE '%\"\(FilterKind.snippetTag)\"%'"
        default: return nil
        }
    }
}
