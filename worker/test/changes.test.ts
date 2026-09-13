import { exports } from "cloudflare:workers";
import { it } from "vitest";
import type { TodoDto } from "../src/types";

const TEST_TOKEN = "test-token";

interface PushResponseBody {
  applied: Array<{ id: string; serverSeq: number }>;
}

interface ChangesResponseBody {
  items: TodoDto[];
  cursor: number;
}

function todo(id: string): TodoDto {
  const now = new Date().toISOString();
  return {
    id,
    title: `Item ${id}`,
    notes: null,
    isDone: false,
    dueAt: null,
    recurrence: null,
    createdAt: now,
    updatedAt: now,
    isDeleted: false,
    serverSeq: 0,
  };
}

async function push(items: TodoDto[]): Promise<PushResponseBody> {
  const response = await exports.default.fetch("https://example.com/push", {
    method: "POST",
    headers: { Authorization: `Bearer ${TEST_TOKEN}`, "content-type": "application/json" },
    body: JSON.stringify({ items }),
  });
  return (await response.json()) as PushResponseBody;
}

async function changes(query: string): Promise<ChangesResponseBody> {
  const response = await exports.default.fetch(`https://example.com/changes${query}`, {
    headers: { Authorization: `Bearer ${TEST_TOKEN}` },
  });
  return (await response.json()) as ChangesResponseBody;
}

it("returns only rows after the given cursor", async ({ expect }) => {
  const a = await push([todo("aaaaaaaa-0000-0000-0000-000000000001")]);
  const b = await push([todo("aaaaaaaa-0000-0000-0000-000000000002")]);

  const result = await changes(`?since=${a.applied[0]!.serverSeq}`);
  const ids = result.items.map((item) => item.id);

  expect(ids).not.toContain("aaaaaaaa-0000-0000-0000-000000000001");
  expect(ids).toContain("aaaaaaaa-0000-0000-0000-000000000002");
  expect(result.cursor).toBe(b.applied[0]!.serverSeq);
});

it("orders rows ascending by serverSeq", async ({ expect }) => {
  await push([todo("bbbbbbbb-0000-0000-0000-000000000001")]);
  await push([todo("bbbbbbbb-0000-0000-0000-000000000002")]);
  await push([todo("bbbbbbbb-0000-0000-0000-000000000003")]);

  const result = await changes("?since=0");
  const seqs = result.items.map((item) => item.serverSeq);
  const sorted = [...seqs].sort((x, y) => x - y);

  expect(seqs).toEqual(sorted);
});

it("respects the limit parameter and returns a cursor to continue from", async ({ expect }) => {
  await push([todo("cccccccc-0000-0000-0000-000000000001")]);
  await push([todo("cccccccc-0000-0000-0000-000000000002")]);
  await push([todo("cccccccc-0000-0000-0000-000000000003")]);

  const page = await changes("?since=0&limit=2");
  expect(page.items).toHaveLength(2);
  expect(page.cursor).toBe(page.items[1]!.serverSeq);
});

it("keeps the cursor unchanged when there are no new rows", async ({ expect }) => {
  const result = await changes("?since=999999");
  expect(result.items).toHaveLength(0);
  expect(result.cursor).toBe(999999);
});

it("returns 400 for a negative since value", async ({ expect }) => {
  const response = await exports.default.fetch("https://example.com/changes?since=-1", {
    headers: { Authorization: `Bearer ${TEST_TOKEN}` },
  });
  expect(response.status).toBe(400);
});
