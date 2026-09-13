# todo-sync

A personal TODO app for one user. Avalonia 12 / .NET 10, macOS + iOS, offline-first SQLite with cheap sync via a Cloudflare Worker + D1. Not distributed through any app store.

Full design decisions and phased plan: `Tech/todo-sync/project-plan.md` in the Obsidian vault (see `CLAUDE.md` for the working agreement and stack details).

## Status

**Phase 2** is implemented and deployed: a Cloudflare Worker + D1 backend (`worker/`) with `POST /push` (idempotent, last-write-wins upsert) and `GET /changes?since=` (cursor-based pull), bearer-token auth. The .NET client doesn't talk to it yet — that's Phase 3 (`ISyncClient`/`SyncEngine`). No client-side sync, no reminders yet — see the phase table below.

| Phase | Scope |
|---|---|
| 0 ✅ | Solution scaffold, Core models, SQLite repo, macOS head (list/add/edit/complete/delete) |
| 1 ✅ | iOS head, shared-view split, per-platform secret storage |
| 2 ✅ | Cloudflare Worker + D1 sync backend — deployed |
| 3 | Sync engine (push/pull, conflict handling) |
| 4 | Reminders (recurrence, notifications) |
| 5 | Signing + install workflow |

## Prerequisites

- **.NET 10 SDK** (`dotnet --version` → `10.0.100` or later) with the **`ios` workload** (`dotnet workload install ios`) for the iOS head
- **macOS + Xcode** to build/run either head — `Todo.Desktop` uses the Avalonia Native backend (not Mac Catalyst); `Todo.iOS` needs Xcode's iOS SDK/simulators
- **Node.js + npm** — for the `worker/` project (Cloudflare Worker + D1 backend)

## Solution layout

```
todo-sync/
  Todo.slnx
  src/
    Todo.Core/       models, ITodoRepository, ISecretStore, SqliteTodoRepository — no Avalonia references
    Todo.App/         shared Avalonia UI (MainView + dialogs, view models)
    Todo.Desktop/     macOS entry point, MacFileSecretStore
    Todo.iOS/         iOS entry point, IosKeychainSecretStore
  tests/
    Todo.Core.Tests/     xunit tests for Core
    Todo.Desktop.Tests/  xunit tests for macOS-only platform code
  worker/            Cloudflare Worker + D1 backend (TypeScript) — push/changes/auth, see below
```

## Commands

```bash
# Restore + build everything
dotnet build Todo.slnx

# Run the test suites
dotnet test tests/Todo.Core.Tests
dotnet test tests/Todo.Desktop.Tests

# Run the macOS app (fast dev loop — no app bundle, generic Dock icon)
dotnet build src/Todo.Desktop && dotnet run --project src/Todo.Desktop

# Run the macOS app as a real .app bundle (shows the actual Dock icon)
dotnet build src/Todo.Desktop && open src/Todo.Desktop/bin/Debug/net10.0/Todo.app

# Build + launch the iOS app on a simulator (find a udid via `xcrun simctl list devices`)
dotnet build src/Todo.iOS/Todo.iOS.csproj -t:Run -p:_DeviceName=":v2:udid=<simulator-udid>"
```

The macOS app stores its SQLite database at `~/Library/Application Support/todo-sync/todo.db`; the iOS app stores it in its sandboxed Documents directory.

### Worker (`worker/`)

```bash
cd worker
npm install
npm run typecheck
npm test                                    # local D1 via @cloudflare/vitest-plugin, no account needed
npx wrangler d1 migrations apply DB --local  # sanity-check migrations/*.sql outside the test harness
```

Deploying is a manual, account-touching process — not run by Claude Code:

```bash
wrangler d1 create todo-sync            # paste the returned database_id into wrangler.toml
wrangler d1 migrations apply DB --remote
wrangler secret put API_TOKEN           # any random high-entropy string, e.g. `openssl rand -hex 32`
wrangler deploy
```
