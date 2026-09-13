namespace Todo.Core.Models;

public sealed class TodoItem
{
    public required Guid Id { get; init; }

    public required string Title { get; set; }

    public string? Notes { get; set; }

    public bool IsDone { get; set; }

    public DateTimeOffset? DueAt { get; set; }

    public RecurrenceRule? Recurrence { get; set; }

    public required DateTimeOffset CreatedAt { get; init; }

    public required DateTimeOffset UpdatedAt { get; set; }

    public bool IsDeleted { get; set; }

    /// <summary>Local only, never synced.</summary>
    public bool Dirty { get; set; }

    /// <summary>Assigned by the sync Worker; null until first synced.</summary>
    public long? ServerSeq { get; set; }
}
