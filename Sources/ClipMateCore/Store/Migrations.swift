import Foundation

enum Migrations {
    static func run(_ db: Database) throws {
        // v1：基础表
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
        CREATE INDEX IF NOT EXISTS idx_clip_blob ON clip(blob_name);
        """)

        // FTS5 外部内容表 + 触发器同步；不可用时由 ClipStore 降级 LIKE。
        if db.hasFTS5 {
            try db.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS clip_fts USING fts5(plain_text, title, content='clip', content_rowid='id');
            CREATE TRIGGER IF NOT EXISTS clip_ai AFTER INSERT ON clip BEGIN
                INSERT INTO clip_fts(rowid, plain_text, title) VALUES (new.id, new.plain_text, new.title);
            END;
            CREATE TRIGGER IF NOT EXISTS clip_ad AFTER DELETE ON clip BEGIN
                INSERT INTO clip_fts(clip_fts, rowid, plain_text, title) VALUES ('delete', old.id, old.plain_text, old.title);
            END;
            CREATE TRIGGER IF NOT EXISTS clip_au AFTER UPDATE OF plain_text, title ON clip BEGIN
                INSERT INTO clip_fts(clip_fts, rowid, plain_text, title) VALUES ('delete', old.id, old.plain_text, old.title);
                INSERT INTO clip_fts(rowid, plain_text, title) VALUES (new.id, new.plain_text, new.title);
            END;
            """)
        }

        // v2：语义搜索向量列（float32 数组）
        if db.userVersion < 2, !columnExists(db, table: "clip", column: "embedding") {
            try db.execute("ALTER TABLE clip ADD COLUMN embedding BLOB")
        }

        // v3：FTS5 增加 title 列支持
        if db.userVersion < 3 {
            if db.hasFTS5 {
                try? db.execute("""
                DROP TRIGGER IF EXISTS clip_ai;
                DROP TRIGGER IF EXISTS clip_ad;
                DROP TRIGGER IF EXISTS clip_au;
                DROP TABLE IF EXISTS clip_fts;
                CREATE VIRTUAL TABLE IF NOT EXISTS clip_fts USING fts5(plain_text, title, content='clip', content_rowid='id');
                CREATE TRIGGER IF NOT EXISTS clip_ai AFTER INSERT ON clip BEGIN
                    INSERT INTO clip_fts(rowid, plain_text, title) VALUES (new.id, new.plain_text, new.title);
                END;
                CREATE TRIGGER IF NOT EXISTS clip_ad AFTER DELETE ON clip BEGIN
                    INSERT INTO clip_fts(clip_fts, rowid, plain_text, title) VALUES ('delete', old.id, old.plain_text, old.title);
                END;
                CREATE TRIGGER IF NOT EXISTS clip_au AFTER UPDATE OF plain_text, title ON clip BEGIN
                    INSERT INTO clip_fts(clip_fts, rowid, plain_text, title) VALUES ('delete', old.id, old.plain_text, old.title);
                    INSERT INTO clip_fts(rowid, plain_text, title) VALUES (new.id, new.plain_text, new.title);
                END;
                INSERT INTO clip_fts(rowid, plain_text, title) SELECT id, plain_text, title FROM clip;
                """)
            }
            try db.execute("PRAGMA user_version = 3;")
        }

        // v4：号码归一化键（同一号码的不同分隔符写法视为同一条，避免历史里散落多份）
        if db.userVersion < 4, !columnExists(db, table: "clip", column: "num_key") {
            try? db.execute("ALTER TABLE clip ADD COLUMN num_key TEXT")
            try? db.execute("CREATE INDEX IF NOT EXISTS idx_clip_num ON clip(num_key)")
            try db.execute("PRAGMA user_version = 4;")
        }
    }

    private static func columnExists(_ db: Database, table: String, column: String) -> Bool {
        guard let statement = try? db.prepare("PRAGMA table_info(\(table))") else { return false }
        while statement.step() {
            if statement.columnText(1) == column { return true }
        }
        return false
    }
}
