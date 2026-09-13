# todo-sync

A personal TODO app for one user. Avalonia 12 / .NET 10, macOS + iOS, offline-first SQLite with cheap sync via a Cloudflare Worker + D1. Not distributed through any app store.

Full design decisions and phased plan: `Tech/todo-sync/project-plan.md` in the Obsidian vault (see `CLAUDE.md` for the working agreement and stack details).

## Status

**Phase 0** is implemented: solution scaffold, Core models, SQLite repository, and a macOS app with list / add / edit / complete / delete. No sync, no reminders, no iOS yet — see the phase table below.

| Phase | Scope |
|---|---|
| 0 ✅ | Solution scaffold, Core models, SQLite repo, macOS head (list/add/edit/complete/delete) |
| 1 | iOS head, adaptive layout, per-platform secret storage |
| 2 | Cloudflare Worker + D1 sync backend |
| 3 | Sync engine (push/pull, conflict handling) |
| 4 | Reminders (recurrence, notifications) |
| 5 | Signing + install workflow |

## Prerequisites

- **.NET 10 SDK** (`dotnet --version` → `10.0.100` or later)
- **macOS** to build/run the `Todo.Desktop` head (uses the Avalonia Native backend, not Mac Catalyst)
- **Node.js + npm** — only needed once the `worker/` project exists (Phase 2)

## Solution layout

```
todo-sync/
  Todo.slnx
  src/
    Todo.Core/      models, ITodoRepository, SqliteTodoRepository — no Avalonia references
    Todo.App/        shared Avalonia UI (views, view models)
    Todo.Desktop/    macOS entry point
  tests/
    Todo.Core.Tests/ xunit tests for Core
```

## Commands

```bash
# Restore + build everything
dotnet build Todo.slnx

# Run the Core test suite
dotnet test tests/Todo.Core.Tests

# Run the macOS app
dotnet build src/Todo.Desktop && dotnet run --project src/Todo.Desktop
```

The macOS app stores its SQLite database at `~/Library/Application Support/todo-sync/todo.db`.
