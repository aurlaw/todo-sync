export interface Env {
  DB: D1Database;
  API_TOKEN: string;
}

/**
 * Wire contract, camelCase. Mirrors Todo.Core.Models.TodoItem minus `Dirty` (local-only).
 * `recurrence` is the client's raw JSON.Serialize(RecurrenceRule) output, PascalCase with
 * integer enums (default System.Text.Json) — the Worker never parses it, just stores/returns
 * it verbatim as an opaque string.
 */
export interface TodoDto {
  id: string;
  title: string;
  notes: string | null;
  isDone: boolean;
  dueAt: string | null;
  recurrence: string | null;
  createdAt: string;
  updatedAt: string;
  isDeleted: boolean;
  serverSeq: number;
}

export interface TodoRow {
  id: string;
  title: string;
  notes: string | null;
  is_done: number;
  due_at: string | null;
  recurrence: string | null;
  created_at: string;
  updated_at: string;
  is_deleted: number;
  server_seq: number;
}

export function rowToDto(row: TodoRow): TodoDto {
  return {
    id: row.id,
    title: row.title,
    notes: row.notes,
    isDone: row.is_done !== 0,
    dueAt: row.due_at,
    recurrence: row.recurrence,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    isDeleted: row.is_deleted !== 0,
    serverSeq: row.server_seq,
  };
}
