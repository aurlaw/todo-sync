using Todo.Core.Models;

namespace Todo.Core.Tests;

public sealed class SyncEngineTests : IDisposable
{
    private readonly string _dbPath;
    private readonly FakeClock _clock;
    private readonly SqliteTodoRepository _repository;
    private readonly FakeSyncClient _syncClient;
    private readonly SyncEngine _engine;

    public SyncEngineTests()
    {
        _dbPath = Path.Combine(Path.GetTempPath(), $"todo-sync-tests-{Guid.NewGuid():N}.db");
        _clock = new FakeClock(new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero));
        _repository = new SqliteTodoRepository(_dbPath, _clock);
        _syncClient = new FakeSyncClient();
        _engine = new SyncEngine(_repository, _syncClient);
    }

    public void Dispose()
    {
        if (File.Exists(_dbPath))
        {
            File.Delete(_dbPath);
        }
    }

    private TodoItem NewItem(string title) => new()
    {
        Id = Guid.NewGuid(),
        Title = title,
        CreatedAt = _clock.UtcNow,
        UpdatedAt = _clock.UtcNow,
    };

    [Fact]
    public async Task SyncAsync_skips_push_when_nothing_is_dirty()
    {
        var result = await _engine.SyncAsync();

        Assert.True(result.IsSuccess);
        Assert.Equal(0, _syncClient.PushCallCount);
    }

    [Fact]
    public async Task SyncAsync_pushes_dirty_items_and_clears_dirty_on_applied()
    {
        var item = (await _repository.AddAsync(NewItem("Buy milk"))).Value;

        var result = await _engine.SyncAsync();

        Assert.True(result.IsSuccess);
        Assert.Equal(1, _syncClient.PushCallCount);
        Assert.Contains(item.Id, _syncClient.PushedItems.Select(i => i.Id));

        var dirty = await _repository.GetDirtyAsync();
        Assert.Empty(dirty.Value);
    }

    [Fact]
    public async Task SyncAsync_leaves_rejected_items_dirty()
    {
        var item = (await _repository.AddAsync(NewItem("Buy milk"))).Value;
        _syncClient.PushHandler = items => new PushResult
        {
            Applied = [],
            Rejected = items.Select(i => new RejectedItem(i.Id, "stale")).ToList(),
        };

        var result = await _engine.SyncAsync();

        Assert.True(result.IsSuccess);
        var dirty = await _repository.GetDirtyAsync();
        Assert.Contains(item.Id, dirty.Value.Select(i => i.Id));
    }

    [Fact]
    public async Task SyncAsync_applies_pulled_changes_and_advances_cursor()
    {
        var remoteId = Guid.NewGuid();
        _syncClient.ChangesResponses.Enqueue(new ChangesResult
        {
            Items =
            [
                new TodoItem
                {
                    Id = remoteId,
                    Title = "From another device",
                    CreatedAt = _clock.UtcNow,
                    UpdatedAt = _clock.UtcNow,
                    ServerSeq = 5,
                },
            ],
            Cursor = 5,
        });

        var result = await _engine.SyncAsync();

        Assert.True(result.IsSuccess);
        var active = await _repository.GetActiveAsync();
        Assert.Contains(active.Value, i => i.Id == remoteId && i.Title == "From another device");

        var cursor = await _repository.GetSyncCursorAsync();
        Assert.Equal(5, cursor.Value);
    }

    [Fact]
    public async Task SyncAsync_drains_multiple_pages_before_persisting_final_cursor()
    {
        var firstId = Guid.NewGuid();
        var secondId = Guid.NewGuid();
        _syncClient.ChangesResponses.Enqueue(new ChangesResult
        {
            Items = [new TodoItem { Id = firstId, Title = "Page 1", CreatedAt = _clock.UtcNow, UpdatedAt = _clock.UtcNow, ServerSeq = 1 }],
            Cursor = 1,
        });
        _syncClient.ChangesResponses.Enqueue(new ChangesResult
        {
            Items = [new TodoItem { Id = secondId, Title = "Page 2", CreatedAt = _clock.UtcNow, UpdatedAt = _clock.UtcNow, ServerSeq = 2 }],
            Cursor = 2,
        });

        var result = await _engine.SyncAsync();

        Assert.True(result.IsSuccess);
        Assert.Equal(3, _syncClient.ChangesCallCount); // page 1, page 2, then the empty page that ends the loop

        var active = await _repository.GetActiveAsync();
        Assert.Contains(active.Value, i => i.Id == firstId);
        Assert.Contains(active.Value, i => i.Id == secondId);

        var cursor = await _repository.GetSyncCursorAsync();
        Assert.Equal(2, cursor.Value);
    }

    [Fact]
    public async Task SyncAsync_uses_the_persisted_cursor_as_since_on_the_next_call()
    {
        _syncClient.ChangesResponses.Enqueue(new ChangesResult { Items = [], Cursor = 10 });
        await _engine.SyncAsync();

        await _engine.SyncAsync();

        Assert.Equal([0L, 10L], _syncClient.ChangesSinceCalls);
    }
}
