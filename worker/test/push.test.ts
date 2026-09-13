import { exports } from "cloudflare:workers";
import { it } from "vitest";
import type { TodoDto } from "../src/types";

const TEST_TOKEN = "test-token";

interface PushResponseBody {
  applied: Array<{ id: string; serverSeq: number }>;
  rejected: Array<{ id: string; reason: string }>;
}

interface ChangesResponseBody {
  items: TodoDto[];
  cursor: number;
}

function todo(overrides: Partial<TodoDto> & Pick<TodoDto, "id">): TodoDto {
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

async function push(items: TodoDto[]) {
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
  const response = await push([{ id: "not-a-full-todo" } as unknown as TodoDto]);
  expect(response.status).toBe(200);

  const body = (await response.json()) as PushResponseBody;
  expect(body.rejected).toContainEqual({ id: "not-a-full-todo", reason: "invalid" });
});

it("returns 400 for a malformed request body", async ({ expect }) => {
  const response = await exports.default.fetch("https://example.com/push", {
    method: "POST",
    headers: { Authorization: `Bearer ${TEST_TOKEN}`, "content-type": "application/json" },
    body: JSON.stringify({ notItems: [] }),
  });
  expect(response.status).toBe(400);
});
