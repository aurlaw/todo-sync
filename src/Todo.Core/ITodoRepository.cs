using Todo.Core.Models;

namespace Todo.Core;

public interface ITodoRepository
{
    /// <summary>Non-deleted items, due-soonest first (nulls last), then by creation order.</summary>
    Task<Result<IReadOnlyList<TodoItem>>> GetActiveAsync(CancellationToken ct = default);

    /// <summary>Inserts <paramref name="item"/> (caller sets Id and CreatedAt). Stamps UpdatedAt from the clock and sets Dirty = true.</summary>
    Task<Result<TodoItem>> AddAsync(TodoItem item, CancellationToken ct = default);

    /// <summary>Updates the row matching item.Id. Stamps UpdatedAt from the clock and sets Dirty = true.</summary>
    Task<Result<TodoItem>> UpdateAsync(TodoItem item, CancellationToken ct = default);

    /// <summary>Soft delete: sets IsDeleted = true, stamps UpdatedAt, sets Dirty = true. Never removes the row.</summary>
    Task<Result> DeleteAsync(Guid id, CancellationToken ct = default);

    /// <summary>All rows with Dirty = true, including soft-deleted ones (deletes must propagate too).</summary>
    Task<Result<IReadOnlyList<TodoItem>>> GetDirtyAsync(CancellationToken ct = default);

    /// <summary>Clears Dirty for the given ids after a successful push. No-op for ids not found.</summary>
    Task<Result> ClearDirtyAsync(IReadOnlyCollection<Guid> ids, CancellationToken ct = default);

    /// <summary>
    /// Upserts <paramref name="item"/> using its own UpdatedAt/ServerSeq as authoritative — unlike
    /// AddAsync/UpdateAsync, does NOT stamp the clock and always clears Dirty (the item came from the
    /// server, not a local edit). Applies only if the incoming row is newer than what's stored.
    /// </summary>
    Task<Result> ApplyRemoteAsync(TodoItem item, CancellationToken ct = default);

    /// <summary>The last-applied `/changes` cursor. 0 if sync has never run.</summary>
    Task<Result<long>> GetSyncCursorAsync(CancellationToken ct = default);

    /// <summary>Persists the `/changes` cursor after a successful pull.</summary>
    Task<Result> SetSyncCursorAsync(long cursor, CancellationToken ct = default);
}
