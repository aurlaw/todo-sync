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
    Todo.App/          Avalonia shared — App.axaml, views (MainView, TodoEditView, SettingsView), view models, styles.
    Todo.Desktop/      net10.0 — macOS entry point, platform service implementations.
    Todo.iOS/          net10.0-ios — iOS entry point, platform service implementations.
  tests/
    Todo.Core.Tests/     xunit — repository, sync engine, recurrence.
    Todo.Desktop.Tests/  xunit — macOS-only platform code (e.g. MacFileSecretStore).
  worker/
    src/index.ts, src/{auth,push,changes,types}.ts, migrations/0001_init.sql, wrangler.toml, package.json
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

- **Deployed Worker base URL: `https://todo-sync-worker.aurlaw.dev`** (custom domain, not the default `*.workers.dev` URL). This is `SyncSettings.DefaultBaseUrl` — the fallback `HttpSyncClient` uses when nothing is configured. The actual base URL is user-editable via the Settings overlay (`SecretKeys.SyncBaseUrl`, stored in `ISecretStore` alongside the token) so it can be pointed at a different Worker (e.g. local dev) without a rebuild. `HttpSyncClient` re-resolves both the token and the base URL fresh on every request — no `HttpClient.BaseAddress` is set in the composition roots anymore, `HttpSyncClient` always builds an absolute request URI itself.
- Last-write-wins on `UpdatedAt`. Worker assigns a monotonic `server_seq` on every accepted write.
- Client: `POST /push` (dirty rows) → `GET /changes?since=<cursor>` → apply rows newer than local → clear `Dirty` → persist cursor.
- `/push` is idempotent: upsert by id, accept only if incoming `UpdatedAt` > stored.
- Triggers (Phase 3): app start and a ~2 s debounce after local edits. **Not** foreground/resume — `Avalonia.Controls.ApplicationLifetimes.IActivatableLifetime` is confirmed broken on both macOS and iOS via Avalonia's own GitHub issues (#16875, #17561, #16403), so it's deliberately unused; revisit if a reliable per-platform hook ever exists.
- Auth: `Authorization: Bearer <token>`. Token is a Worker secret; on device it comes from `ISecretStore` (set via the in-app Settings overlay — `SettingsViewModel`/`SettingsView.axaml`). Never hard-code or log it.
- After applying a change set, call `INotificationScheduler.Reschedule(...)` so reminders match merged state. **Not implemented yet** — `INotificationScheduler` doesn't exist until Phase 4.

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
cd worker && npm run typecheck
cd worker && npx wrangler d1 migrations apply DB --local   # sanity-checks migrations/*.sql outside the test harness, no account needed
```

Michael-only, account-touching (never run by Claude): `wrangler d1 create todo-sync` (paste the returned `database_id` into `worker/wrangler.toml`), `wrangler d1 migrations apply DB --remote`, `wrangler secret put API_TOKEN`, `wrangler deploy`.

## Gotchas

- Avalonia Native on macOS does not use the .NET macOS workload — no `AppKit`/`Foundation` bindings are available in `Todo.Desktop`. Don't reference `Microsoft.macOS`.
- `.NET 8` mobile workloads are gone from the .NET 10 SDK; everything mobile is `net10.0-ios`.
- Central Package Management is on: add versions in `Directory.Packages.props`, not in `.csproj` files.
- SQLite `DateTimeOffset` has no native type — store as ISO 8601 TEXT and parse with `DateTimeOffset.Parse(…, CultureInfo.InvariantCulture)`.
- D1 has no `RETURNING` guarantees across batches — read `server_seq` from the `meta` table in the same transaction rather than relying on `last_insert_rowid`. Concretely (`worker/src/push.ts`): `db.batch()` runs a pre-built array of already-bound statements atomically, but a later statement can't use a value computed by an earlier one in the same batch — so `server_seq` assignment is **one single-statement `UPDATE meta SET value = value + 1 WHERE key = 'max_server_seq' RETURNING value`** per row (RETURNING is reliable for a single statement), followed by a separate `INSERT ... ON CONFLICT DO UPDATE ... WHERE excluded.updated_at > todos.updated_at` upsert using that value. A rejected (stale) push still consumes a sequence number — a harmless gap, not a bug.
- Worker JSON wire contract is **camelCase** (`worker/src/types.ts`'s `TodoDto`), which matches neither D1's snake_case columns nor the client's default PascalCase `System.Text.Json` output (`SqliteTodoRepository.cs` serializes `RecurrenceRule` with zero custom converters — PascalCase properties, integer enums). The Worker treats `recurrence` as an **opaque JSON string**, never parsing it. `Todo.Core/HttpSyncClient.cs`'s private `TodoWireDto` handles the camelCase mapping via `[JsonPropertyName]`; `recurrence` is passed through completely unchanged (never re-parsed/re-shaped) — its value is whatever `SqliteTodoRepository` already produced.
- Date fields on the wire (`HttpSyncClient`'s `TodoWireDto`) are plain `string`, not `DateTimeOffset` — System.Text.Json's own `DateTimeOffset` converter isn't guaranteed to match the exact `"O"`-format string both `SqliteTodoRepository`'s local upsert and the Worker's `push.ts` upsert rely on for their `WHERE excluded.updated_at > todos.updated_at` string comparison. `Todo.Core/Iso8601.cs` is the single shared formatter (`Format`/`Parse`) — every producer of an `updated_at`/`due_at`/`created_at` string, local or wire, must go through it. `SqliteTodoRepository.ApplyRemoteAsync` (the local mirror of the Worker's conditional upsert) relies on the same guarantee for its own `WHERE` clause.
- `MainViewModel.ActiveDialog` is `object?` (not a single dialog type) so the same in-view overlay mechanism (`MainView.axaml`'s `UserControl.DataTemplates`, one entry per view-model type) hosts both `TodoEditDialogViewModel` and the new `SettingsViewModel` — extend this pattern for any future dialog rather than adding a parallel mechanism.
- `HttpSyncClient` re-reads both the bearer token and the base URL from `ISecretStore` on **every** call rather than caching either at construction, specifically so saving new values via the Settings overlay take effect on the very next sync — no app restart needed.
- The local SQLite `meta` table (added in `SqliteTodoRepository.EnsureSchema()`, `CREATE TABLE IF NOT EXISTS` like `todos`) now holds the sync cursor (`key = 'sync_cursor'`) — the same table-per-key pattern the Worker's own `meta` table uses server-side for `max_server_seq`, kept intentionally parallel.
- Worker testing uses `@cloudflare/vitest-plugin` (not the older `@cloudflare/vitest-pool-workers` — confirmed via Cloudflare's current docs) via `cloudflareTest()` in `worker/vitest.config.ts`, migrations applied in `worker/test/apply-migrations.ts` using `applyD1Migrations` from `cloudflare:test` + `env`/`exports` from `cloudflare:workers` (`exports.default.fetch(...)` calls the actual Worker). Runs fully locally against a real D1 instance — no Cloudflare account/login needed for `npm test`.
- `wrangler types` (run via `npm run types`, wired as a `pre`-hook on `dev`/`test`/`typecheck`) now generates a full runtime type library into `worker/worker-configuration.d.ts` and **supersedes `@cloudflare/workers-types`** (Wrangler prints this exact guidance) — don't reinstall that package. The generated file is gitignored (regenerated on demand, depends on `wrangler.toml`) and must be added to `tsconfig.json`'s `include` for the ambient `Env`/`cloudflare:workers` `Exports` types to resolve. Secrets (`API_TOKEN`) never appear in it since `wrangler types` only reflects `wrangler.toml`, not `wrangler secret put` values — hence the hand-written `Env` interface in `worker/src/types.ts` includes `API_TOKEN` itself, and test files cast `env` to a local `TestEnv` type for the test-only `TEST_MIGRATIONS` binding.
- Never put real-looking tokens in tests, fixtures, or this file. Construct test secrets at runtime.
- Building the `AppBuilder` by hand (not via `UsePlatformDetect()`, needed here since the composition root has to inject `MainViewModel` via `AppBuilder.Configure(() => new App(...))`) means text rendering isn't wired automatically: call `.UseSkia().UseHarfBuzz()` in addition to the windowing backend (`.UseAvaloniaNative()` on macOS), or the app throws `InvalidOperationException: No text shaping system configured` on startup. `Avalonia.HarfBuzz` comes transitively via `Avalonia.Native`/`Avalonia.Desktop`, no extra package reference needed.
- The root namespace is `Todo`, and `Todo.App` is both a project/namespace and contains a class named `App`. Referencing `Todo.App.App` from another `Todo.*` namespace (e.g. `Todo.Desktop`) needs a `using AvaloniaApp = Todo.App.App;` alias — an unqualified `using Todo.App;` plus `new App(...)` resolves `App` to the namespace, not the class (CS0118).
- `Avalonia.iOS`'s `AvaloniaAppDelegate<TApp>` constrains `where TApp : Application, new()`, and a type with `required` members can't satisfy `new()` (CS9040) — so `App`'s platform-injected `MainViewModel` property is a plain (non-`required`) settable property, not constructor-injected. To actually inject it, override `CreateAppBuilder()` (not `CustomizeAppBuilder`) in the iOS `AppDelegate` and use `AppBuilder.Configure(() => new App { MainViewModel = ... })` — same factory pattern `Todo.Desktop`'s `Program.cs` already uses, since `AvaloniaAppDelegate<TApp>`'s default `CreateAppBuilder` calls `AppBuilder.Configure<TApp>()` (parameterless-only).
- iOS builds always run through IL linking, even for `dotnet build`/simulator/Debug — `PublishTrimmed=false` is rejected outright ("iOS projects must build with PublishTrimmed=true"); use `<MtouchLink>None</MtouchLink>` in `Todo.iOS.csproj` to disable trimming instead. Revisit before any App Store build (needs a `JsonSerializerContext` for `RecurrenceRule`'s JSON column to be trim-safe).
- `ISingleViewApplicationLifetime.MainView` (iOS) is the mobile analog of `IClassicDesktopStyleApplicationLifetime.MainWindow` (desktop) in `App.axaml.cs`'s `OnFrameworkInitializationCompleted`. **`Window` has no platform implementation at all on iOS's single-view host** — not just `ShowDialog<T>`'s owner requirement, but even a plain, non-modal `Window.Show()` throws (confirmed by an actual crash log: an unhandled managed exception inside `Avalonia_iOS_DispatcherImpl_CheckSignaled`, thrown from the "New" button's click handler). The edit dialog (`TodoEditDialogViewModel` + `TodoEditView`, a `UserControl`) is therefore shown as an in-view overlay driven by `MainViewModel.ActiveDialog` (an implicit `DataTemplate` in `MainView.axaml` maps it to `TodoEditView`, shown/hidden via an `IsVisible` binding), not a separate `Window`, on both platforms. Don't reach for `Window`/`ShowDialog` for any future dialog in this app — it doesn't work on iOS at all.
- Real device Keychain entitlements (`keychain-access-groups` etc.) aren't set up yet — simulator generic-password Keychain access doesn't need special entitlements (confirmed — Phase 3's Settings save now exercises `IosKeychainSecretStore` on-simulator).
- `SecKeyChain.Update(query, newAttributes)`'s `newAttributes` record must be built with the **parameterless** `new SecRecord()`, never `new SecRecord(SecKind.GenericPassword)` — the `SecKind` constructor implicitly sets `kSecClass` on the record, and the underlying `SecItemUpdate` API rejects a `kSecClass` in the attributes-to-update dictionary with `errSecNoSuchAttr` ("NoSuchAttribute") — confirmed via `xamarin-macios`' own `Security/Items.cs` source and reproduced by Michael saving a token in Settings on the iOS simulator after a record already existed (first save = `SecKeyChain.Add`, works; re-save = `SecKeyChain.Update`, was failing). Fixed in `IosKeychainSecretStore.SetAsync`.
- App icon: master art is `_appicon/appIcon_1024.png` (1024×1024, no alpha) — never hand-edit derived files. iOS: `src/Todo.iOS/Assets.xcassets/AppIcon.appiconset/icon-1024.png` + `<AppIcon>AppIcon</AppIcon>` in `Todo.iOS.csproj` (the iOS SDK auto-globs `**/*.xcassets` into `ImageAsset` items — confirmed in `Microsoft.iOS.Sdk.DefaultItems.props` — but the `$(AppIcon)` MSBuild property must still be set or `actool` never runs and `Assets.car` never gets compiled into the bundle). macOS: `.NET` has no built-in app-bundle project type outside Mac Catalyst, so `Todo.Desktop.csproj` has a `CreateMacOSAppBundle` post-build target that assembles `Todo.app/Contents/{MacOS,Resources}` from `Info.plist` + `_appicon/AppIcon.icns` (built via `_appicon/make-icns.sh`) — `dotnet run`/the plain executable skips this and shows the generic icon, which is expected; only `open bin/.../Todo.app` shows the real one.
- Platform-native button styling: `src/Todo.App/Styles/MacButtonTheme.axaml` and `IosButtonTheme.axaml` each define a `ControlTheme x:Key="PlatformButtonTheme" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}"` (`ControlTheme.BasedOn` is a real, documented Avalonia 12 feature — confirmed via docs/source examples — that inherits FluentTheme's Button template/focus/disabled visuals and lets you override only specific `Setter`s). Only one of the two files is merged into `Application.Resources.MergedDictionaries` at startup in `App.axaml.cs`'s `Initialize()`, chosen via `OperatingSystem.IsMacOS()` (both files reuse the same key, so there's no collision — whichever one is merged is the one that resolves). Buttons opt in per-instance with `Theme="{DynamicResource PlatformButtonTheme}"` (`StyledElement.Theme` is the documented way to explicitly assign a keyed `ControlTheme` to one control instance instead of relying on implicit `TargetType` resolution) — the iOS-touch-target `MinHeight="44" MinWidth="44"` convention now lives inside `IosButtonTheme.axaml` instead of being hardcoded on every `<Button>` in the shared views. Deliberately uses literal hex brushes, not Fluent's internal `SystemControl*`-style resource keys — those aren't documented/stable Avalonia API and grepping the compiled `Avalonia.Themes.Fluent.dll` for common WinUI-style key names (`ButtonBackground`, etc.) turned up nothing, so their real names in this Fluent version are unverified. (The older `SystemControlBackgroundAltHighBrush` reference in `TodoEditView.axaml`'s/`SettingsView.axaml`'s dialog background turned out to be exactly the flagged risk materializing — see below.) True native controls (`NSButton`/`UIButton` via `NativeControlHost`) were considered and explicitly rejected as out of scope — Avalonia is a self-rendering framework, `NativeControlHost` exists but ships no ready-made Button host for either platform, so it would mean hand-writing native view/event-marshaling interop per platform.
- **macOS dark-mode contrast fix**: Michael reported the macOS UI looking "flat black" with barely-visible buttons/modals in dark mode (iOS was fine). Two root causes, both fixed: (1) `SystemControlBackgroundAltHighBrush` (the unverified Fluent key flagged above) doesn't reliably resolve, leaving dialog `Border.Background` effectively transparent — replaced with explicit `DialogBackgroundBrush`/`DialogBorderBrush` resources in a new `src/Todo.App/Styles/DialogTheme.axaml`, merged unconditionally (both platforms) in `App.axaml.cs`'s `Initialize()`. (2) `MacButtonTheme.axaml`'s chrome used the *same* semi-transparent gray tint for both light and dark mode — a gray-on-anything overlay at 8-20% alpha is essentially invisible against a near-black dark-mode window; a visible button needs to be *lighter* than a dark background, not a darker gray blended into it. Both files now use `<ResourceDictionary.ThemeDictionaries>` (`x:Key="Light"`/`"Dark"`, a real documented Avalonia mechanism — confirmed via docs — for defining theme-variant-aware resources that `{DynamicResource}` picks up automatically based on the active `ThemeVariant`) instead of one-size-fits-all literal brushes: light mode keeps black-based translucency, dark mode uses white-based translucency. This is the general fix for "looks fine in one theme variant, invisible in the other" — reach for `ThemeDictionaries` rather than a single flat color for anything chrome-like.
- `TextBox.PasswordChar` is broken on mobile: confirmed by Michael pasting the API token into `SettingsView`'s token field on iOS and only the first character landing. Matches a known class of Avalonia bugs — masked/secure text entry interacting badly with the platform's native text composition/paste pipeline (confirmed on Android in Avalonia's own issue tracker, #16913/#15658; no iOS-specific issue filed yet but same symptom, same mechanism). `SettingsView.axaml`'s token field is a plain unmasked `TextBox` because of this — the token is already stored securely via `ISecretStore`/Keychain regardless of whether the UI masks it while typing, so there's no real security loss, just less cosmetic privacy while entering it. Don't reach for `PasswordChar` on this app's mobile-visible fields; same "drop the unreliable Avalonia mobile API" pattern as `Window` on iOS and `IActivatableLifetime`.
- **Cmd+V on an external/Simulator hardware keyboard is unreliable on iOS** — confirmed by Michael: pressing ⌘V while the iOS Simulator's TextBox is focused inserted the literal character "v" instead of pasting (same field worked correctly via the same physical keyboard in Safari, and the macOS head is unaffected — this is iOS-only). Root cause lives inside Avalonia's iOS hardware-keyboard-to-TextBox input handling (not something fixable from app code); there's precedent for this class of bug (#14837, "iOS: TextBox handles 'backspace' key as 'delete' key on hardware keyboards", closed) but no exact Cmd+V fix is documented anywhere as of this Avalonia version. Worked around in `SettingsView` with an explicit **Paste** button (`SettingsView.axaml.cs`'s `OnPasteClick`) that reads `TopLevel.GetTopLevel(this)?.Clipboard.TryGetTextAsync()` directly (`Avalonia.Input.Platform`'s `ClipboardExtensions.TryGetTextAsync` — confirmed present in the installed `Avalonia.Base.dll`/`Avalonia.Controls.dll`), sidestepping the OS shortcut entirely. If a future text field needs pasted input on iOS, reach for this pattern rather than relying on ⌘V.
- Toolbar/row icons (New/Edit/Delete in `MainView.axaml`) use `PathIcon` with `StreamGeometry` resources holding raw SVG path data copied verbatim from Google's [material-design-icons](https://github.com/google/material-design-icons) repo (Apache 2.0 — `content/add`, `image/edit`, `action/delete`, classic `24x24` viewBox, not the newer Material Symbols set which uses an unusual negative-origin viewBox). Avalonia's path mini-language accepts SVG path syntax directly, lowercase relative commands included — confirmed via docs, no conversion needed. No icon font/SVG-rendering package added; this keeps icons dependency-free, matching the "no third-party Avalonia control libraries" stack lock. Add new icons the same way: fetch the exact path `d` string from the classic (not Symbols) set and drop it into a `StreamGeometry` resource, don't hand-draw path data from memory.
