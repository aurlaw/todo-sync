using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Todo.Core.Models;

namespace Todo.App.ViewModels;

public sealed partial class TodoEditDialogViewModel : ObservableObject
{
    private readonly Guid? _existingId;
    private readonly DateTimeOffset? _existingCreatedAt;
    private readonly RecurrenceRule? _existingRecurrence;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(SaveCommand))]
    private string _title = string.Empty;

    [ObservableProperty]
    private string? _notes;

    [ObservableProperty]
    private DateTimeOffset? _dueAt;

    public bool IsEditingExisting => _existingId is not null;

    /// <summary>Set by the view. Invoked with the saved item, or null on cancel.</summary>
    public Action<TodoItem?>? RequestClose { get; set; }

    public TodoEditDialogViewModel()
    {
    }

    public TodoEditDialogViewModel(TodoItem existing)
    {
        _existingId = existing.Id;
        _existingCreatedAt = existing.CreatedAt;
        _existingRecurrence = existing.Recurrence;
        Title = existing.Title;
        Notes = existing.Notes;
        DueAt = existing.DueAt;
    }

    private bool CanSave => !string.IsNullOrWhiteSpace(Title);

    [RelayCommand(CanExecute = nameof(CanSave))]
    private void Save()
    {
        var now = DateTimeOffset.UtcNow;
        var item = new TodoItem
        {
            Id = _existingId ?? Guid.NewGuid(),
            Title = Title.Trim(),
            Notes = string.IsNullOrWhiteSpace(Notes) ? null : Notes.Trim(),
            DueAt = DueAt,
            Recurrence = _existingRecurrence,
            CreatedAt = _existingCreatedAt ?? now,
            UpdatedAt = now,
        };
        RequestClose?.Invoke(item);
    }

    [RelayCommand]
    private void Cancel() => RequestClose?.Invoke(null);
}
