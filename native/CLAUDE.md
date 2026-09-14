# CLAUDE.md — native/ (Swift rewrite)

This loads alongside the root `CLAUDE.md` when running `claude` from `native/`. Root working agreement (Michael runs git/deploys/signing, phase-driven sessions, surgical edits, "don't guess unknown APIs") still applies. This file only adds Swift-specific stack rules. Full plan: `Tech/todo-sync/native/swift-rewrite-plan.md` in the Obsidian vault; per-phase briefs: `Tech/todo-sync/native/phase-N*.md`.

## What this is

A from-scratch native Swift/SwiftUI rewrite of todo-sync, replacing the archived Avalonia client (`src/`, `tests/`, `Todo.slnx` at the repo root — reference only, never edited). The Cloudflare Worker + D1 backend (`worker/`) is unchanged and shared by both clients' wire protocol.

## Stack (locked)

- Swift 6, SwiftUI, one multiplatform app target (`TodoNative`) with macOS (native, not Catalyst) and iOS destinations.
- Minimums: iOS 26 / macOS 26.
- Shared logic lives in the local Swift package `TodoNativeCore` (models, store, sync, recurrence, notifications) — the app target is UI plus DI wiring only, same "no platform code in the shared layer" discipline as the Avalonia `Todo.Core` project.
- Local store: SwiftData. No Core Data, no third-party persistence.
- Sync: existing Worker + D1, existing bearer token, existing wire format (`worker/src/index.ts` / `worker/src/types.ts`) — the Worker is not changed for the Swift client.
- Reminders: native `UNUserNotificationCenter` on both platforms.
- Zero third-party dependencies. Apple frameworks only.
- Naming: everything Swift-side uses the `TodoNative` prefix (package `TodoNativeCore`, test target `TodoNativeCoreTests`, bundle id `com.aurlaw.todonative`). Nothing in `native/` is named plain `Todo`.

## Working agreement additions for native/

- **Michael creates and owns `TodoNative.xcodeproj`** (new targets, destinations, capabilities, signing) — Claude Code doesn't hand-author `.pbxproj`. Claude authors everything inside `TodoNativeCore` and the app target's Swift/SwiftUI source once the project exists.
- Claude may run `swift build` / `swift test` inside `TodoNativeCore` freely to verify the package compiles and its tests pass. Building/running the actual `TodoNative` app target (Xcode scheme, simulator, device) is normally Michael's step unless asked to verify a compile-only build via `xcodebuild`.
- Phases are `N0`-`N5`, mirroring the archived Avalonia phases 0-4 one for one (see the table in `swift-rewrite-plan.md`). Stay inside the current phase's brief.

## Gotchas

- **SwiftData's `@Model` macro reserves the exact property name `isDeleted`** — a stored property with that name silently resets to `false` on every `context.save()` (confirmed by an isolated repro: set `true`, save, read back `false`; no error, no warning). This is presumably `@Model`'s own soft-delete/tombstone bookkeeping colliding with a same-named user property. `TodoItem`'s soft-delete flag is named `isSoftDeleted` instead — never name a `@Model` property `isDeleted`.
- `Package.swift` accepts `.macOS(.v26)` / `.iOS(.v26)` platform requirements under `swift-tools-version: 6.3` (confirmed buildable with the installed Xcode 26.6 / Swift 6.3.3 toolchain) — no need to fall back to an older platform floor.
- `TodoStore` is `@MainActor` and takes a `Clock` (`protocol Clock { func now() -> Date }`, default `SystemClock`) so mutation timestamps are deterministic in tests — same purpose as the Avalonia client's `IClock`, needed because `Date.now`/`DateTimeOffset.UtcNow`-style calls aren't testable directly.
