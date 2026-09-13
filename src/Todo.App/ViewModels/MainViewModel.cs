using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Todo.Core;
using Todo.Core.Models;

namespace Todo.App.ViewModels;

public sealed partial class MainViewModel : ObservableObject
{
    private readonly ITodoRepository _repository;

    public ObservableCollection<TodoItemViewModel> Items { get; } = [];

    [ObservableProperty]
    private string? _statusMessage;

    [ObservableProperty]
    private TodoEditDialogViewModel? _activeDialog;

    public MainViewModel(ITodoRepository repository)
    {
        _repository = repository;
    }

    [RelayCommand]
    private void OpenNew()
    {
        var dialog = new TodoEditDialogViewModel();
        dialog.RequestClose = result => OnDialogClosed(result, existingTarget: null);
        ActiveDialog = dialog;
    }

    [RelayCommand]
    private void OpenEdit(TodoItemViewModel target)
    {
        var dialog = new TodoEditDialogViewModel(target.ToDomainModel());
        dialog.RequestClose = result => OnDialogClosed(result, target);
        ActiveDialog = dialog;
    }

    private void OnDialogClosed(TodoItem? result, TodoItemViewModel? existingTarget)
    {
        ActiveDialog = null;

        if (result is null)
        {
            return;
        }

        if (existingTarget is null)
        {
            _ = AddAsync(result);
        }
        else
        {
            _ = UpdateAsync(existingTarget, result);
        }
    }

    public async Task LoadAsync()
    {
        var result = await _repository.GetActiveAsync();
        if (!result.IsSuccess)
        {
            StatusMessage = result.Error;
            return;
        }

        Items.Clear();
        foreach (var item in result.Value)
        {
            Items.Add(new TodoItemViewModel(item, ToggleDoneAsync));
        }
    }

    private async Task AddAsync(TodoItem item)
    {
        var result = await _repository.AddAsync(item);
        if (result.IsSuccess)
        {
            Items.Add(new TodoItemViewModel(result.Value, ToggleDoneAsync));
        }
        else
        {
            StatusMessage = result.Error;
        }
    }

    private async Task UpdateAsync(TodoItemViewModel target, TodoItem edited)
    {
        var result = await _repository.UpdateAsync(edited);
        if (result.IsSuccess)
        {
            target.Apply(result.Value);
        }
        else
        {
            StatusMessage = result.Error;
        }
    }

    [RelayCommand]
    private async Task DeleteAsync(TodoItemViewModel target)
    {
        var result = await _repository.DeleteAsync(target.Id);
        if (result.IsSuccess)
        {
            Items.Remove(target);
        }
        else
        {
            StatusMessage = result.Error;
        }
    }

    private async Task ToggleDoneAsync(TodoItemViewModel target)
    {
        var result = await _repository.UpdateAsync(target.ToDomainModel());
        if (!result.IsSuccess)
        {
            StatusMessage = result.Error;
        }
    }
}
