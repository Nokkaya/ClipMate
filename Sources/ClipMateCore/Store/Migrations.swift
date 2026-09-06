import Foundation

enum Migrations {
    static func run(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE IF NOT EXISTS clip (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            plain_text TEXT NOT NULL DEFAULT '',
            source_bundle TEXT NOT NULL DEFAULT '',
            source_name TEXT NOT NULL DEFAULT '',
            content_hash BLOB NOT NULL,
            byte_size INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            last_used_at REAL NOT NULL,
            use_count INTEGER NOT NULL DEFAULT 1,
            pinned INTEGER NOT NULL DEFAULT 0,
            title TEXT,
            tags TEXT NOT NULL DEFAULT '[]',
            meta TEXT NOT NULL DEFAULT '{}',
            inline_data BLOB,
            blob_name TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_clip_list ON clip(pinned DESC, created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_clip_hash ON clip(content_hash);
        """)

        // FTS5 外部内容表 + 触发器同步；不可用时由 ClipStore 降级 LIKE。
        if db.hasFTS5 {
            try db.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS clip_fts USING fts5(plain_text, content='clip', content_rowid='id');
            CREATE TRIGGER IF NOT EXISTS clip_ai AFTER INSERT ON clip BEGIN
                INSERT INTO clip_fts(rowid, plain_text) VALUES (new.id, new.plain_text);
            END;
            CREATE TRIGGER IF NOT EXISTS clip_ad AFTER DELETE ON clip BEGIN
                INSERT INTO clip_fts(clip_fts, rowid, plain_text) VALUES ('delete', old.id, old.plain_text);
            END;
            CREATE TRIGGER IF NOT EXISTS clip_au AFTER UPDATE OF plain_text ON clip BEGIN
                INSERT INTO clip_fts(clip_fts, rowid, plain_text) VALUES ('delete', old.id, old.plain_text);
                INSERT INTO clip_fts(rowid, plain_text) VALUES (new.id, new.plain_text);
            END;
            """)
        }
        try db.execute("PRAGMA user_version = 1;")
    }
}
