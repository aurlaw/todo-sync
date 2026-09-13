# CLAUDE.md — todo-sync

Personal TODO app for one user. Avalonia 12 / .NET 10 on macOS and iOS, offline-first SQLite, sync through a Cloudflare Worker + D1. Full plan and decisions: `Tech/todo-sync/project-plan.md` in the Obsidian vault (Michael will paste relevant sections into briefs).

## Working agreement

- Michael runs all `git` commands, `wrangler` deploys, Apple signing, and any dashboard/provisioning work. Never commit, push, deploy, or create infrastructure.
- Claude Code authors files and may run `dotnet restore`, `dotnet build`, `dotnet test`, `npm install`, `npm test`. Nothing else without asking.
- Work is phase-driven. Each session implements one brief. Stay inside the brief's scope; if something outside it needs changing, say so and stop.
- Modifying existing code = surgical change, not a rewrite.
- When unsure about an Avalonia 12 or .NET 10 API, say so rather than guessing. Do not invent package or type names.

## Stack (locked)

- .NET 10, C# latest, nullable enabled, implicit usings on, warnings as errors.
- Avalonia 12. macOS head uses the Avalonia Native backend (not Mac Catalyst). iOS head targets `net10.0-ios`.
- `CommunityToolkit.Mvvm` for view models. No third-party Avalonia control libraries.
- `Microsoft.Data.Sqlite` with hand-written SQL. No EF Core, no Dapper.
- Worker: TypeScript, Cloudflare Workers + D1, Wrangler. No framework (no Hono etc.) unless a brief says otherwise.
- Native AOT is out of scope. No app-store distribution.

## Solution layout

```
todo-sync/
  Todo.slnx
  Directory.Build.props        shared TFM/analyzer settings
  Directory.Packages.props     central package management
  src/
    Todo.Core/         net10.0 — models, ITodoRepository, ISyncClient, INotificationScheduler,
                       ISecretStore, SyncEngine, Result<T>. NO Avalonia references.
    Todo.App/          Avalonia shared — App.axaml, views, view models, styles.
    Todo.Desktop/      net10.0 — macOS entry point, platform service implementations.
    Todo.iOS/          net10.0-ios — iOS entry point, platform service implementations.
  tests/
    Todo.Core.Tests/     xunit — repository, sync engine, recurrence.
    Todo.Desktop.Tests/  xunit — macOS-only platform code (e.g. MacFileSecretStore).
  worker/
    src/index.ts, schema.sql, wrangler.toml, package.json
```

## Engineering rules

- **Result<T> everywhere in Core.** Railway-oriented; no exceptions for expected failures (not found, conflict, network). Exceptions only for programmer errors.
- **Interfaces for every external dependency.** Repository, sync client, secret store, notification scheduler, clock (`IClock`). Platform heads supply implementations via DI in their entry point.
- **Core has zero platform or UI references.** If a Core type needs `Avalonia.*` or `UIKit`, the design is wrong.
- **Dates are UTC `DateTimeOffset`** in storage and on the wire (ISO 8601). Convert to local only in view models.
- **IDs are GUIDs generated on the client.** Never rely on the server to mint ids.
- **Soft delete only.** `IsDeleted = true` + bump `UpdatedAt`. Hard deletes happen nowhere.
- **Every local write sets `Dirty = true` and `UpdatedAt = clock.UtcNow`.** The repository enforces this, not callers.
- Logging: `Microsoft.Extensions.Logging` abstractions in Core; heads wire a console/debug provider. No Serilog in this project — keep it small.
- Tests: xunit, `FluentAssertions` not used — plain `Assert`. Test recurrence math and sync merge rules thoroughly; UI has no tests.

## Data model (summary)

`TodoItem`: `Id` GUID, `Title`, `Notes?`, `IsDone`, `DueAt?` (UTC), `Recurrence?`, `CreatedAt`, `UpdatedAt`, `IsDeleted`, `Dirty` (local only), `ServerSeq?`.

`RecurrenceRule`: `Frequency` (Daily | Weekly | Monthly), `Interval` (≥1), `DaysOfWeek?` (Weekly only). Stored as a JSON string column. Completing a recurring item advances `DueAt` to the next occurrence and resets `IsDone = false`; there is no occurrence history.

## Sync protocol (summary)

- Last-write-wins on `UpdatedAt`. Worker assigns a monotonic `server_seq` on every accepted write.
- Client: `POST /push` (dirty rows) → `GET /changes?since=<cursor>` → apply rows newer than local → clear `Dirty` → persist cursor.
- `/push` is idempotent: upsert by id, accept only if incoming `UpdatedAt` > stored.
- Triggers: app start, foreground, and ~2 s debounce after local edits. No background sync, no realtime.
- Auth: `Authorization: Bearer <token>`. Token is a Worker secret; on device it comes from `ISecretStore`. Never hard-code or log it.
- After applying a change set, call `INotificationScheduler.Reschedule(...)` so reminders match merged state.

## Reminders

- `INotificationScheduler` lives in Core. iOS implementation uses `UNUserNotificationCenter`; macOS implementation is an in-app "Overdue / Due today" section only for v1. Do not attempt native macOS notifications unless a brief asks.
- Interval-based recurrences schedule the next ~8 occurrences and reschedule on launch/foreground.

## Commands

```
dotnet build Todo.slnx
dotnet test tests/Todo.Core.Tests
dotnet build src/Todo.Desktop && dotnet run --project src/Todo.Desktop
dotnet build src/Todo.iOS -f net10.0-ios          # simulator/device builds — Michael runs, Claude may build to verify compile
dotnet build src/Todo.iOS/Todo.iOS.csproj -t:Run -p:_DeviceName=":v2:udid=<simulator-udid>"   # build+launch on a booted/bootable simulator (find udid via `xcrun simctl list devices`)
cd worker && npm install && npm test
```

## Gotchas

- Avalonia Native on macOS does not use the .NET macOS workload — no `AppKit`/`Foundation` bindings are available in `Todo.Desktop`. Don't reference `Microsoft.macOS`.
- `.NET 8` mobile workloads are gone from the .NET 10 SDK; everything mobile is `net10.0-ios`.
- Central Package Management is on: add versions in `Directory.Packages.props`, not in `.csproj` files.
- SQLite `DateTimeOffset` has no native type — store as ISO 8601 TEXT and parse with `DateTimeOffset.Parse(…, CultureInfo.InvariantCulture)`.
- D1 has no `RETURNING` guarantees across batches — read `server_seq` from the `meta` table in the same transaction rather than relying on `last_insert_rowid`.
- Never put real-looking tokens in tests, fixtures, or this file. Construct test secrets at runtime.
- Building the `AppBuilder` by hand (not via `UsePlatformDetect()`, needed here since the composition root has to inject `MainViewModel` via `AppBuilder.Configure(() => new App(...))`) means text rendering isn't wired automatically: call `.UseSkia().UseHarfBuzz()` in addition to the windowing backend (`.UseAvaloniaNative()` on macOS), or the app throws `InvalidOperationException: No text shaping system configured` on startup. `Avalonia.HarfBuzz` comes transitively via `Avalonia.Native`/`Avalonia.Desktop`, no extra package reference needed.
- The root namespace is `Todo`, and `Todo.App` is both a project/namespace and contains a class named `App`. Referencing `Todo.App.App` from another `Todo.*` namespace (e.g. `Todo.Desktop`) needs a `using AvaloniaApp = Todo.App.App;` alias — an unqualified `using Todo.App;` plus `new App(...)` resolves `App` to the namespace, not the class (CS0118).
- `Avalonia.iOS`'s `AvaloniaAppDelegate<TApp>` constrains `where TApp : Application, new()`, and a type with `required` members can't satisfy `new()` (CS9040) — so `App`'s platform-injected `MainViewModel` property is a plain (non-`required`) settable property, not constructor-injected. To actually inject it, override `CreateAppBuilder()` (not `CustomizeAppBuilder`) in the iOS `AppDelegate` and use `AppBuilder.Configure(() => new App { MainViewModel = ... })` — same factory pattern `Todo.Desktop`'s `Program.cs` already uses, since `AvaloniaAppDelegate<TApp>`'s default `CreateAppBuilder` calls `AppBuilder.Configure<TApp>()` (parameterless-only).
- iOS builds always run through IL linking, even for `dotnet build`/simulator/Debug — `PublishTrimmed=false` is rejected outright ("iOS projects must build with PublishTrimmed=true"); use `<MtouchLink>None</MtouchLink>` in `Todo.iOS.csproj` to disable trimming instead. Revisit before any App Store build (needs a `JsonSerializerContext` for `RecurrenceRule`'s JSON column to be trim-safe).
- `ISingleViewApplicationLifetime.MainView` (iOS) is the mobile analog of `IClassicDesktopStyleApplicationLifetime.MainWindow` (desktop) in `App.axaml.cs`'s `OnFrameworkInitializationCompleted`. **`Window` has no platform implementation at all on iOS's single-view host** — not just `ShowDialog<T>`'s owner requirement, but even a plain, non-modal `Window.Show()` throws (confirmed by an actual crash log: an unhandled managed exception inside `Avalonia_iOS_DispatcherImpl_CheckSignaled`, thrown from the "New" button's click handler). The edit dialog (`TodoEditDialogViewModel` + `TodoEditView`, a `UserControl`) is therefore shown as an in-view overlay driven by `MainViewModel.ActiveDialog` (an implicit `DataTemplate` in `MainView.axaml` maps it to `TodoEditView`, shown/hidden via an `IsVisible` binding), not a separate `Window`, on both platforms. Don't reach for `Window`/`ShowDialog` for any future dialog in this app — it doesn't work on iOS at all.
- Real device Keychain entitlements (`keychain-access-groups` etc.) aren't set up yet — `IosKeychainSecretStore` is unverified beyond compiling; simulator generic-password Keychain access typically doesn't need special entitlements, but confirm when Phase 3 actually exercises it.
- App icon: master art is `_appicon/appIcon_1024.png` (1024×1024, no alpha) — never hand-edit derived files. iOS: `src/Todo.iOS/Assets.xcassets/AppIcon.appiconset/icon-1024.png` + `<AppIcon>AppIcon</AppIcon>` in `Todo.iOS.csproj` (the iOS SDK auto-globs `**/*.xcassets` into `ImageAsset` items — confirmed in `Microsoft.iOS.Sdk.DefaultItems.props` — but the `$(AppIcon)` MSBuild property must still be set or `actool` never runs and `Assets.car` never gets compiled into the bundle). macOS: `.NET` has no built-in app-bundle project type outside Mac Catalyst, so `Todo.Desktop.csproj` has a `CreateMacOSAppBundle` post-build target that assembles `Todo.app/Contents/{MacOS,Resources}` from `Info.plist` + `_appicon/AppIcon.icns` (built via `_appicon/make-icns.sh`) — `dotnet run`/the plain executable skips this and shows the generic icon, which is expected; only `open bin/.../Todo.app` shows the real one.
