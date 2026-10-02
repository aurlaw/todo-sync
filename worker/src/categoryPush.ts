import type { CategoryPushDto, Env } from "./types";
import { isLowercaseUuid } from "./types";
import { nextServerSeq } from "./push";

interface PushResult {
  applied: Array<{ id: string; serverSeq: number }>;
  rejected: Array<{ id: string; reason: string }>;
}

const COLOR_PATTERN = /^#[0-9a-f]{6}$/;

// Every field is required, nullable ones as explicit null: no client predates categories. parentId is
// not checked against stored rows, and sibling name uniqueness is not enforced — both are client rules.
function isValidCategoryDto(value: unknown): value is CategoryPushDto {
  if (typeof value !== "object" || value === null) {
    return false;
  }
  const v = value as Record<string, unknown>;
  return (
    isLowercaseUuid(v.id) &&
    typeof v.name === "string" &&
    v.name.trim().length > 0 &&
    (v.parentId === null || isLowercaseUuid(v.parentId)) &&
    (v.color === null || (typeof v.color === "string" && COLOR_PATTERN.test(v.color))) &&
    typeof v.sortOrder === "number" &&
    Number.isFinite(v.sortOrder) &&
    typeof v.createdAt === "string" &&
    typeof v.updatedAt === "string" &&
    typeof v.isDeleted === "boolean"
  );
}

async function upsertCategory(db: D1Database, item: CategoryPushDto, serverSeq: number): Promise<boolean> {
  const result = await db
    .prepare(
      `INSERT INTO categories (id, name, parent_id, color, sort_order, created_at, updated_at, is_deleted, server_seq)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
       ON CONFLICT(id) DO UPDATE SET
         name = excluded.name,
         parent_id = excluded.parent_id,
         color = excluded.color,
         sort_order = excluded.sort_order,
         updated_at = excluded.updated_at,
         is_deleted = excluded.is_deleted,
         server_seq = excluded.server_seq
       WHERE excluded.updated_at > categories.updated_at`,
    )
    .bind(
      item.id,
      item.name,
      item.parentId,
      item.color,
      item.sortOrder,
      item.createdAt,
      item.updatedAt,
      item.isDeleted ? 1 : 0,
      serverSeq,
    )
    .run();

  return result.meta.changes > 0;
}

export async function handleCategoryPush(request: Request, env: Env): Promise<Response> {
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
    return new Response(JSON.stringify({ error: "expected { items: CategoryDto[] }" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  const items = (body as { items: unknown[] }).items;
  const result: PushResult = { applied: [], rejected: [] };

  for (const raw of items) {
    if (!isValidCategoryDto(raw)) {
      const id = typeof (raw as { id?: unknown })?.id === "string" ? (raw as { id: string }).id : "unknown";
      result.rejected.push({ id, reason: "invalid" });
      continue;
    }

    const serverSeq = await nextServerSeq(env.DB);
    const applied = await upsertCategory(env.DB, raw, serverSeq);

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
