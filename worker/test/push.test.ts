import { exports } from "cloudflare:workers";
import { it } from "vitest";
import type { TodoDto, TodoPushDto } from "../src/types";

const TEST_TOKEN = "test-token";

interface PushResponseBody {
  applied: Array<{ id: string; serverSeq: number }>;
  rejected: Array<{ id: string; reason: string }>;
}

interface ChangesResponseBody {
  items: TodoDto[];
  cursor: number;
}

// Omits sortOrder unless overridden, like a client that predates N8.
function todo(overrides: Partial<TodoPushDto> & Pick<TodoPushDto, "id">): TodoPushDto {
  const now = new Date().toISOString();
  return {
    title: "Buy milk",
    notes: null,
    isDone: false,
    dueAt: null,
    recurrence: null,
    createdAt: now,
    updatedAt: now,
    isDeleted: false,
    serverSeq: 0,
    ...overrides,
  };
}

async function push(items: TodoPushDto[]) {
  return exports.default.fetch("https://example.com/push", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${TEST_TOKEN}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ items }),
  });
}

async function fetchChanges(since = 0) {
  const response = await exports.default.fetch(`https://example.com/changes?since=${since}`, {
    headers: { Authorization: `Bearer ${TEST_TOKEN}` },
  });
  return (await response.json()) as ChangesResponseBody;
}

it("accepts a new item and assigns an increasing serverSeq", async ({ expect }) => {
  const response = await push([todo({ id: "11111111-1111-1111-1111-111111111111" })]);
  expect(response.status).toBe(200);

  const body = (await response.json()) as PushResponseBody;
  expect(body.applied).toHaveLength(1);
  expect(body.applied[0]!.id).toBe("11111111-1111-1111-1111-111111111111");
  expect(body.applied[0]!.serverSeq).toBeGreaterThan(0);
});

it("assigns strictly increasing serverSeq across separate pushes", async ({ expect }) => {
  const first = await push([todo({ id: "22222222-2222-2222-2222-222222222222" })]);
  const firstBody = (await first.json()) as PushResponseBody;

  const second = await push([todo({ id: "33333333-3333-3333-3333-333333333333" })]);
  const secondBody = (await second.json()) as PushResponseBody;

  expect(secondBody.applied[0]!.serverSeq).toBeGreaterThan(firstBody.applied[0]!.serverSeq);
});

it("upserts a newer update to an existing item", async ({ expect }) => {
  const id = "44444444-4444-4444-4444-444444444444";
  const created = new Date("2026-01-01T00:00:00.000Z").toISOString();
  const updated = new Date("2026-01-02T00:00:00.000Z").toISOString();

  await push([todo({ id, title: "Original", createdAt: created, updatedAt: created })]);
  const response = await push([todo({ id, title: "Updated", createdAt: created, updatedAt: updated })]);

  const body = (await response.json()) as PushResponseBody;
  expect(body.applied.map((a) => a.id)).toContain(id);

  const changes = await fetchChanges();
  const found = changes.items.find((item) => item.id === id);
  expect(found?.title).toBe("Updated");
});

it("rejects a stale update as a no-op", async ({ expect }) => {
  const id = "55555555-5555-5555-5555-555555555555";
  const newer = new Date("2026-02-02T00:00:00.000Z").toISOString();
  const older = new Date("2026-02-01T00:00:00.000Z").toISOString();

  await push([todo({ id, title: "Newer", createdAt: older, updatedAt: newer })]);
  const response = await push([todo({ id, title: "Stale", createdAt: older, updatedAt: older })]);

  const body = (await response.json()) as PushResponseBody;
  expect(body.rejected).toContainEqual({ id, reason: "stale" });

  const changes = await fetchChanges();
  const found = changes.items.find((item) => item.id === id);
  expect(found?.title).toBe("Newer");
});

it("rejects malformed items without crashing the batch", async ({ expect }) => {
  const response = await push([{ id: "not-a-full-todo" } as unknown as TodoPushDto]);
  expect(response.status).toBe(200);

  const body = (await response.json()) as PushResponseBody;
  expect(body.rejected).toContainEqual({ id: "not-a-full-todo", reason: "invalid" });
});

const T1 = "2026-03-01T00:00:00.000Z";
const T2 = "2026-03-02T00:00:00.000Z";
const T3 = "2026-03-03T00:00:00.000Z";

async function sortOrderOf(id: string): Promise<number | undefined> {
  const changes = await fetchChanges();
  return changes.items.find((item) => item.id === id)?.sortOrder;
}

it("stores and returns a sortOrder", async ({ expect }) => {
  const id = "dddddddd-0000-0000-0000-000000000001";
  await push([todo({ id, sortOrder: 1.5 })]);
  expect(await sortOrderOf(id)).toBe(1.5);
});

it("defaults sortOrder to 0 when a new row omits it", async ({ expect }) => {
  const id = "dddddddd-0000-0000-0000-000000000002";
  await push([todo({ id })]);
  expect(await sortOrderOf(id)).toBe(0);
});

it("keeps the stored sortOrder when a newer push omits it", async ({ expect }) => {
  const id = "dddddddd-0000-0000-0000-000000000003";
  await push([todo({ id, title: "Old", createdAt: T1, updatedAt: T1, sortOrder: 5 })]);

  const response = await push([todo({ id, title: "Edited by old client", createdAt: T1, updatedAt: T2 })]);
  const body = (await response.json()) as PushResponseBody;
  expect(body.applied.map((a) => a.id)).toContain(id);

  const found = (await fetchChanges()).items.find((item) => item.id === id);
  expect(found?.title).toBe("Edited by old client");
  expect(found?.sortOrder).toBe(5);
});

it("treats an explicit null sortOrder like an omitted one", async ({ expect }) => {
  const id = "dddddddd-0000-0000-0000-000000000004";
  await push([todo({ id, createdAt: T1, updatedAt: T1, sortOrder: 7 })]);
  await push([todo({ id, createdAt: T1, updatedAt: T2, sortOrder: null })]);
  expect(await sortOrderOf(id)).toBe(7);
});

it("rejects a non-numeric sortOrder as invalid", async ({ expect }) => {
  const id = "dddddddd-0000-0000-0000-000000000005";
  const response = await push([todo({ id, sortOrder: "3" as unknown as number })]);

  const body = (await response.json()) as PushResponseBody;
  expect(body.rejected).toContainEqual({ id, reason: "invalid" });
  expect(await sortOrderOf(id)).toBeUndefined();
});

it("leaves the stored sortOrder alone when a stale push carries a different one", async ({ expect }) => {
  const id = "dddddddd-0000-0000-0000-000000000006";
  await push([todo({ id, createdAt: T1, updatedAt: T3, sortOrder: 2 })]);

  const response = await push([todo({ id, createdAt: T1, updatedAt: T1, sortOrder: 99 })]);
  const body = (await response.json()) as PushResponseBody;
  expect(body.rejected).toContainEqual({ id, reason: "stale" });
  expect(await sortOrderOf(id)).toBe(2);
});

it("lets an explicit 0 overwrite a previous non-zero sortOrder", async ({ expect }) => {
  const id = "dddddddd-0000-0000-0000-000000000007";
  await push([todo({ id, createdAt: T1, updatedAt: T1, sortOrder: 4 })]);
  await push([todo({ id, createdAt: T1, updatedAt: T2, sortOrder: 0 })]);
  expect(await sortOrderOf(id)).toBe(0);
});

it("returns 400 for a malformed request body", async ({ expect }) => {
  const response = await exports.default.fetch("https://example.com/push", {
    method: "POST",
    headers: { Authorization: `Bearer ${TEST_TOKEN}`, "content-type": "application/json" },
    body: JSON.stringify({ notItems: [] }),
  });
  expect(response.status).toBe(400);
});
