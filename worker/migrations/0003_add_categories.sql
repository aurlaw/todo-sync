-- N9a: categories. Additive only. No foreign keys: tree rules and orphan handling live on the client.
CREATE TABLE categories (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  parent_id TEXT,
  color TEXT,
  sort_order REAL NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  is_deleted INTEGER NOT NULL DEFAULT 0,
  server_seq INTEGER NOT NULL
);

CREATE INDEX idx_categories_server_seq ON categories(server_seq);

-- NULL means the virtual Unassigned category, which has no row.
ALTER TABLE todos ADD COLUMN category_id TEXT;
