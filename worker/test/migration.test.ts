import { env } from "cloudflare:workers";
import { it } from "vitest";
import type { Env } from "../src/types";

const db = (env as unknown as Env).DB;

// The setup file has already applied every migration to this file's fresh local DB.
it("reads category_id as null for a todo inserted without one", async ({ expect }) => {
  const id = "99999999-0000-0000-0000-000000000001";
  await db
    .prepare(
      `INSERT INTO todos (id, title, created_at, updated_at, server_seq)
       VALUES (?, 'Pre-N9 row', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', 1)`,
    )
    .bind(id)
    .run();

  const row = await db.prepare("SELECT category_id FROM todos WHERE id = ?").bind(id).first<{ category_id: string | null }>();
  expect(row).toEqual({ category_id: null });
});

it("creates an empty categories table", async ({ expect }) => {
  const row = await db.prepare("SELECT COUNT(*) AS n FROM categories").first<{ n: number }>();
  expect(row?.n).toBe(0);
});
