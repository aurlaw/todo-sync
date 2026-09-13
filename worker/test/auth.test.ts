import { exports } from "cloudflare:workers";
import { it } from "vitest";

const TEST_TOKEN = "test-token";

it("rejects requests with no Authorization header", async ({ expect }) => {
  const response = await exports.default.fetch("https://example.com/changes");
  expect(response.status).toBe(401);
});

it("rejects requests with the wrong bearer token", async ({ expect }) => {
  const response = await exports.default.fetch("https://example.com/changes", {
    headers: { Authorization: "Bearer wrong-token" },
  });
  expect(response.status).toBe(401);
});

it("accepts requests with the correct bearer token", async ({ expect }) => {
  const response = await exports.default.fetch("https://example.com/changes", {
    headers: { Authorization: `Bearer ${TEST_TOKEN}` },
  });
  expect(response.status).toBe(200);
});
