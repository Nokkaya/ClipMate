import Foundation
import CryptoKit

/// 历史存储：SQLite（去重合并、FTS5/LIKE 检索、语义向量混合排序、固定、保留策略、大对象落盘、导入导出）。
public final class ClipStore {
    private let db: Database
    private let blobs: BlobStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// 语义检索的向量生成器（文本 → 向量二进制）；nil 表示未启用。
    private let embeddingProvider: ((String) -> Data?)?
    /// 向量缓存：id → float 数组（懒加载，写操作后失效）。
    private var embeddingCache: [Int64: [Float]]?

    public init(database: Database,
                blobStore: BlobStore,
                embeddingProvider: ((String) -> Data?)? = nil) throws {
        self.db = database
        self.blobs = blobStore
        self.embeddingProvider = embeddingProvider
        try Migrations.run(database)
    }

    public var supportsFullTextSearch: Bool { db.hasFTS5 }

    /// 当前已建立向量的条目数。
    public var embeddedCount: Int { embeddingVectors().count }

    // MARK: - 列

    private enum Col {
        static let id: Int32 = 0
        static let kind: Int32 = 1
        static let plainText: Int32 = 2
        static let sourceBundle: Int32 = 3
        static let sourceName: Int32 = 4
        static let byteSize: Int32 = 6
        static let createdAt: Int32 = 7
        static let lastUsedAt: Int32 = 8
        static let useCount: Int32 = 9
        static let pinned: Int32 = 10
        static let title: Int32 = 11
        static let tags: Int32 = 12
        static let meta: Int32 = 13
        static let inlineData: Int32 = 14
        static let blobName: Int32 = 15
    }

    // MARK: - 采集入库（含去重合并）

    /// 相同内容再次复制时上浮并累加 use_count，不产生新行。createdAt 供导入还原原始时间。
    @discardableResult
    public func capture(kind: ClipKind,
                        plainText: String,
                        sourceBundle: String,
                        sourceName: String,
                        tags: [String] = [],
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

        let dup = try db.prepare("SELECT id FROM clip WHERE content_hash = ? LIMIT 1")
        dup.bind([.blob(hashData)])
        let existingID: Int64? = dup.step() ? dup.columnInt(0) : nil

        if let id = existingID {
            let update = try db.prepare("""
                UPDATE clip SET kind = ?, plain_text = ?, source_bundle = ?, source_name = ?,
                    byte_size = ?, created_at = ?, last_used_at = ?, use_count = use_count + 1,
                    inline_data = ?, blob_name = ?, meta = ?
                WHERE id = ?
                """)
            update.bind([
                .text(kind.rawValue), .text(plainText), .text(sourceBundle), .text(sourceName),
                .int(Int64(content.count)), .double(timestamp), .double(now),
                .blob(inlineData), .text(blobName), .text(json(meta)),
                .int(id),
            ])
            try update.run()
            guard let item = item(id: id) else { throw StoreError.sql("去重更新后读取失败") }
            return (item, false)
        }

        let insert = try db.prepare("""
            INSERT INTO clip (kind, plain_text, source_bundle, source_name, content_hash, byte_size,
                created_at, last_used_at, use_count, pinned, title, tags, meta, inline_data, blob_name)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 0, NULL, ?, ?, ?, ?)
            """)
        insert.bind([
            .text(kind.rawValue), .text(plainText), .text(sourceBundle), .text(sourceName),
            .blob(hashData), .int(Int64(content.count)), .double(timestamp), .double(timestamp),
            .text(json(tags)), .text(json(meta)), .blob(inlineData), .text(blobName),
        ])
        try insert.run()
        guard let item = item(id: db.lastInsertRowID) else { throw StoreError.sql("插入后读取失败") }
        return (item, true)
    }

    // MARK: - 查询

    /// 检索：文本路径（FTS5 前缀/LIKE）+ 语义向量路径，RRF 混合排序。
    /// 拉丁文查询走 FTS5，含 CJK 的查询走 LIKE（系统 FTS5 默认分词器不切中文）。
    public func search(query: String, filter: FilterKind = .all, limit: Int = 300) -> [ClipItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let textResults = try textSearch(trimmed, filter: filter, limit: limit)
            guard !trimmed.isEmpty, let provider = embeddingProvider else { return textResults }

            let vectors = embeddingVectors()
            guard !vectors.isEmpty else { return textResults }

            // 语义召回：余弦相似度，取 top 2×limit
            guard let queryData = provider(trimmed),
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
            let vectorIDs = candidates.prefix(limit * 2).map(\.id)

            // RRF 融合两路排名
            var scores: [Int64: Double] = [:]
            for (rank, item) in textResults.enumerated() {
                scores[item.id, default: 0] += 1.0 / Double(60 + rank)
            }
            var itemMap = Dictionary(uniqueKeysWithValues: textResults.map { ($0.id, $0) })
            for (rank, id) in vectorIDs.enumerated() {
                scores[id, default: 0] += 1.0 / Double(60 + rank)
                if itemMap[id] == nil, let fetched = item(id: id), matchesFilter(fetched, filter) {
                    itemMap[id] = fetched
                }
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

    private func textSearch(_ trimmed: String, filter: FilterKind, limit: Int) throws -> [ClipItem] {
        if !trimmed.isEmpty, db.hasFTS5, !containsCJK(trimmed) {
            let ftsQuery = ftsExpression(for: trimmed)
            var sql = "SELECT clip.* FROM clip, clip_fts WHERE clip_fts MATCH ? AND clip.id = clip_fts.rowid"
            if let clause = filter.kindClause { sql += " AND \(clause)" }
            if let extra = filter.extraClause { sql += " AND \(extra)" }
            if filter == .pinned { sql += " AND clip.pinned = 1" }
            sql += " ORDER BY clip.pinned DESC, rank LIMIT ?"
            let statement = try db.prepare(sql)
            statement.bind([.text(ftsQuery), .int(Int64(limit))])
            return collect(statement)
        }

        var clauses: [String] = []
        var args: [SQLValue] = []
        if !trimmed.isEmpty {
            clauses.append("plain_text LIKE ?")
            args.append(.text("%\(trimmed)%"))
        }
        if let clause = filter.kindClause { clauses.append(clause) }
        if let extra = filter.extraClause { clauses.append(extra) }
        if filter == .pinned { clauses.append("pinned = 1") }
        var sql = "SELECT * FROM clip"
        if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
        sql += " ORDER BY pinned DESC, created_at DESC LIMIT ?"
        args.append(.int(Int64(limit)))
        let statement = try db.prepare(sql)
        statement.bind(args)
        return collect(statement)
    }

    func matchesFilter(_ item: ClipItem, _ filter: FilterKind) -> Bool {
        switch filter {
        case .all: return true
        case .pinned: return item.pinned
        case .snippet: return item.tags.contains(FilterKind.snippetTag)
        case .text: return item.kind == .text || item.kind == .richText || item.kind == .pdf
        case .image: return item.kind == .image
        case .file: return item.kind == .file
        case .link: return item.kind == .url
        }
    }

    public func item(id: Int64) -> ClipItem? {
        guard let statement = try? db.prepare("SELECT * FROM clip WHERE id = ?") else { return nil }
        statement.bind([.int(id)])
        return statement.step() ? rowToItem(statement) : nil
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

    public func setEmbedding(_ id: Int64, _ data: Data) {
        guard let statement = try? db.prepare("UPDATE clip SET embedding = ? WHERE id = ?") else { return }
        statement.bind([.blob(data), .int(id)])
        try? statement.run()
        embeddingCache = nil
    }

    private func embeddingVectors() -> [Int64: [Float]] {
        if let cache = embeddingCache { return cache }
        var cache: [Int64: [Float]] = [:]
        if let statement = try? db.prepare("SELECT id, embedding FROM clip WHERE embedding IS NOT NULL") {
            while statement.step() {
                if let data = statement.columnData(1), let vector = Self.vectors(from: data) {
                    cache[statement.columnInt(0)] = vector
                }
            }
        }
        embeddingCache = cache
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

    /// 编辑条目文本（富文本场景仅替换纯文本表示）；文本变化后向量失效待补算。
    public func updateText(_ id: Int64, _ text: String) throws {
        guard let existing = item(id: id) else { return }
        let hashData = Data(SHA256.hash(data: Data(existing.kind.rawValue.utf8) + Data(text.utf8)))
        let statement = try db.prepare("""
            UPDATE clip SET plain_text = ?, content_hash = ?, byte_size = ?, embedding = NULL WHERE id = ?
            """)
        statement.bind([.text(text), .blob(hashData), .int(Int64(text.utf8.count)), .int(id)])
        try statement.run()
        embeddingCache = nil
    }

    public func delete(_ id: Int64) throws {
        if let item = item(id: id), let blobName = item.blobName {
            blobs.remove(blobName)
        }
        let statement = try db.prepare("DELETE FROM clip WHERE id = ?")
        statement.bind([.int(id)])
        try statement.run()
        embeddingCache = nil
    }

    public func deleteAll(keepPinned: Bool) throws {
        let statement = try db.prepare(keepPinned ? "DELETE FROM clip WHERE pinned = 0" : "DELETE FROM clip")
        try statement.run()
        embeddingCache = nil
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
        embeddingCache = nil
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
        let statement = try db.prepare("SELECT * FROM clip ORDER BY created_at ASC")
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

    // MARK: - 粘贴内容装配

    public func pasteboardContent(for item: ClipItem) -> PasteboardContent? {
        switch item.kind {
        case .text, .url:
            return .text(item.plainText)
        case .richText:
            if let rtf = item.inlineData { return .richText(rtf: rtf, plain: item.plainText) }
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

    private func collect(_ statement: Statement) -> [ClipItem] {
        var items: [ClipItem] = []
        while statement.step() {
            items.append(rowToItem(statement))
        }
        return items
    }

    private func rowToItem(_ statement: Statement) -> ClipItem {
        let tags = decode([String].self, from: statement.columnText(Col.tags)) ?? []
        let meta = decode([String: String].self, from: statement.columnText(Col.meta)) ?? [:]
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
            inlineData: statement.columnData(Col.inlineData),
            blobName: statement.columnText(Col.blobName)
        )
    }

    private func decode<T: Decodable>(_ type: T.Type, from string: String?) -> T? {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return try? decoder.decode(type, from: data)
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
