using Todo.Core.Models;

namespace Todo.Core.Tests;

public sealed class SqliteTodoRepositoryTests : IDisposable
{
    private readonly string _dbPath;
    private readonly FakeClock _clock;
    private readonly SqliteTodoRepository _repository;

    public SqliteTodoRepositoryTests()
    {
        _dbPath = Path.Combine(Path.GetTempPath(), $"todo-sync-tests-{Guid.NewGuid():N}.db");
        _clock = new FakeClock(new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero));
        _repository = new SqliteTodoRepository(_dbPath, _clock);
    }

    public void Dispose()
    {
        if (File.Exists(_dbPath))
        {
            File.Delete(_dbPath);
        }
    }

    private TodoItem NewItem(string title, DateTimeOffset? dueAt = null) => new()
    {
        Id = Guid.NewGuid(),
        Title = title,
        CreatedAt = _clock.UtcNow,
        UpdatedAt = _clock.UtcNow,
        DueAt = dueAt,
    };

    [Fact]
    public async Task AddAsync_stamps_dirty_and_returns_item()
    {
        var item = NewItem("Buy milk");

        var result = await _repository.AddAsync(item);

        Assert.True(result.IsSuccess);
        Assert.True(result.Value.Dirty);
        Assert.Equal(_clock.UtcNow, result.Value.UpdatedAt);
    }

    [Fact]
    public async Task GetActiveAsync_returns_added_items_ordered_by_due_date()
    {
        var later = NewItem("Later", _clock.UtcNow.AddDays(2));
        var sooner = NewItem("Sooner", _clock.UtcNow.AddDays(1));
        var noDueDate = NewItem("No due date");

        await _repository.AddAsync(later);
        await _repository.AddAsync(sooner);
        await _repository.AddAsync(noDueDate);

        var result = await _repository.GetActiveAsync();

        Assert.True(result.IsSuccess);
        Assert.Equal(["Sooner", "Later", "No due date"], result.Value.Select(i => i.Title));
    }

    [Fact]
    public async Task UpdateAsync_persists_changes_and_bumps_UpdatedAt()
    {
        var item = NewItem("Original title");
        await _repository.AddAsync(item);

        _clock.UtcNow = _clock.UtcNow.AddHours(1);
        item.Title = "Updated title";
        item.IsDone = true;
        var updateResult = await _repository.UpdateAsync(item);

        Assert.True(updateResult.IsSuccess);

        var active = (await _repository.GetActiveAsync()).Value;
        var stored = Assert.Single(active);
        Assert.Equal("Updated title", stored.Title);
        Assert.True(stored.IsDone);
        Assert.Equal(_clock.UtcNow, stored.UpdatedAt);
    }

    [Fact]
    public async Task UpdateAsync_for_unknown_id_fails()
    {
        var item = NewItem("Never added");

        var result = await _repository.UpdateAsync(item);

        Assert.False(result.IsSuccess);
    }

    [Fact]
    public async Task DeleteAsync_soft_deletes_and_excludes_from_active_list()
    {
        var item = NewItem("Delete me");
        await _repository.AddAsync(item);

        var deleteResult = await _repository.DeleteAsync(item.Id);
        var active = await _repository.GetActiveAsync();

        Assert.True(deleteResult.IsSuccess);
        Assert.Empty(active.Value);
    }

    [Fact]
    public async Task DeleteAsync_for_unknown_id_fails()
    {
        var result = await _repository.DeleteAsync(Guid.NewGuid());

        Assert.False(result.IsSuccess);
    }

    [Fact]
    public async Task Recurrence_round_trips_through_storage()
    {
        var item = NewItem("Take pills");
        item.Recurrence = new RecurrenceRule
        {
            Frequency = RecurrenceFrequency.Weekly,
            Interval = 1,
            DaysOfWeek = [DayOfWeek.Monday, DayOfWeek.Thursday],
        };
        await _repository.AddAsync(item);

        var active = await _repository.GetActiveAsync();

        var stored = Assert.Single(active.Value);
        Assert.NotNull(stored.Recurrence);
        Assert.Equal(RecurrenceFrequency.Weekly, stored.Recurrence!.Frequency);
        Assert.Equal([DayOfWeek.Monday, DayOfWeek.Thursday], stored.Recurrence.DaysOfWeek);
    }

    [Fact]
    public async Task GetDirtyAsync_returns_only_dirty_rows_including_deleted()
    {
        var dirty = NewItem("Dirty");
        var deletedDirty = NewItem("Deleted but dirty");
        await _repository.AddAsync(dirty);
        await _repository.AddAsync(deletedDirty);
        await _repository.DeleteAsync(deletedDirty.Id);

        var clean = NewItem("Clean");
        var addedClean = (await _repository.AddAsync(clean)).Value;
        await _repository.ClearDirtyAsync([addedClean.Id]);

        var result = await _repository.GetDirtyAsync();

        Assert.True(result.IsSuccess);
        Assert.Equal(
            new[] { "Dirty", "Deleted but dirty" }.OrderBy(t => t),
            result.Value.Select(i => i.Title).OrderBy(t => t));
    }

    [Fact]
    public async Task ClearDirtyAsync_clears_only_given_ids()
    {
        var a = (await _repository.AddAsync(NewItem("A"))).Value;
        var b = (await _repository.AddAsync(NewItem("B"))).Value;

        var result = await _repository.ClearDirtyAsync([a.Id]);
        var dirty = await _repository.GetDirtyAsync();

        Assert.True(result.IsSuccess);
        var remaining = Assert.Single(dirty.Value);
        Assert.Equal(b.Id, remaining.Id);
    }

    [Fact]
    public async Task ClearDirtyAsync_with_no_ids_is_a_noop()
    {
        var result = await _repository.ClearDirtyAsync([]);

        Assert.True(result.IsSuccess);
    }

    [Fact]
    public async Task ApplyRemoteAsync_inserts_new_item_without_marking_dirty()
    {
        var remote = new TodoItem
        {
            Id = Guid.NewGuid(),
            Title = "From server",
            CreatedAt = _clock.UtcNow,
            UpdatedAt = _clock.UtcNow,
            ServerSeq = 7,
        };

        var result = await _repository.ApplyRemoteAsync(remote);
        var active = await _repository.GetActiveAsync();

        Assert.True(result.IsSuccess);
        var stored = Assert.Single(active.Value);
        Assert.Equal("From server", stored.Title);
        Assert.False(stored.Dirty);
        Assert.Equal(7, stored.ServerSeq);
    }

    [Fact]
    public async Task ApplyRemoteAsync_applies_a_newer_update()
    {
        var id = Guid.NewGuid();
        var older = new TodoItem { Id = id, Title = "Old", CreatedAt = _clock.UtcNow, UpdatedAt = _clock.UtcNow, ServerSeq = 1 };
        await _repository.ApplyRemoteAsync(older);

        var newer = new TodoItem
        {
            Id = id,
            Title = "New",
            CreatedAt = _clock.UtcNow,
            UpdatedAt = _clock.UtcNow.AddMinutes(1),
            ServerSeq = 2,
        };
        var result = await _repository.ApplyRemoteAsync(newer);

        var active = await _repository.GetActiveAsync();
        var stored = Assert.Single(active.Value);
        Assert.True(result.IsSuccess);
        Assert.Equal("New", stored.Title);
        Assert.Equal(2, stored.ServerSeq);
    }

    [Fact]
    public async Task ApplyRemoteAsync_rejects_a_stale_update_as_a_noop()
    {
        var id = Guid.NewGuid();
        var newer = new TodoItem { Id = id, Title = "New", CreatedAt = _clock.UtcNow, UpdatedAt = _clock.UtcNow.AddMinutes(1), ServerSeq = 2 };
        await _repository.ApplyRemoteAsync(newer);

        var stale = new TodoItem { Id = id, Title = "Stale", CreatedAt = _clock.UtcNow, UpdatedAt = _clock.UtcNow, ServerSeq = 1 };
        var result = await _repository.ApplyRemoteAsync(stale);

        var active = await _repository.GetActiveAsync();
        var stored = Assert.Single(active.Value);
        Assert.True(result.IsSuccess);
        Assert.Equal("New", stored.Title);
    }

    [Fact]
    public async Task ApplyRemoteAsync_can_soft_delete_a_local_item()
    {
        var id = Guid.NewGuid();
        var existing = new TodoItem { Id = id, Title = "Local", CreatedAt = _clock.UtcNow, UpdatedAt = _clock.UtcNow };
        await _repository.ApplyRemoteAsync(existing);

        var deleted = new TodoItem
        {
            Id = id,
            Title = "Local",
            CreatedAt = _clock.UtcNow,
            UpdatedAt = _clock.UtcNow.AddMinutes(1),
            IsDeleted = true,
        };
        await _repository.ApplyRemoteAsync(deleted);

        var active = await _repository.GetActiveAsync();
        Assert.Empty(active.Value);
    }

    [Fact]
    public async Task Sync_cursor_defaults_to_zero_and_round_trips()
    {
        var initial = await _repository.GetSyncCursorAsync();
        Assert.True(initial.IsSuccess);
        Assert.Equal(0, initial.Value);

        await _repository.SetSyncCursorAsync(42);
        var updated = await _repository.GetSyncCursorAsync();

        Assert.Equal(42, updated.Value);

        await _repository.SetSyncCursorAsync(99);
        var overwritten = await _repository.GetSyncCursorAsync();

        Assert.Equal(99, overwritten.Value);
    }
}
