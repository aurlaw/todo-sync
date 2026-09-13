import { applyD1Migrations } from "cloudflare:test";
import { env } from "cloudflare:workers";
import type { Env } from "../src/types";

interface TestEnv extends Env {
  TEST_MIGRATIONS: unknown;
}

const testEnv = env as unknown as TestEnv;

// Setup files run outside per-test-file storage isolation and may run more than
// once; applyD1Migrations() only applies migrations that haven't already been
// applied, so calling it here is safe.
await applyD1Migrations(testEnv.DB, testEnv.TEST_MIGRATIONS as never);
