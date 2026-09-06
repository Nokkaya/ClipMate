import Foundation
import CryptoKit

/// 历史存储：SQLite（去重合并、FTS5/LIKE 检索、固定、保留策略、大对象落盘）。
public final class ClipStore {
    private let db: Database
    private let blobs: BlobStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(database: Database, blobStore: BlobStore) throws {
        self.db = database
        self.blobs = blobStore
        try Migrations.run(database)
    }

    public var supportsFullTextSearch: Bool { db.hasFTS5 }

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

    /// 相同内容再次复制时上浮并累加 use_count，不产生新行。
    @discardableResult
    public func capture(kind: ClipKind,
                        plainText: String,
                        sourceBundle: String,
                        sourceName: String,
                        tags: [String] = [],
                        inlineData: Data? = nil,
                        imageOriginal: Data? = nil,
                        meta: [String: String] = [:]) throws -> (item: ClipItem, isNew: Bool) {
        var meta = meta
        var blobName: String?
        if kind == .image, let original = imageOriginal {
            blobName = try blobs.store(original)
            meta["bytes"] = String(original.count)
        }

        let content = kind == .image ? (imageOriginal ?? Data()) : Data(plainText.utf8)
        let hashData = Data(SHA256.hash(data: Data(kind.rawValue.utf8) + content))
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
                .int(Int64(content.count)), .double(now), .double(now),
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
            .blob(hashData), .int(Int64(content.count)), .double(now), .double(now),
            .text(json(tags)), .text(json(meta)), .blob(inlineData), .text(blobName),
        ])
        try insert.run()
        guard let item = item(id: db.lastInsertRowID) else { throw StoreError.sql("插入后读取失败") }
        return (item, true)
    }

    // MARK: - 查询

    /// 检索：拉丁文走 FTS5 前缀匹配（按相关度），含 CJK 的查询走 LIKE（系统 FTS5 默认分词器不切中文）。
    public func search(query: String, filter: FilterKind = .all, limit: Int = 300) -> [ClipItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if !trimmed.isEmpty, db.hasFTS5, !containsCJK(trimmed) {
                let ftsQuery = ftsExpression(for: trimmed)
                var sql = "SELECT clip.* FROM clip, clip_fts WHERE clip_fts MATCH ? AND clip.id = clip_fts.rowid"
                if let clause = filter.kindClause { sql += " AND \(clause)" }
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
            if filter == .pinned { clauses.append("pinned = 1") }
            var sql = "SELECT * FROM clip"
            if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
            sql += " ORDER BY pinned DESC, created_at DESC LIMIT ?"
            args.append(.int(Int64(limit)))
            let statement = try db.prepare(sql)
            statement.bind(args)
            return collect(statement)
        } catch {
            return []
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

    // MARK: - 变更

    public func setPinned(_ id: Int64, _ pinned: Bool) throws {
        let statement = try db.prepare("UPDATE clip SET pinned = ? WHERE id = ?")
        statement.bind([.int(pinned ? 1 : 0), .int(id)])
        try statement.run()
    }

    /// 编辑条目文本（富文本场景仅替换纯文本表示）。
    public func updateText(_ id: Int64, _ text: String) throws {
        guard let existing = item(id: id) else { return }
        let hashData = Data(SHA256.hash(data: Data(existing.kind.rawValue.utf8) + Data(text.utf8)))
        let statement = try db.prepare("UPDATE clip SET plain_text = ?, content_hash = ?, byte_size = ? WHERE id = ?")
        statement.bind([.text(text), .blob(hashData), .int(Int64(text.utf8.count)), .int(id)])
        try statement.run()
    }

    public func delete(_ id: Int64) throws {
        if let item = item(id: id), let blobName = item.blobName {
            blobs.remove(blobName)
        }
        let statement = try db.prepare("DELETE FROM clip WHERE id = ?")
        statement.bind([.int(id)])
        try statement.run()
    }

    public func deleteAll(keepPinned: Bool) throws {
        let statement = try db.prepare(keepPinned ? "DELETE FROM clip WHERE pinned = 0" : "DELETE FROM clip")
        try statement.run()
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
        cleanupOrphanBlobs()
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
}
