using CommunityToolkit.Mvvm.ComponentModel;
using Todo.Core.Models;

namespace Todo.App.ViewModels;

public sealed partial class TodoItemViewModel : ObservableObject
{
    private readonly Func<TodoItemViewModel, Task> _onToggleDone;
    private bool _isApplying;

    public Guid Id { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public RecurrenceRule? Recurrence { get; private set; }

    [ObservableProperty]
    private string _title = string.Empty;

    [ObservableProperty]
    private string? _notes;

    [ObservableProperty]
    private bool _isDone;

    [ObservableProperty]
    private DateTimeOffset? _dueAt;

    public TodoItemViewModel(TodoItem item, Func<TodoItemViewModel, Task> onToggleDone)
    {
        _onToggleDone = onToggleDone;
        Apply(item);
    }

    /// <summary>Refreshes this view model from a persisted item without re-triggering OnIsDoneChanged's auto-save.</summary>
    public void Apply(TodoItem item)
    {
        _isApplying = true;
        Id = item.Id;
        CreatedAt = item.CreatedAt;
        Recurrence = item.Recurrence;
        Title = item.Title;
        Notes = item.Notes;
        DueAt = item.DueAt;
        IsDone = item.IsDone;
        _isApplying = false;
    }

    public TodoItem ToDomainModel() => new()
    {
        Id = Id,
        Title = Title,
        Notes = Notes,
        IsDone = IsDone,
        DueAt = DueAt,
        Recurrence = Recurrence,
        CreatedAt = CreatedAt,
        UpdatedAt = CreatedAt,
    };

    partial void OnIsDoneChanged(bool value)
    {
        if (_isApplying)
        {
            return;
        }

        _ = _onToggleDone(this);
    }
}
