CREATE TABLE todos (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  notes TEXT,
  is_done INTEGER NOT NULL DEFAULT 0,
  due_at TEXT,
  recurrence TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  is_deleted INTEGER NOT NULL DEFAULT 0,
  server_seq INTEGER NOT NULL
);

CREATE INDEX idx_todos_server_seq ON todos(server_seq);

CREATE TABLE meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

INSERT INTO meta (key, value) VALUES ('max_server_seq', '0');
