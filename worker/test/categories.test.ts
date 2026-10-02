import { exports } from "cloudflare:workers";
import { it } from "vitest";
import type { CategoryDto, CategoryPushDto, TodoPushDto } from "../src/types";

const TEST_TOKEN = "test-token";

interface PushResponseBody {
  applied: Array<{ id: string; serverSeq: number }>;
  rejected: Array<{ id: string; reason: string }>;
}

interface ChangesResponseBody {
  items: CategoryDto[];
  cursor: number;
}

const T1 = "2026-03-01T00:00:00.000Z";
const T2 = "2026-03-02T00:00:00.000Z";
const T3 = "2026-03-03T00:00:00.000Z";

function category(overrides: Partial<CategoryPushDto> & Pick<CategoryPushDto, "id">): CategoryPushDto {
  return {
    name: "Work",
    parentId: null,
    color: null,
    sortOrder: 0,
    createdAt: T1,
    updatedAt: T1,
    isDeleted: false,
    ...overrides,
  };
}

async function post(path: string, items: unknown[]): Promise<PushResponseBody> {
  const response = await exports.default.fetch(`https://example.com${path}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${TEST_TOKEN}`, "content-type": "application/json" },
    body: JSON.stringify({ items }),
  });
  return (await response.json()) as PushResponseBody;
}

function push(items: unknown[]): Promise<PushResponseBody> {
  return post("/categories/push", items);
}

async function changes(query = "?since=0"): Promise<ChangesResponseBody> {
  const response = await exports.default.fetch(`https://example.com/categories/changes${query}`, {
    headers: { Authorization: `Bearer ${TEST_TOKEN}` },
  });
  return (await response.json()) as ChangesResponseBody;
}

async function stored(id: string): Promise<CategoryDto[]> {
  return (await changes()).items.filter((item) => item.id === id);
}

it("returns a pushed category with every field", async ({ expect }) => {
  const parentId = "a0000000-0000-4000-8000-000000000001";
  const id = "a0000000-0000-4000-8000-000000000002";
  await push([category({ id: parentId })]);

  const body = await push([
    category({ id, name: "Errands", parentId, color: "#1a2b3c", sortOrder: 2.5, createdAt: T1, updatedAt: T2 }),
  ]);
  expect(body.rejected).toHaveLength(0);
  expect(body.applied).toHaveLength(1);

  expect(await stored(id)).toEqual([
    {
      id,
      name: "Errands",
      parentId,
      color: "#1a2b3c",
      sortOrder: 2.5,
      createdAt: T1,
      updatedAt: T2,
      isDeleted: false,
      serverSeq: body.applied[0]!.serverSeq,
    },
  ]);
});

it("stores the name as sent, without trimming", async ({ expect }) => {
  const id = "a0000000-0000-4000-8000-000000000003";
  await push([category({ id, name: "  Padded  " })]);
  expect((await stored(id))[0]?.name).toBe("  Padded  ");
});

it("rejects an older updatedAt and replaces on a newer one", async ({ expect }) => {
  const id = "b0000000-0000-4000-8000-000000000001";
  await push([category({ id, name: "Second", color: "#111111", updatedAt: T2 })]);

  const stale = await push([category({ id, name: "First", color: "#222222", updatedAt: T1 })]);
  expect(stale.applied).toHaveLength(0);
  expect(stale.rejected).toEqual([{ id, reason: "stale" }]);
  expect(await stored(id)).toMatchObject([{ name: "Second", color: "#111111", updatedAt: T2 }]);

  const newer = await push([category({ id, name: "Third", color: null, sortOrder: 9, updatedAt: T3 })]);
  expect(newer.applied.map((a) => a.id)).toEqual([id]);
  expect(await stored(id)).toMatchObject([
    { name: "Third", color: null, sortOrder: 9, updatedAt: T3, serverSeq: newer.applied[0]!.serverSeq },
  ]);
});

it("is idempotent: the same push twice yields one row and no error", async ({ expect }) => {
  const id = "b0000000-0000-4000-8000-000000000002";
  const first = await push([category({ id })]);
  const second = await push([category({ id })]);

  expect(first.applied.map((a) => a.id)).toEqual([id]);
  expect(second.rejected).toEqual([{ id, reason: "stale" }]);

  const rows = await stored(id);
  expect(rows).toHaveLength(1);
  expect(rows[0]!.serverSeq).toBe(first.applied[0]!.serverSeq);
});

it("round-trips a soft delete", async ({ expect }) => {
  const id = "b0000000-0000-4000-8000-000000000003";
  await push([category({ id, updatedAt: T1 })]);
  await push([category({ id, updatedAt: T2, isDeleted: true })]);
  expect(await stored(id)).toMatchObject([{ isDeleted: true, updatedAt: T2 }]);
});

it("accepts a parentId that points at a missing or deleted category", async ({ expect }) => {
  const deletedParent = "c0000000-0000-4000-8000-000000000001";
  const neverPushed = "c0000000-0000-4000-8000-000000000002";
  const childOfDeleted = "c0000000-0000-4000-8000-000000000003";
  const childOfMissing = "c0000000-0000-4000-8000-000000000004";
  await push([category({ id: deletedParent, isDeleted: true })]);

  const body = await push([
    category({ id: childOfDeleted, parentId: deletedParent }),
    category({ id: childOfMissing, parentId: neverPushed }),
  ]);

  expect(body.rejected).toHaveLength(0);
  expect((await stored(childOfDeleted))[0]?.parentId).toBe(deletedParent);
  expect((await stored(childOfMissing))[0]?.parentId).toBe(neverPushed);
});

it("rejects invalid categories without crashing the batch", async ({ expect }) => {
  const base = "d0000000-0000-4000-8000-00000000000";
  const good = `${base}0`;
  const { parentId: _parentId, ...noParentKey } = category({ id: `${base}5` });

  const invalid: unknown[] = [
    category({ id: `${base}1`, name: "" }),
    category({ id: `${base}2`, name: "   " }),
    category({ id: `${base}3`, color: "#1A2B3C" }),
    category({ id: `${base}4`, color: "1a2b3c" }),
    noParentKey,
    category({ id: `${base}6`, isDeleted: 1 as unknown as boolean }),
    category({ id: `${base}7`, parentId: `${base}0`.toUpperCase() }),
    category({ id: `${base}8`, sortOrder: "1" as unknown as number }),
    category({ id: `${base}9`.toUpperCase() }),
    "not an object",
  ];

  const body = await push([...invalid, category({ id: good })]);

  expect(body.applied.map((a) => a.id)).toEqual([good]);
  expect(body.rejected).toEqual([
    { id: `${base}1`, reason: "invalid" },
    { id: `${base}2`, reason: "invalid" },
    { id: `${base}3`, reason: "invalid" },
    { id: `${base}4`, reason: "invalid" },
    { id: `${base}5`, reason: "invalid" },
    { id: `${base}6`, reason: "invalid" },
    { id: `${base}7`, reason: "invalid" },
    { id: `${base}8`, reason: "invalid" },
    { id: `${base}9`.toUpperCase(), reason: "invalid" },
    { id: "unknown", reason: "invalid" },
  ]);

  const ids = (await changes()).items.map((item) => item.id);
  for (const rejected of body.rejected) {
    expect(ids).not.toContain(rejected.id);
  }
});

it("pages: a full page, then the rest from the last serverSeq", async ({ expect }) => {
  const start = (await changes()).cursor;
  const ids = [
    "e0000000-0000-4000-8000-000000000001",
    "e0000000-0000-4000-8000-000000000002",
    "e0000000-0000-4000-8000-000000000003",
  ];
  await push(ids.map((id) => category({ id })));

  const first = await changes(`?since=${start}&limit=2`);
  expect(first.items.map((item) => item.id)).toEqual(ids.slice(0, 2));
  expect(first.cursor).toBe(first.items[1]!.serverSeq);

  const second = await changes(`?since=${first.cursor}&limit=2`);
  expect(second.items.map((item) => item.id)).toEqual(ids.slice(2));
  expect(second.cursor).toBe(second.items[0]!.serverSeq);

  const done = await changes(`?since=${second.cursor}&limit=2`);
  expect(done.items).toHaveLength(0);
  expect(done.cursor).toBe(second.cursor);
});

it("draws todo and category serverSeq values from one increasing counter", async ({ expect }) => {
  const todo = (id: string): TodoPushDto => ({
    id,
    title: "Interleaved",
    notes: null,
    isDone: false,
    dueAt: null,
    recurrence: null,
    createdAt: T1,
    updatedAt: T1,
    isDeleted: false,
    serverSeq: 0,
  });

  const seqs: number[] = [];
  seqs.push((await post("/push", [todo("f0000000-0000-4000-8000-000000000001")])).applied[0]!.serverSeq);
  seqs.push((await push([category({ id: "f0000000-0000-4000-8000-000000000002" })])).applied[0]!.serverSeq);
  seqs.push((await post("/push", [todo("f0000000-0000-4000-8000-000000000003")])).applied[0]!.serverSeq);
  seqs.push((await push([category({ id: "f0000000-0000-4000-8000-000000000004" })])).applied[0]!.serverSeq);

  for (let i = 1; i < seqs.length; i++) {
    expect(seqs[i]!).toBeGreaterThan(seqs[i - 1]!);
  }
  expect(new Set(seqs).size).toBe(seqs.length);
});

it("returns 400 for a malformed request body", async ({ expect }) => {
  const response = await exports.default.fetch("https://example.com/categories/push", {
    method: "POST",
    headers: { Authorization: `Bearer ${TEST_TOKEN}`, "content-type": "application/json" },
    body: JSON.stringify({ notItems: [] }),
  });
  expect(response.status).toBe(400);
});

it("returns 400 for a negative since value", async ({ expect }) => {
  const response = await exports.default.fetch("https://example.com/categories/changes?since=-1", {
    headers: { Authorization: `Bearer ${TEST_TOKEN}` },
  });
  expect(response.status).toBe(400);
});
