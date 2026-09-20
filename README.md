# todo-sync

A personal TODO app for one user. Native Swift/SwiftUI on macOS + iOS, offline-first SwiftData with cheap sync via a Cloudflare Worker + D1. Not distributed through any app store.

Full design decisions and phased plan: `Tech/todo-sync/native/swift-rewrite-plan.md` in the Obsidian vault (see `CLAUDE.md` for the working agreement and stack details).



## Prerequisites

- **Xcode 26 / Swift 6**, targeting iOS 26 / macOS 26 (native macOS, not Mac Catalyst)
- **Node.js + npm** — for the `worker/` project (Cloudflare Worker + D1 backend, unchanged from the Avalonia era)

## Repo layout

```
todo-sync/
  src/, tests/, Todo.slnx   archived Avalonia client — reference only, do not touch
  worker/                   Cloudflare Worker + D1 backend (TypeScript) — push/changes/auth, see below
  scripts/                  Avalonia-era publish/codesign wrappers — archived with the Avalonia client; the Swift app installs via Xcode (see N4 doc)
  native/
    CLAUDE.md               Swift-specific rules; loads alongside root CLAUDE.md when running claude from native/
    TodoNative/             Xcode project — TodoNative.xcodeproj, app target (SwiftUI views)
    TodoNativeCore/         local Swift package — models, TodoStore, ModelContainer factory,
                            Secrets/ (KeychainStore), Sync/ (wire DTOs, Iso8601, client, engine,
                            coordinator), tests
```

Full target layout (later phases) and per-phase briefs: `Tech/todo-sync/native/swift-rewrite-plan.md` and `Tech/todo-sync/native/phase-N0-scaffold.md`, `phase-N1-ios-head.md`, `phase-N2-worker-dtos.md`.

### Native app (`native/`)

```bash
# Run TodoNativeCore's tests (models, TodoStore, Keychain, wire DTOs)
cd native/TodoNativeCore && swift test

# Build/run the app — open in Xcode, or from the command line:
cd native/TodoNative
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -destination 'platform=macOS' build
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -destination 'generic/platform=iOS Simulator' build
```

The app's SwiftData store lives in the default app-support location Apple picks for its bundle id (`com.aurlaw.TodoNative`); the Keychain items use service `com.aurlaw.todonative`. Sync stays off until both the Worker URL and token are saved in Settings.

To check real Worker payloads against the DTOs, save a `GET /changes?since=0` response as `native/TodoNativeCore/Tests/TodoNativeCoreTests/Fixtures/local/changes.json` (git-ignored, never committed) and run `swift test`.

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

## Archived: Avalonia client

The original .NET/Avalonia implementation (phases 0-4: solution scaffold, iOS head, Worker sync, signing/install) is preserved for reference in `src/`, `tests/`, `Todo.slnx`, and `scripts/`. See `READMEAvalonia.md` for its full documentation. It is not built, run, or maintained going forward.
