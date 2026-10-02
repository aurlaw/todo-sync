import type { CategoryRow, Env } from "./types";
import { categoryRowToDto } from "./types";

const DEFAULT_LIMIT = 500;
const MAX_LIMIT = 500;

export async function handleCategoryChanges(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);

  const sinceParam = url.searchParams.get("since");
  const since = sinceParam !== null ? Number(sinceParam) : 0;
  if (!Number.isFinite(since) || since < 0) {
    return new Response(JSON.stringify({ error: "'since' must be a non-negative number" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  const limitParam = url.searchParams.get("limit");
  const limit = limitParam !== null ? Math.min(Number(limitParam), MAX_LIMIT) : DEFAULT_LIMIT;
  if (!Number.isFinite(limit) || limit <= 0) {
    return new Response(JSON.stringify({ error: "'limit' must be a positive number" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  const { results } = await env.DB.prepare(
    `SELECT id, name, parent_id, color, sort_order, created_at, updated_at, is_deleted, server_seq
     FROM categories
     WHERE server_seq > ?
     ORDER BY server_seq ASC
     LIMIT ?`,
  )
    .bind(since, limit)
    .all<CategoryRow>();

  const items = results.map(categoryRowToDto);
  const cursor = items.length > 0 ? items[items.length - 1]!.serverSeq : since;

  return new Response(JSON.stringify({ items, cursor }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}
