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
}
