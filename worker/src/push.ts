import type { Env, TodoDto } from "./types";

interface PushResult {
  applied: Array<{ id: string; serverSeq: number }>;
  rejected: Array<{ id: string; reason: string }>;
}

function isValidTodoDto(value: unknown): value is TodoDto {
  if (typeof value !== "object" || value === null) {
    return false;
  }
  const v = value as Record<string, unknown>;
  return (
    typeof v.id === "string" &&
    typeof v.title === "string" &&
    (v.notes === null || typeof v.notes === "string") &&
    typeof v.isDone === "boolean" &&
    (v.dueAt === null || typeof v.dueAt === "string") &&
    (v.recurrence === null || typeof v.recurrence === "string") &&
    typeof v.createdAt === "string" &&
    typeof v.updatedAt === "string" &&
    typeof v.isDeleted === "boolean"
  );
}

async function nextServerSeq(db: D1Database): Promise<number> {
  const row = await db
    .prepare("UPDATE meta SET value = value + 1 WHERE key = 'max_server_seq' RETURNING value")
    .first<{ value: string }>();

  if (!row) {
    throw new Error("meta row 'max_server_seq' is missing — did migrations run?");
  }

  return Number(row.value);
}

async function upsertTodo(db: D1Database, item: TodoDto, serverSeq: number): Promise<boolean> {
  const result = await db
    .prepare(
      `INSERT INTO todos (id, title, notes, is_done, due_at, recurrence, created_at, updated_at, is_deleted, server_seq)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET
         title = excluded.title,
         notes = excluded.notes,
         is_done = excluded.is_done,
         due_at = excluded.due_at,
         recurrence = excluded.recurrence,
         updated_at = excluded.updated_at,
         is_deleted = excluded.is_deleted,
         server_seq = excluded.server_seq
       WHERE excluded.updated_at > todos.updated_at`,
    )
    .bind(
      item.id,
      item.title,
      item.notes,
      item.isDone ? 1 : 0,
      item.dueAt,
      item.recurrence,
      item.createdAt,
      item.updatedAt,
      item.isDeleted ? 1 : 0,
      serverSeq,
    )
    .run();

  return result.meta.changes > 0;
}

export async function handlePush(request: Request, env: Env): Promise<Response> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid JSON body" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  if (typeof body !== "object" || body === null || !Array.isArray((body as { items?: unknown }).items)) {
    return new Response(JSON.stringify({ error: "expected { items: TodoDto[] }" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  const items = (body as { items: unknown[] }).items;
  const result: PushResult = { applied: [], rejected: [] };

  for (const raw of items) {
    if (!isValidTodoDto(raw)) {
      const id = typeof (raw as { id?: unknown })?.id === "string" ? (raw as { id: string }).id : "unknown";
      result.rejected.push({ id, reason: "invalid" });
      continue;
    }

    const serverSeq = await nextServerSeq(env.DB);
    const applied = await upsertTodo(env.DB, raw, serverSeq);

    if (applied) {
      result.applied.push({ id: raw.id, serverSeq });
    } else {
      result.rejected.push({ id: raw.id, reason: "stale" });
    }
  }

  return new Response(JSON.stringify(result), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}
