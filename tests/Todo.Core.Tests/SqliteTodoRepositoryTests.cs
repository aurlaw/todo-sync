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
}
