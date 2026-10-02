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
  /** Manual list order, ascending. Always present on output. */
  sortOrder: number;
  /** Category link. Always present on output; null is the virtual Unassigned category. */
  categoryId: string | null;
}

/**
 * What `/push` accepts. Same as `TodoDto` except `sortOrder` is optional: clients that predate N8
 * omit it (or send null), and the Worker then keeps the stored value instead of resetting it.
 * `categoryId` is optional too, but there null and missing differ: clients that predate N9b omit
 * the key and the stored value is kept, while an explicit null moves the item to Unassigned.
 */
export type TodoPushDto = Omit<TodoDto, "sortOrder" | "categoryId"> & {
  sortOrder?: number | null;
  categoryId?: string | null;
};

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
  sort_order: number;
  category_id: string | null;
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
    sortOrder: row.sort_order,
    categoryId: row.category_id,
  };
}

/** Wire contract for categories, camelCase. One level of nesting via `parentId`; the Worker only stores it. */
export interface CategoryDto {
  id: string;
  name: string;
  parentId: string | null;
  /** `#rrggbb`, lowercase. */
  color: string | null;
  sortOrder: number;
  createdAt: string;
  updatedAt: string;
  isDeleted: boolean;
  serverSeq: number;
}

/** What `/categories/push` accepts: every field but the server-assigned `serverSeq`, all required. */
export type CategoryPushDto = Omit<CategoryDto, "serverSeq">;

export interface CategoryRow {
  id: string;
  name: string;
  parent_id: string | null;
  color: string | null;
  sort_order: number;
  created_at: string;
  updated_at: string;
  is_deleted: number;
  server_seq: number;
}

export function categoryRowToDto(row: CategoryRow): CategoryDto {
  return {
    id: row.id,
    name: row.name,
    parentId: row.parent_id,
    color: row.color,
    sortOrder: row.sort_order,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    isDeleted: row.is_deleted !== 0,
    serverSeq: row.server_seq,
  };
}

const LOWERCASE_UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export function isLowercaseUuid(value: unknown): value is string {
  return typeof value === "string" && LOWERCASE_UUID_PATTERN.test(value);
}
