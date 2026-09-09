import Foundation
import CryptoKit

/// 时间范围过滤（情境回忆："我记得是昨天复制的"）。
public enum TimeFilter: String, CaseIterable, Identifiable, Sendable {
    case all, today, yesterday, last3Days, thisWeek, thisMonth

    public var id: String { rawValue }

    /// 起始时间；nil 表示不限。
    public var since: Date? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .all: return nil
        case .today: return cal.startOfDay(for: now)
        case .yesterday: return cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now))
        case .last3Days: return cal.date(byAdding: .day, value: -2, to: cal.startOfDay(for: now))
        case .thisWeek: return cal.dateInterval(of: .weekOfYear, for: now)?.start
        case .thisMonth: return cal.dateInterval(of: .month, for: now)?.start
        }
    }

    /// 结束时间（仅"昨天"需要上界）；nil 表示不限。
    public var until: Date? {
        switch self {
        case .yesterday: return Calendar.current.startOfDay(for: Date())
        default: return nil
        }
    }
}

/// 情境过滤：来源应用 + 时间范围。
public struct ContextFilter: Equatable, Sendable {
    public var sourceBundle: String?
    public var since: Date?
    public var until: Date?

    public init(sourceBundle: String? = nil, since: Date? = nil, until: Date? = nil) {
        self.sourceBundle = sourceBundle
        self.since = since
        self.until = until
    }

    public var isActive: Bool {
        sourceBundle != nil || since != nil || until != nil
    }

    public init(time: TimeFilter, sourceBundle: String?) {
        self.sourceBundle = sourceBundle
        self.since = time.since
        self.until = time.until
    }
}

/// 来源应用聚合项（供筛选菜单展示）。
public struct ClipSource: Identifiable, Equatable, Sendable {
    public let bundle: String
    public let name: String
    public let count: Int
    public var id: String { bundle }

    public init(bundle: String, name: String, count: Int) {
        self.bundle = bundle
        self.name = name
        self.count = count
    }
}

/// 历史存储：SQLite（去重合并、FTS5/LIKE 检索、语义向量混合排序、固定、保留策略、大对象落盘、导入导出）。
public final class ClipStore {
    private let db: Database
    private let blobs: BlobStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// 语义检索的向量生成器（文本 → 向量二进制）；nil 表示未启用。
    /// 由 `providerLock` 保护，支持运行中开关语义检索。
    private var _embeddingProvider: ((String) -> Data?)?
    private let providerLock = NSLock()
    /// 向量缓存：id → float 数组（懒加载，写操作后失效）。
    private let cacheLock = NSLock()
    private var embeddingCache: [Int64: [Float]]?

    /// 当前向量生成器（线程安全读取）。
    public var embeddingProvider: ((String) -> Data?)? {
        providerLock.lock()
        defer { providerLock.unlock() }
        return _embeddingProvider
    }

    /// 运行中切换语义检索：替换生成器并失效向量缓存。
    public func setEmbeddingProvider(_ provider: ((String) -> Data?)?) {
        providerLock.lock()
        _embeddingProvider = provider
        providerLock.unlock()
        resetEmbeddingCache()
    }

    public func invalidateEmbeddingCache() {
        resetEmbeddingCache()
    }

    private func resetEmbeddingCache() {
        cacheLock.lock()
        embeddingCache = nil
        cacheLock.unlock()
    }

    public init(database: Database,
                blobStore: BlobStore,
                embeddingProvider: ((String) -> Data?)? = nil) throws {
        self.db = database
        self.blobs = blobStore
        self._embeddingProvider = embeddingProvider
        try Migrations.run(database)
    }

    public var supportsFullTextSearch: Bool { db.hasFTS5 }

    /// 当前已建立向量的条目数。
    public var embeddedCount: Int { embeddingVectors().count }

    // MARK: - 列与投影

    private static let listColumns = "id, kind, plain_text, source_bundle, source_name, byte_size, created_at, last_used_at, use_count, pinned, title, tags, meta, blob_name"
    private static let ftsListColumns = "clip.id, clip.kind, clip.plain_text, clip.source_bundle, clip.source_name, clip.byte_size, clip.created_at, clip.last_used_at, clip.use_count, clip.pinned, clip.title, clip.tags, clip.meta, clip.blob_name"

    private enum Col {
        static let id: Int32 = 0
        static let kind: Int32 = 1
        static let plainText: Int32 = 2
        static let sourceBundle: Int32 = 3
        static let sourceName: Int32 = 4
        static let byteSize: Int32 = 5
        static let createdAt: Int32 = 6
        static let lastUsedAt: Int32 = 7
        static let useCount: Int32 = 8
        static let pinned: Int32 = 9
        static let title: Int32 = 10
        static let tags: Int32 = 11
        static let meta: Int32 = 12
        static let blobName: Int32 = 13
        static let inlineData: Int32 = 14
    }

    // MARK: - 采集入库（含去重合并）

    /// 相同内容再次复制时上浮并累加 use_count，不产生新行。createdAt 供导入还原原始时间。
    @discardableResult
    public func capture(kind: ClipKind,
                        plainText: String,
                        sourceBundle: String,
                        sourceName: String,
                        tags: [String] = [],
                        title: String? = nil,
                        inlineData: Data? = nil,
                        imageOriginal: Data? = nil,
                        meta: [String: String] = [:],
                        createdAt: Date? = nil) throws -> (item: ClipItem, isNew: Bool) {
        var meta = meta
        var blobName: String?
        if kind == .image || kind == .pdf, let original = imageOriginal {
            blobName = try blobs.store(original)
            meta["bytes"] = String(original.count)
        }

        let content = (kind == .image || kind == .pdf) ? (imageOriginal ?? Data()) : Data(plainText.utf8)
        let hashData = Data(SHA256.hash(data: Data(kind.rawValue.utf8) + content))
        let timestamp = (createdAt ?? Date()).timeIntervalSince1970
        let now = Date().timeIntervalSince1970

        // 号码归一化键：同一号码的不同分隔符写法（138 1234 5678 / 138-1234-5678）归并为同一条
        let numberKey = NumberRecognizer.normalize(plainText)

        let dup = try db.prepare("SELECT id FROM clip WHERE content_hash = ? LIMIT 1")
        dup.bind([.blob(hashData)])
        var existingID: Int64? = dup.step() ? dup.columnInt(0) : nil

        if existingID == nil, let key = numberKey {
            let dupNumber = try db.prepare("SELECT id FROM clip WHERE num_key = ? LIMIT 1")
            dupNumber.bind([.text(key)])
            existingID = dupNumber.step() ? dupNumber.columnInt(0) : nil
        }

        if let id = existingID {
            // 合并最新自动标签：旧条目可能在标签规则升级前入库，重新复制时补齐
            var mergedTags = tags
            if !tags.isEmpty, let existing = item(id: id) {
                mergedTags = existing.tags + tags.filter { !existing.tags.contains($0) }
            }
            let update = try db.prepare("""
                UPDATE clip SET kind = ?, plain_text = ?, source_bundle = ?, source_name = ?,
                    byte_size = ?, created_at = ?, last_used_at = ?, use_count = use_count + 1,
                    inline_data = ?, blob_name = ?, meta = ?, num_key = ?, tags = ?
                WHERE id = ?
                """)
            update.bind([
                .text(kind.rawValue), .text(plainText), .text(sourceBundle), .text(sourceName),
                .int(Int64(content.count)), .double(timestamp), .double(now),
                .blob(inlineData), .text(blobName), .text(json(meta)), .text(numberKey),
                .text(json(mergedTags)),
                .int(id),
            ])
            try update.run()
            guard let item = item(id: id) else { throw StoreError.sql("去重更新后读取失败") }
            return (item, false)
        }

        let insert = try db.prepare("""
            INSERT INTO clip (kind, plain_text, source_bundle, source_name, content_hash, byte_size,
                created_at, last_used_at, use_count, pinned, title, tags, meta, inline_data, blob_name, num_key)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 0, ?, ?, ?, ?, ?, ?)
            """)
        insert.bind([
            .text(kind.rawValue), .text(plainText), .text(sourceBundle), .text(sourceName),
            .blob(hashData), .int(Int64(content.count)), .double(timestamp), .double(timestamp),
            .text(title),
            .text(json(tags)), .text(json(meta)), .blob(inlineData), .text(blobName), .text(numberKey),
        ])
        try insert.run()
        guard let item = item(id: db.lastInsertRowID) else { throw StoreError.sql("插入后读取失败") }
        return (item, true)
    }


    // MARK: - 查询

    /// 检索：文本路径（FTS5 前缀/LIKE）+ 语义向量路径，RRF 混合排序。
    /// 拉丁文查询走 FTS5，含 CJK 的查询走 LIKE（系统 FTS5 默认分词器不切中文）。
    public func search(query: String, filter: FilterKind = .all, snippetGroup: String? = nil,
                       context: ContextFilter = ContextFilter(), limit: Int = 300) -> [ClipItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let textResults = try textSearch(trimmed, filter: filter, snippetGroup: snippetGroup, context: context, limit: limit)

            // 语义检索只吃普通关键词（结构化条件如 #11 / app:微信 不参与向量召回）
            let semanticQuery = SearchQueryParser.parse(trimmed).terms.joined(separator: " ")
            guard !semanticQuery.isEmpty, !trimmed.hasPrefix("/"), let provider = embeddingProvider else { return textResults }

            let vectors = embeddingVectors()
            guard !vectors.isEmpty else { return textResults }

            // 语义召回：余弦相似度，取 top limit
            guard let queryData = provider(semanticQuery),
                  let queryVector = Self.vectors(from: queryData) else { return textResults }
            var candidates: [(id: Int64, score: Float)] = []
            for (id, vector) in vectors where vector.count == queryVector.count {
                let similarity = Self.cosine(queryVector, vector)
                if similarity >= 0.28 {
                    candidates.append((id, similarity))
                }
            }
            guard !candidates.isEmpty else { return textResults }
            candidates.sort { $0.score > $1.score }
            let vectorRankIDs = candidates.prefix(limit).map(\.id)

            // RRF 融合两路排名
            var scores: [Int64: Double] = [:]
            for (rank, item) in textResults.enumerated() {
                scores[item.id, default: 0] += 1.0 / Double(60 + rank)
            }
            for (rank, id) in vectorRankIDs.enumerated() {
                scores[id, default: 0] += 1.0 / Double(60 + rank)
            }

            // 仅对缺失条目做一次批量取回（替代逐条 item(id:)），并应用类别过滤
            var itemMap = Dictionary(uniqueKeysWithValues: textResults.map { ($0.id, $0) })
            let missing = vectorRankIDs.filter { itemMap[$0] == nil }
            for fetched in items(ids: missing) where matchesFilter(fetched, filter, snippetGroup: snippetGroup, context: context) {
                itemMap[fetched.id] = fetched
            }
            return scores
                .compactMap { id, score -> (ClipItem, Double)? in
                    itemMap[id].map { ($0, score + ($0.pinned ? 0.002 : 0)) }
                }
                .sorted { $0.1 > $1.1 }
                .prefix(limit)
                .map(\.0)
        } catch {
            return []
        }
    }

    private func textSearch(_ trimmed: String, filter: FilterKind, snippetGroup: String? = nil,
                            context: ContextFilter = ContextFilter(), limit: Int) throws -> [ClipItem] {
        // 短语代码快速匹配与文本扩展（/xxx 或直接 /）
        if trimmed.hasPrefix("/") {
            let rawCode = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            let code = rawCode.hasPrefix("/") ? String(rawCode.dropFirst()) : rawCode
            var clauses: [String] = []
            var args: [SQLValue] = []

            if code.isEmpty {
                // 用户只输入了 "/"，直接召回所有片段，优先展示含短语代码的条目
                clauses.append("(tags LIKE ? OR meta LIKE ?)")
                args.append(.text("%\"" + FilterKind.snippetTag + "\"%"))
                args.append(.text("%\"snippet\":%"))
            } else {
                clauses.append("(meta LIKE ? OR meta LIKE ? OR plain_text LIKE ? OR title LIKE ?)")
                args.append(.text("%\"snippet_shortcode\":\"%" + code + "%\"%"))
                args.append(.text("%\"snippet_shortcode\":\"/%" + code + "%\"%"))
                args.append(.text("%" + code + "%"))
                args.append(.text("%" + code + "%"))
            }

            if let clause = filter.kindClause { clauses.append(clause) }
            if let extra = filter.extraClause { clauses.append(extra) }
            if filter == .pinned { clauses.append("pinned = 1") }
            if filter == .snippet, let group = snippetGroup, !group.isEmpty {
                clauses.append("meta LIKE ?")
                args.append(.text("%\"snippet_group\":\"\(group)\"%"))
            }
            let snippetCtx = contextClauses(context, alias: "")
            clauses.append(contentsOf: snippetCtx.clauses)
            args.append(contentsOf: snippetCtx.args)

            var sql = "SELECT \(Self.listColumns) FROM clip"
            if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }

            if code.isEmpty {
                sql += """
                 ORDER BY
                  CASE
                    WHEN meta LIKE '%"snippet_shortcode"%' THEN 0
                    ELSE 1
                  END,
                  pinned DESC,
                  last_used_at DESC
                 LIMIT ?
                """
                args.append(.int(Int64(limit)))
            } else {
                let exact1 = "%\"snippet_shortcode\":\"" + code + "\"%"
                let exact2 = "%\"snippet_shortcode\":\"/" + code + "\"%"
                let prefix1 = "%\"snippet_shortcode\":\"" + code + "%\"%"
                let prefix2 = "%\"snippet_shortcode\":\"/" + code + "%\"%"
                let snippetTagPattern = "%\"" + FilterKind.snippetTag + "\"%"
                sql += """
                 ORDER BY
                  CASE
                    WHEN (meta LIKE ? OR meta LIKE ?) THEN 0
                    WHEN (meta LIKE ? OR meta LIKE ?) THEN 1
                    WHEN (tags LIKE ? OR meta LIKE '%"snippet":%') THEN 2
                    ELSE 3
                  END,
                  pinned DESC,
                  last_used_at DESC
                 LIMIT ?
                """
                args.append(.text(exact1))
                args.append(.text(exact2))
                args.append(.text(prefix1))
                args.append(.text(prefix2))
                args.append(.text(snippetTagPattern))
                args.append(.int(Int64(limit)))
            }

            let statement = try db.prepare(sql)
            statement.bind(args)
            return collect(statement)
        }

        // 检索语法解析：terms 为普通关键词，其余为结构化过滤条件
        let parsed = SearchQueryParser.parse(trimmed)
        let terms = parsed.terms.joined(separator: " ")

        if !terms.isEmpty, db.hasFTS5, !containsCJK(terms), !parsed.hasFilters {
            let ftsQuery = ftsExpression(for: terms)
            var sql = "SELECT \(Self.ftsListColumns) FROM clip, clip_fts WHERE clip_fts MATCH ? AND clip.id = clip_fts.rowid"
            if let clause = filter.kindClause { sql += " AND \(clause)" }
            if let extra = filter.extraClause { sql += " AND \(extra)" }
            if filter == .pinned { sql += " AND clip.pinned = 1" }
            var bindArgs: [SQLValue] = [.text(ftsQuery)]
            if filter == .snippet, let group = snippetGroup, !group.isEmpty {
                sql += " AND clip.meta LIKE ?"
                bindArgs.append(.text("%\"snippet_group\":\"\(group)\"%"))
            }
            let ftsCtx = contextClauses(context, alias: "clip.")
            for clause in ftsCtx.clauses { sql += " AND \(clause)" }
            bindArgs.append(contentsOf: ftsCtx.args)
            sql += " ORDER BY clip.pinned DESC, rank LIMIT ?"
            bindArgs.append(.int(Int64(limit)))
            let statement = try db.prepare(sql)
            statement.bind(bindArgs)
            return collect(statement)
        }

        var clauses: [String] = []
        var args: [SQLValue] = []
        if !terms.isEmpty {
            clauses.append("(plain_text LIKE ? OR title LIKE ? OR meta LIKE ?)")
            args.append(.text("%\(terms)%"))
            args.append(.text("%\(terms)%"))
            args.append(.text("%\"snippet_shortcode\":\"%\(terms)%\"%"))
        }
        let syntax = structuredClauses(parsed, alias: "")
        clauses.append(contentsOf: syntax.clauses)
        args.append(contentsOf: syntax.args)
        if let clause = filter.kindClause { clauses.append(clause) }
        if let extra = filter.extraClause { clauses.append(extra) }
        if filter == .pinned { clauses.append("pinned = 1") }
        if filter == .snippet, let group = snippetGroup, !group.isEmpty {
            clauses.append("meta LIKE ?")
            args.append(.text("%\"snippet_group\":\"\(group)\"%"))
        }
        let likeCtx = contextClauses(context, alias: "")
        clauses.append(contentsOf: likeCtx.clauses)
        args.append(contentsOf: likeCtx.args)
        var sql = "SELECT \(Self.listColumns) FROM clip"
        if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
        sql += " ORDER BY pinned DESC, created_at DESC LIMIT ?"
        args.append(.int(Int64(limit)))
        let statement = try db.prepare(sql)
        statement.bind(args)
        return collect(statement)
    }

    /// 检索语法（`#11` / `len:>8` / `app:微信` / `before:昨天` / `138*`）生成的 SQL 子句。
    private func structuredClauses(_ query: ParsedQuery, alias: String) -> (clauses: [String], args: [SQLValue]) {
        var clauses: [String] = []
        var args: [SQLValue] = []
        let numKey = "\(alias)num_key"

        if let count = query.digitCount {
            clauses.append("(\(numKey) IS NOT NULL AND length(\(numKey)) = ?)")
            args.append(.int(Int64(count)))
        }
        if let count = query.minDigits {
            clauses.append("(\(numKey) IS NOT NULL AND length(\(numKey)) > ?)")
            args.append(.int(Int64(count)))
        }
        if let count = query.maxDigits {
            clauses.append("(\(numKey) IS NOT NULL AND length(\(numKey)) < ?)")
            args.append(.int(Int64(count)))
        }
        if let count = query.length {
            clauses.append("length(\(alias)plain_text) = ?")
            args.append(.int(Int64(count)))
        }
        if let count = query.minLength {
            clauses.append("length(\(alias)plain_text) > ?")
            args.append(.int(Int64(count)))
        }
        if let count = query.maxLength {
            clauses.append("length(\(alias)plain_text) < ?")
            args.append(.int(Int64(count)))
        }
        if let source = query.source {
            clauses.append("(\(alias)source_name LIKE ? OR \(alias)source_bundle LIKE ?)")
            args.append(.text("%\(source)%"))
            args.append(.text("%\(source)%"))
        }
        if let before = query.before {
            clauses.append("\(alias)created_at < ?")
            args.append(.double(before.timeIntervalSince1970))
        }
        if let after = query.after {
            clauses.append("\(alias)created_at >= ?")
            args.append(.double(after.timeIntervalSince1970))
        }
        if let prefix = query.prefix {
            clauses.append("(\(alias)plain_text LIKE ? OR \(alias)title LIKE ?)")
            args.append(.text("\(prefix)%"))
            args.append(.text("\(prefix)%"))
        }
        return (clauses, args)
    }

    /// 情境过滤的 SQL 子句与绑定参数；alias 为表别名前缀（如 "clip."）。
    private func contextClauses(_ context: ContextFilter, alias: String) -> (clauses: [String], args: [SQLValue]) {
        var clauses: [String] = []
        var args: [SQLValue] = []
        if let bundle = context.sourceBundle, !bundle.isEmpty {
            clauses.append("\(alias)source_bundle = ?")
            args.append(.text(bundle))
        }
        if let since = context.since {
            clauses.append("\(alias)created_at >= ?")
            args.append(.double(since.timeIntervalSince1970))
        }
        if let until = context.until {
            clauses.append("\(alias)created_at < ?")
            args.append(.double(until.timeIntervalSince1970))
        }
        return (clauses, args)
    }

    func matchesFilter(_ item: ClipItem, _ filter: FilterKind, snippetGroup: String? = nil,
                       context: ContextFilter = ContextFilter()) -> Bool {
        if let bundle = context.sourceBundle, !bundle.isEmpty, item.sourceBundle != bundle { return false }
        if let since = context.since, item.createdAt < since { return false }
        if let until = context.until, item.createdAt >= until { return false }
        if filter == .snippet, let group = snippetGroup, !group.isEmpty {
            guard item.tags.contains(FilterKind.snippetTag) && item.snippetGroup == group else { return false }
        }
        switch filter {
        case .all: return true
        case .pinned: return item.pinned
        case .snippet: return item.tags.contains(FilterKind.snippetTag)
        case .text: return item.kind == .text || item.kind == .richText || item.kind == .pdf
        case .image: return item.kind == .image
        case .file: return item.kind == .file
        case .link: return item.kind == .url
        case .number: return NumberKind.allTags.contains { item.tags.contains($0) }
        }
    }

    public func item(id: Int64) -> ClipItem? {
        guard let statement = try? db.prepare("SELECT \(Self.listColumns), inline_data FROM clip WHERE id = ?") else { return nil }
        statement.bind([.int(id)])
        return statement.step() ? rowToItem(statement, includeInlineData: true) : nil
    }

    public func itemCount() -> Int {
        guard let statement = try? db.prepare("SELECT COUNT(*) FROM clip"), statement.step() else { return 0 }
        return Int(statement.columnInt(0))
    }

    // MARK: - 语义向量

    /// 待补算向量的文本条目（供后台批量补算）。
    public func itemsNeedingEmbedding(limit: Int = 50) -> [(id: Int64, text: String)] {
        guard let statement = try? db.prepare("""
            SELECT id, plain_text FROM clip
            WHERE embedding IS NULL AND kind IN ('text','url')
              AND length(plain_text) > 0 AND length(plain_text) < 8000
            LIMIT ?
            """) else { return [] }
        statement.bind([.int(Int64(limit))])
        var result: [(Int64, String)] = []
        while statement.step() {
            result.append((statement.columnInt(0), statement.columnText(1) ?? ""))
        }
        return result
    }

    /// 按 id 批量取回（一次查询，供语义候选拼装）。
    public func items(ids: [Int64]) -> [ClipItem] {
        guard !ids.isEmpty else { return [] }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        guard let statement = try? db.prepare("SELECT \(Self.listColumns) FROM clip WHERE id IN (\(placeholders))") else { return [] }
        statement.bind(ids.map { .int($0) })
        return collect(statement)
    }

    public func setEmbedding(_ id: Int64, _ data: Data) {
        guard let statement = try? db.prepare("UPDATE clip SET embedding = ? WHERE id = ?") else { return }
        statement.bind([.blob(data), .int(id)])
        try? statement.run()
        resetEmbeddingCache()
    }

    private func embeddingVectors() -> [Int64: [Float]] {
        cacheLock.lock()
        if let cache = embeddingCache {
            cacheLock.unlock()
            return cache
        }
        cacheLock.unlock()

        var cache: [Int64: [Float]] = [:]
        if let statement = try? db.prepare("SELECT id, embedding FROM clip WHERE embedding IS NOT NULL") {
            while statement.step() {
                if let data = statement.columnData(1), let vector = Self.vectors(from: data) {
                    cache[statement.columnInt(0)] = vector
                }
            }
        }
        cacheLock.lock()
        embeddingCache = cache
        cacheLock.unlock()
        return cache
    }

    // MARK: - 变更

    public func setPinned(_ id: Int64, _ pinned: Bool) throws {
        let statement = try db.prepare("UPDATE clip SET pinned = ? WHERE id = ?")
        statement.bind([.int(pinned ? 1 : 0), .int(id)])
        try statement.run()
    }

    /// 增删条目标签（片段收藏即基于标签实现）。
    public func mutateTag(_ id: Int64, tag: String, add: Bool) throws {
        guard let item = item(id: id) else { return }
        var tags = item.tags
        if add {
            guard !tags.contains(tag) else { return }
            tags.append(tag)
        } else {
            tags.removeAll { $0 == tag }
        }
        let statement = try db.prepare("UPDATE clip SET tags = ? WHERE id = ?")
        statement.bind([.text(json(tags)), .int(id)])
        try statement.run()
    }

    /// 用户自定义标题的 meta 标记；置位后智能标题 / OCR / 链接标题都不再覆盖 title 列。
    public static let userTitleKey = "user_title"

    /// 设置用户自定义标题（写入 title 列，因此 FTS 与 LIKE 检索都能命中）。
    /// 传 nil 或空串表示清除，恢复设置前的自动标题。
    @discardableResult
    public func setUserTitle(_ id: Int64, title: String?) throws -> ClipItem? {
        guard let existing = item(id: id) else { return nil }
        var meta = existing.meta
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)

        let newTitle: String?
        if let trimmed, !trimmed.isEmpty {
            // 首次标注时备份原自动标题，便于之后还原
            if meta[Self.userTitleKey] != "1" {
                if let auto = existing.title, !auto.isEmpty {
                    meta["auto_title"] = auto
                } else {
                    meta.removeValue(forKey: "auto_title")
                }
            }
            meta[Self.userTitleKey] = "1"
            newTitle = trimmed
        } else {
            meta.removeValue(forKey: Self.userTitleKey)
            let restored = meta.removeValue(forKey: "auto_title")
            newTitle = (restored?.isEmpty == false) ? restored : nil
        }

        let statement = try db.prepare("UPDATE clip SET title = ?, meta = ? WHERE id = ?")
        statement.bind([.text(newTitle), .text(json(meta)), .int(id)])
        try statement.run()
        return item(id: id)
    }

    /// 编辑条目文本（富文本场景仅替换纯文本表示）；文本变化后向量失效待补算。
    public func updateText(_ id: Int64, _ text: String) throws {
        guard let existing = item(id: id) else { return }
        let hashData = Data(SHA256.hash(data: Data(existing.kind.rawValue.utf8) + Data(text.utf8)))
        let statement = try db.prepare("""
            UPDATE clip SET plain_text = ?, content_hash = ?, byte_size = ?, embedding = NULL WHERE id = ?
            """)
        statement.bind([.text(text), .blob(hashData), .int(Int64(text.utf8.count)), .int(id)])
        try statement.run()
        resetEmbeddingCache()
    }

    /// 异步 OCR 识别完成后补充文字信息与标签，触发 FTS5 自动索引更新
    @discardableResult
    public func updateOCR(_ id: Int64, text: String, title: String? = nil) throws -> ClipItem? {
        guard let existing = item(id: id) else { return nil }
        var tags = existing.tags
        if !tags.contains("OCR") {
            tags.insert("OCR", at: 0)
        }
        var meta = existing.meta
        meta["ocr"] = "1"
        // 用户手动标注过的标题不被 OCR / 智能标题覆盖
        let newTitle = meta[Self.userTitleKey] == "1" ? existing.title : (title ?? existing.title)
        let statement = try db.prepare("""
            UPDATE clip SET plain_text = ?, tags = ?, meta = ?, title = ? WHERE id = ?
            """)
        statement.bind([.text(text), .text(json(tags)), .text(json(meta)), .text(newTitle), .int(id)])
        try statement.run()
        return item(id: id)
    }


    /// 异步抓取到网页元数据（标题、Favicon 图标）后更新条目
    @discardableResult
    public func updateURLMetadata(_ id: Int64, title: String?, faviconData: Data?) throws -> ClipItem? {
        guard let existing = item(id: id) else { return nil }
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isUserTitled = existing.meta[Self.userTitleKey] == "1"
        let newTitle = isUserTitled
            ? existing.title
            : ((trimmedTitle?.isEmpty == false) ? trimmedTitle : existing.title)
        let newInlineData = faviconData ?? existing.inlineData
        guard newTitle != existing.title || faviconData != nil else { return existing }

        var meta = existing.meta
        if newTitle != nil, !isUserTitled { meta["link_title"] = "1" }
        if newInlineData != nil { meta["link_favicon"] = "1" }

        let statement = try db.prepare("""
            UPDATE clip SET title = ?, inline_data = ?, meta = ? WHERE id = ?
            """)
        statement.bind([
            .text(newTitle),
            .blob(newInlineData),
            .text(json(meta)),
            .int(id)
        ])
        try statement.run()
        return item(id: id)
    }

    // MARK: - 片段管理

    /// 获取当前所有已存在的片段分组列表（去重且排序）
    /// 按当前标签规则重算存量条目的自动标签（只增不减，规则升级后一次性回填）。
    /// 新增号码识别等规则后，历史条目也需要补上标签才能被分类过滤到。
    @discardableResult
    public func backfillAutoTags(limit: Int = 5000) -> Int {
        guard let statement = try? db.prepare("""
            SELECT id, kind, plain_text, tags FROM clip
            WHERE kind IN ('text','url','richText')
            LIMIT ?
            """) else { return 0 }
        statement.bind([.int(Int64(limit))])

        var updates: [(id: Int64, tags: [String])] = []
        while statement.step() {
            let id = statement.columnInt(0)
            guard let kindRaw = statement.columnText(1), let kind = ClipKind(rawValue: kindRaw) else { continue }
            let text = statement.columnText(2) ?? ""
            var tags = decodeTags(from: statement.columnText(3))
            let missing = AutoTagger.tags(for: text, kind: kind).filter { !tags.contains($0) }
            guard !missing.isEmpty else { continue }
            tags.append(contentsOf: missing)
            updates.append((id, tags))
        }

        guard !updates.isEmpty,
              let update = try? db.prepare("UPDATE clip SET tags = ? WHERE id = ?") else { return 0 }
        for entry in updates {
            update.bind([.text(json(entry.tags)), .int(entry.id)])
            try? update.run()
        }
        return updates.count
    }

    /// 回填存量条目的号码归一化键（迁移 v4 后的一次性后台任务）。
    /// 非号码条目写入空串哨兵，避免每次启动重复扫描。
    public func backfillNumberKeys(limit: Int = 5000) {
        guard let statement = try? db.prepare("""
            SELECT id, plain_text FROM clip
            WHERE num_key IS NULL AND kind IN ('text','url') AND length(plain_text) <= 64
            LIMIT ?
            """) else { return }
        statement.bind([.int(Int64(limit))])

        var updates: [(id: Int64, key: String)] = []
        while statement.step() {
            let id = statement.columnInt(0)
            let key = statement.columnText(1).flatMap { NumberRecognizer.normalize($0) } ?? ""
            updates.append((id, key))
        }
        guard !updates.isEmpty,
              let update = try? db.prepare("UPDATE clip SET num_key = ? WHERE id = ?") else { return }
        for entry in updates {
            update.bind([.text(entry.key), .int(entry.id)])
            try? update.run()
        }
    }

    /// 来源应用聚合（按条目数降序），供情境筛选菜单展示。
    public func distinctSources(limit: Int = 20) -> [ClipSource] {
        guard let statement = try? db.prepare("""
            SELECT source_bundle, source_name, COUNT(*) FROM clip
            WHERE source_bundle <> ''
            GROUP BY source_bundle
            ORDER BY COUNT(*) DESC
            LIMIT ?
            """) else { return [] }
        statement.bind([.int(Int64(limit))])
        var result: [ClipSource] = []
        while statement.step() {
            let bundle = statement.columnText(0) ?? ""
            let rawName = statement.columnText(1) ?? ""
            result.append(ClipSource(
                bundle: bundle,
                name: rawName.isEmpty ? bundle : rawName,
                count: Int(statement.columnInt(2))
            ))
        }
        return result
    }

    public func allSnippetGroups() -> [String] {
        guard let statement = try? db.prepare("""
            SELECT meta FROM clip WHERE tags LIKE '%"\(FilterKind.snippetTag)"%'
            """) else { return [] }
        var groups = Set<String>()
        while statement.step() {
            if let metaJson = statement.columnText(0),
               let data = metaJson.data(using: .utf8),
               let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let group = dict["snippet_group"] as? String {
                let trimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    groups.insert(trimmed)
                }
            }
        }
        return groups.sorted()
    }

    /// 创建一个新片段（可来自手动录入，或从历史转换）
    @discardableResult
    public func createSnippet(title: String, text: String, group: String? = nil, shortcode: String? = nil) throws -> ClipItem {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGroup = group?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedShortcode = shortcode?.trimmingCharacters(in: .whitespacesAndNewlines)

        var tags = [FilterKind.snippetTag]
        if let g = trimmedGroup, !g.isEmpty, !tags.contains(g) {
            tags.append(g)
        }

        var meta: [String: String] = ["snippet": "1"]
        if let g = trimmedGroup, !g.isEmpty {
            meta["snippet_group"] = g
        }
        let cleanShortcode: String? = {
            guard let s = trimmedShortcode, !s.isEmpty else { return nil }
            let stripped = s.hasPrefix("/") ? String(s.dropFirst()) : s
            return stripped.isEmpty ? nil : stripped
        }()
        if let cleanShortcode {
            meta["snippet_shortcode"] = cleanShortcode
        }

        let now = Date()
        let kind = ClipKind.text
        let hashData = Data(SHA256.hash(data: Data(kind.rawValue.utf8) + Data(text.utf8)))

        // 检查是否已有相同哈希的内容，若有则升级为片段
        let dup = try? db.prepare("SELECT id FROM clip WHERE content_hash = ? LIMIT 1")
        dup?.bind([.blob(hashData)])
        let existingID: Int64? = (dup?.step() == true) ? dup?.columnInt(0) : nil

        if let id = existingID, let existing = item(id: id) {
            var updatedTags = existing.tags
            if !updatedTags.contains(FilterKind.snippetTag) {
                updatedTags.insert(FilterKind.snippetTag, at: 0)
            }
            if let g = trimmedGroup, !g.isEmpty, !updatedTags.contains(g) {
                updatedTags.append(g)
            }
            var updatedMeta = existing.meta
            updatedMeta["snippet"] = "1"
            if let g = trimmedGroup, !g.isEmpty { updatedMeta["snippet_group"] = g }
            if let cleanShortcode { updatedMeta["snippet_shortcode"] = cleanShortcode }

            let statement = try db.prepare("""
                UPDATE clip SET title = ?, tags = ?, meta = ?, last_used_at = ? WHERE id = ?
                """)
            statement.bind([
                .text(trimmedTitle.isEmpty ? (existing.title ?? "") : trimmedTitle),
                .text(json(updatedTags)),
                .text(json(updatedMeta)),
                .double(now.timeIntervalSince1970),
                .int(existing.id)
            ])
            try statement.run()
            return item(id: existing.id)!
        }

        let statement = try db.prepare("""
            INSERT INTO clip (
                kind, plain_text, source_bundle, source_name, content_hash,
                byte_size, created_at, last_used_at, use_count, pinned,
                tags, title, meta, inline_data, blob_name
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 0, ?, ?, ?, NULL, NULL)
            """)
        statement.bind([
            .text(kind.rawValue),
            .text(text),
            .text(""),
            .text("ClipMate"),
            .blob(hashData),
            .int(Int64(text.utf8.count)),
            .double(now.timeIntervalSince1970),
            .double(now.timeIntervalSince1970),
            .text(json(tags)),
            .text(trimmedTitle.isEmpty ? nil : trimmedTitle),
            .text(json(meta))
        ])
        try statement.run()
        return item(id: db.lastInsertRowID)!
    }

    /// 更新片段元数据或正文
    @discardableResult
    public func updateSnippet(id: Int64, title: String?, group: String?, shortcode: String?, text: String? = nil) throws -> ClipItem? {
        guard let existing = item(id: id) else { return nil }

        var tags = existing.tags
        if !tags.contains(FilterKind.snippetTag) {
            tags.insert(FilterKind.snippetTag, at: 0)
        }

        var meta = existing.meta
        meta["snippet"] = "1"

        if let group {
            let trimmedGroup = group.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedGroup.isEmpty {
                meta.removeValue(forKey: "snippet_group")
            } else {
                meta["snippet_group"] = trimmedGroup
                if !tags.contains(trimmedGroup) {
                    tags.append(trimmedGroup)
                }
            }
        }

        if let shortcode {
            let trimmedCode = shortcode.trimmingCharacters(in: .whitespacesAndNewlines)
            let stripped = trimmedCode.hasPrefix("/") ? String(trimmedCode.dropFirst()) : trimmedCode
            if stripped.isEmpty {
                meta.removeValue(forKey: "snippet_shortcode")
            } else {
                meta["snippet_shortcode"] = stripped
            }
        }

        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTitle = (trimmedTitle?.isEmpty == false) ? trimmedTitle : nil

        if let text, text != existing.plainText {
            let hashData = Data(SHA256.hash(data: Data(existing.kind.rawValue.utf8) + Data(text.utf8)))
            let statement = try db.prepare("""
                UPDATE clip SET plain_text = ?, content_hash = ?, byte_size = ?, title = ?, tags = ?, meta = ?, embedding = NULL WHERE id = ?
                """)
            statement.bind([
                .text(text),
                .blob(hashData),
                .int(Int64(text.utf8.count)),
                .text(newTitle),
                .text(json(tags)),
                .text(json(meta)),
                .int(id)
            ])
            try statement.run()
            resetEmbeddingCache()
        } else {
            let statement = try db.prepare("""
                UPDATE clip SET title = ?, tags = ?, meta = ? WHERE id = ?
                """)
            statement.bind([
                .text(newTitle),
                .text(json(tags)),
                .text(json(meta)),
                .int(id)
            ])
            try statement.run()
        }

        return item(id: id)
    }

    /// 获取全部片段条目（可选按分组过滤）
    public func allSnippets(group: String? = nil) -> [ClipItem] {
        search(query: "", filter: .snippet, snippetGroup: group, limit: 1000)
    }

    public func delete(_ id: Int64) throws {
        if let item = item(id: id), let blobName = item.blobName {
            blobs.remove(blobName)
        }
        let statement = try db.prepare("DELETE FROM clip WHERE id = ?")
        statement.bind([.int(id)])
        try statement.run()
        resetEmbeddingCache()
    }

    public func deleteAll(keepPinned: Bool) throws {
        let statement = try db.prepare(keepPinned ? "DELETE FROM clip WHERE pinned = 0" : "DELETE FROM clip")
        try statement.run()
        resetEmbeddingCache()
        cleanupOrphanBlobs()
    }

    /// 保留策略：条数 + 天数，固定条目豁免。
    public func enforceRetention(maxItems: Int, maxAgeDays: Int) throws {
        if maxAgeDays > 0 {
            let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 86400).timeIntervalSince1970
            let statement = try db.prepare("DELETE FROM clip WHERE pinned = 0 AND created_at < ?")
            statement.bind([.double(cutoff)])
            try statement.run()
        }
        if maxItems > 0 {
            let statement = try db.prepare("""
                DELETE FROM clip WHERE pinned = 0 AND id NOT IN
                (SELECT id FROM clip WHERE pinned = 0 ORDER BY created_at DESC LIMIT ?)
                """)
            statement.bind([.int(Int64(maxItems))])
            try statement.run()
        }
        resetEmbeddingCache()
        cleanupOrphanBlobs()
    }

    // MARK: - 导入导出

    struct ExportItem: Codable {
        var kind: String
        var plainText: String
        var sourceBundle: String
        var sourceName: String
        var tags: [String]
        var meta: [String: String]
        var createdAt: Date
    }

    struct ExportDocument: Codable {
        var version: Int
        var exportedAt: Date
        var items: [ExportItem]
    }

    public func exportJSON() throws -> Data {
        let statement = try db.prepare("SELECT \(Self.listColumns) FROM clip ORDER BY created_at ASC")
        let items = collect(statement).map { item in
            ExportItem(kind: item.kind.rawValue, plainText: item.plainText,
                       sourceBundle: item.sourceBundle, sourceName: item.sourceName,
                       tags: item.tags, meta: item.meta, createdAt: item.createdAt)
        }
        let document = ExportDocument(version: 1, exportedAt: Date(), items: items)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        defer { encoder.outputFormatting = [] }
        return try encoder.encode(document)
    }

    /// 导入（逐条走 capture 去重），返回新入库条数。
    public func importJSON(_ data: Data) throws -> Int {
        decoder.dateDecodingStrategy = .secondsSince1970
        defer { decoder.dateDecodingStrategy = .deferredToDate }
        let document: ExportDocument
        do {
            document = try decoder.decode(ExportDocument.self, from: data)
        } catch {
            throw StoreError.sql("文件格式不正确：\(error.localizedDescription)")
        }
        var imported = 0
        for entry in document.items {
            guard let kind = ClipKind(rawValue: entry.kind) else { continue }
            let result = try capture(kind: kind, plainText: entry.plainText,
                                     sourceBundle: entry.sourceBundle, sourceName: entry.sourceName,
                                     tags: entry.tags, meta: entry.meta,
                                     createdAt: entry.createdAt)
            if result.isNew { imported += 1 }
        }
        return imported
    }

    // MARK: - 粘贴内容装配与按需二进制

    /// 按需读取单条记录的缩略图/内联二进制（避免列表检索全量读取大量 BLOB）
    public func inlineData(for id: Int64) -> Data? {
        guard let statement = try? db.prepare("SELECT inline_data FROM clip WHERE id = ?") else { return nil }
        statement.bind([.int(id)])
        guard statement.step() else { return nil }
        return statement.columnData(0)
    }

    public func pasteboardContent(for item: ClipItem) -> PasteboardContent? {
        switch item.kind {
        case .text, .url:
            return .text(item.plainText)
        case .richText:
            if let rtf = item.inlineData ?? inlineData(for: item.id) { return .richText(rtf: rtf, plain: item.plainText) }
            return .text(item.plainText)
        case .image:
            guard let name = item.blobName,
                  let data = try? Data(contentsOf: blobs.url(for: name)) else { return nil }
            return .image(data: data)
        case .pdf:
            guard let name = item.blobName,
                  let data = try? Data(contentsOf: blobs.url(for: name)) else { return nil }
            return .pdf(data: data, plain: item.plainText)
        case .file:
            let urls = item.plainText
                .components(separatedBy: "\n")
                .filter { !$0.isEmpty }
                .compactMap(URL.init(string:))
            guard !urls.isEmpty else { return nil }
            return .files(urls)
        }
    }

    public func imageURL(for item: ClipItem) -> URL? {
        item.blobName.map { blobs.url(for: $0) }
    }

    // MARK: - Private

    private func collect(_ statement: Statement, includeInlineData: Bool = false) -> [ClipItem] {
        var items: [ClipItem] = []
        while statement.step() {
            items.append(rowToItem(statement, includeInlineData: includeInlineData))
        }
        return items
    }

    private func rowToItem(_ statement: Statement, includeInlineData: Bool = false) -> ClipItem {
        let tags = decodeTags(from: statement.columnText(Col.tags))
        let meta = decodeMeta(from: statement.columnText(Col.meta))
        return ClipItem(
            id: statement.columnInt(Col.id),
            kind: ClipKind(rawValue: statement.columnText(Col.kind) ?? "text") ?? .text,
            plainText: statement.columnText(Col.plainText) ?? "",
            sourceBundle: statement.columnText(Col.sourceBundle) ?? "",
            sourceName: statement.columnText(Col.sourceName) ?? "",
            byteSize: Int(statement.columnInt(Col.byteSize)),
            createdAt: Date(timeIntervalSince1970: statement.columnDouble(Col.createdAt)),
            lastUsedAt: Date(timeIntervalSince1970: statement.columnDouble(Col.lastUsedAt)),
            useCount: Int(statement.columnInt(Col.useCount)),
            pinned: statement.columnInt(Col.pinned) != 0,
            tags: tags,
            title: statement.columnText(Col.title),
            meta: meta,
            inlineData: includeInlineData ? statement.columnData(Col.inlineData) : nil,
            blobName: statement.columnText(Col.blobName)
        )
    }

    /// 极速 JSON 快路径：针对高频空集合直出空实例，非空改用 JSONSerialization 规避 Codable 反射开销
    private func decodeTags(from string: String?) -> [String] {
        guard let string, !string.isEmpty, string != "[]" else { return [] }
        if let data = string.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return array
        }
        return []
    }

    private func decodeMeta(from string: String?) -> [String: String] {
        guard let string, !string.isEmpty, string != "{}" else { return [:] }
        if let data = string.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            return dict
        }
        return [:]
    }

    private func json(_ value: some Encodable) -> String {
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func ftsExpression(for query: String) -> String {
        let tokens = query.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return "\"\"" }
        return tokens
            .map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }
            .joined(separator: " ")
    }

    private func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0x3040...0x30FF).contains(scalar.value)
                || (0xAC00...0xD7AF).contains(scalar.value)
        }
    }

    private func cleanupOrphanBlobs() {
        guard let statement = try? db.prepare("SELECT DISTINCT blob_name FROM clip WHERE blob_name IS NOT NULL") else { return }
        var referenced = Set<String>()
        while statement.step() {
            if let name = statement.columnText(0) { referenced.insert(name) }
        }
        for name in blobs.allNames() where !referenced.contains(name) {
            blobs.remove(name)
        }
    }

    // MARK: - 向量编解码与相似度

    public static func data(from vector: [Double]) -> Data {
        let floats = vector.map(Float.init)
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    public static func vectors(from data: Data) -> [Float]? {
        guard !data.isEmpty, data.count % MemoryLayout<Float>.size == 0 else { return nil }
        return data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }
    }

    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, normA: Float = 0, normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denominator = (normA * normB).squareRoot()
        guard denominator > 0 else { return 0 }
        return dot / denominator
    }
}
