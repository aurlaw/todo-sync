# todo-sync

A personal TODO app for one user. Native Swift/SwiftUI on macOS + iOS, offline-first SwiftData with cheap sync via a Cloudflare Worker + D1. Not distributed through any app store.

Full design decisions and phased plan: `Tech/todo-sync/native/swift-rewrite-plan.md` in the Obsidian vault (see `CLAUDE.md` for the working agreement and stack details).

## Status

**Rewrite in progress.** The original Avalonia/.NET client (phases 0-4, see `READMEAvalonia.md`) was judged not good enough on the UI front and is now archived — kept in `src/`, `tests/`, `Todo.slnx` for reference, not run or maintained. The app is being rebuilt from scratch as a pure-Swift, fully native client under `native/`. The Cloudflare Worker + D1 backend and its wire protocol are unchanged and carry forward as-is.

**N0** is implemented and confirmed working: `TodoNativeCore` (SwiftData model, `TodoStore`, tests) plus a macOS SwiftUI app (list/add/edit/complete/delete via `TodoNative.xcodeproj`).

| Phase | Scope |
|---|---|
| N0 ✅ | Xcode scaffold, `TodoNativeCore` package, SwiftData model, macOS head (list/add/edit/complete/delete) |
| N1 | iOS head, adaptive layout, Keychain secret storage, Settings screen |
| N2 | Swift DTOs against the existing Worker JSON — no Worker changes |
| N3 | Sync engine (push/pull, conflict handling) |
| N4 | Signing + install workflow |
| N5 | Reminders (recurrence, `UNUserNotificationCenter`) |

## Prerequisites

- **Xcode 26 / Swift 6**, targeting iOS 26 / macOS 26 (native macOS, not Mac Catalyst)
- **Node.js + npm** — for the `worker/` project (Cloudflare Worker + D1 backend, unchanged from the Avalonia era)

## Repo layout

```
todo-sync/
  src/, tests/, Todo.slnx   archived Avalonia client — reference only, do not touch
  worker/                   Cloudflare Worker + D1 backend (TypeScript) — push/changes/auth, see below
  scripts/                  Avalonia-era publish/codesign wrappers — superseded once native/ has its own signing workflow (N4)
  native/
    CLAUDE.md               Swift-specific rules; loads alongside root CLAUDE.md when running claude from native/
    TodoNative/             Xcode project — TodoNative.xcodeproj, app target (SwiftUI views)
    TodoNativeCore/         local Swift package — models, TodoStore, ModelContainer factory, tests
```

Full target layout (later phases) documented in `Tech/todo-sync/native/swift-rewrite-plan.md` and `Tech/todo-sync/native/phase-N0-scaffold.md`.

### Native app (`native/`)

```bash
# Run TodoNativeCore's tests (models, TodoStore mutation rules)
cd native/TodoNativeCore && swift test

# Build/run the app — open in Xcode, or from the command line:
cd native/TodoNative
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -destination 'platform=macOS' build
```

The macOS app's SwiftData store lives in the default app-support location Apple picks for the app's bundle id (`com.aurlaw.todonative`). No sync yet — everything is local-only until N3.

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
