import path from "node:path";
import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig(async () => {
  // Read all migrations in the `migrations` directory so they can be applied
  // to the isolated local D1 instance before tests run.
  const migrationsPath = path.join(import.meta.dirname, "migrations");
  const migrations = await readD1Migrations(migrationsPath);

  return {
    plugins: [
      cloudflareTest({
        wrangler: {
          configPath: "./wrangler.toml",
        },
        miniflare: {
          bindings: {
            // Test-only binding so the migrations can be applied in a setup file.
            TEST_MIGRATIONS: migrations,
            // Fixed token for tests — never a real secret.
            API_TOKEN: "test-token",
          },
        },
      }),
    ],
    test: {
      setupFiles: ["./test/apply-migrations.ts"],
    },
  };
});
