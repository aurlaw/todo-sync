import type { Env } from "./types";
import { isAuthorized, unauthorized } from "./auth";
import { handlePush } from "./push";
import { handleChanges } from "./changes";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (!isAuthorized(request, env)) {
      return unauthorized();
    }

    const url = new URL(request.url);

    if (request.method === "POST" && url.pathname === "/push") {
      return handlePush(request, env);
    }

    if (request.method === "GET" && url.pathname === "/changes") {
      return handleChanges(request, env);
    }

    return new Response(JSON.stringify({ error: "not found" }), {
      status: 404,
      headers: { "content-type": "application/json" },
    });
  },
};
