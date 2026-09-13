import type { Env } from "./types";

const BEARER_PREFIX = "Bearer ";

export function isAuthorized(request: Request, env: Env): boolean {
  const header = request.headers.get("Authorization");
  if (!header || !header.startsWith(BEARER_PREFIX)) {
    return false;
  }

  const token = header.slice(BEARER_PREFIX.length);
  return token === env.API_TOKEN;
}

export function unauthorized(): Response {
  return new Response(JSON.stringify({ error: "unauthorized" }), {
    status: 401,
    headers: { "content-type": "application/json" },
  });
}
