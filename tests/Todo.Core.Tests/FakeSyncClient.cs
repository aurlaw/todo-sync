using Todo.Core.Models;

namespace Todo.Core.Tests;

public sealed class FakeSyncClient : ISyncClient
{
    public List<TodoItem> PushedItems { get; } = [];

    public int PushCallCount { get; private set; }

    public int ChangesCallCount { get; private set; }

    public List<long> ChangesSinceCalls { get; } = [];

    /// <summary>Default: every pushed item is applied with serverSeq = 1.</summary>
    public Func<IReadOnlyList<TodoItem>, PushResult> PushHandler { get; set; } =
        items => new PushResult
        {
            Applied = items.Select(i => new PushedItem(i.Id, 1)).ToList(),
            Rejected = [],
        };

    /// <summary>Scripted `/changes` responses, dequeued in order. Empty queue -&gt; empty page, cursor unchanged.</summary>
    public Queue<ChangesResult> ChangesResponses { get; } = new();

    public Task<Result<PushResult>> PushAsync(IReadOnlyList<TodoItem> items, CancellationToken ct = default)
    {
        PushCallCount++;
        PushedItems.AddRange(items);
        return Task.FromResult(Result.Ok(PushHandler(items)));
    }

    public Task<Result<ChangesResult>> GetChangesAsync(long since, CancellationToken ct = default)
    {
        ChangesCallCount++;
        ChangesSinceCalls.Add(since);
        var response = ChangesResponses.Count > 0
            ? ChangesResponses.Dequeue()
            : new ChangesResult { Items = [], Cursor = since };
        return Task.FromResult(Result.Ok(response));
    }
}
