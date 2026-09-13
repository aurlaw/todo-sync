using Todo.Core.Models;

namespace Todo.Core;

public interface ISyncClient
{
    Task<Result<PushResult>> PushAsync(IReadOnlyList<TodoItem> items, CancellationToken ct = default);

    Task<Result<ChangesResult>> GetChangesAsync(long since, CancellationToken ct = default);
}

public sealed class PushResult
{
    public required IReadOnlyList<PushedItem> Applied { get; init; }

    public required IReadOnlyList<RejectedItem> Rejected { get; init; }
}

public sealed record PushedItem(Guid Id, long ServerSeq);

public sealed record RejectedItem(Guid Id, string Reason);

public sealed class ChangesResult
{
    public required IReadOnlyList<TodoItem> Items { get; init; }

    public required long Cursor { get; init; }
}
