using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Todo.Core;
using Todo.Core.Models;

namespace Todo.App.ViewModels;

public sealed partial class MainViewModel : ObservableObject
{
    private static readonly TimeSpan SyncDebounceDelay = TimeSpan.FromSeconds(2);

    private readonly ITodoRepository _repository;
    private readonly SyncEngine _syncEngine;
    private readonly ISecretStore _secretStore;
    private CancellationTokenSource? _debounceCts;

    public ObservableCollection<TodoItemViewModel> Items { get; } = [];

    [ObservableProperty]
    private string? _statusMessage;

    /// <summary>Either a TodoEditDialogViewModel or a SettingsViewModel — see MainView.axaml's DataTemplates.</summary>
    [ObservableProperty]
    private object? _activeDialog;

    public MainViewModel(ITodoRepository repository, SyncEngine syncEngine, ISecretStore secretStore)
    {
        _repository = repository;
        _syncEngine = syncEngine;
        _secretStore = secretStore;
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

    [RelayCommand]
    private void OpenSettings()
    {
        var settings = new SettingsViewModel(_secretStore);
        settings.RequestClose = () => ActiveDialog = null;
        ActiveDialog = settings;
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
            ScheduleSync();
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
            ScheduleSync();
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
            ScheduleSync();
        }
        else
        {
            StatusMessage = result.Error;
        }
    }

    private async Task ToggleDoneAsync(TodoItemViewModel target)
    {
        var result = await _repository.UpdateAsync(target.ToDomainModel());
        if (result.IsSuccess)
        {
            ScheduleSync();
        }
        else
        {
            StatusMessage = result.Error;
        }
    }

    /// <summary>
    /// Runs one sync cycle immediately. Called at app start (after the initial LoadAsync) and,
    /// debounced, after local edits. Failures are deliberately not surfaced to StatusMessage this
    /// phase — "API token not configured" is expected/silent pre-setup, and distinguishing that
    /// from a real network failure needs error-type info Result doesn't carry yet; better done once
    /// there's an actual sync-status UI. The next debounce or app start naturally retries.
    /// </summary>
    public async Task SyncNowAsync()
    {
        var result = await _syncEngine.SyncAsync();
        if (result.IsSuccess)
        {
            await LoadAsync();
        }
    }

    private void ScheduleSync()
    {
        _debounceCts?.Cancel();
        var cts = new CancellationTokenSource();
        _debounceCts = cts;
        _ = DebounceSyncAsync(cts.Token);
    }

    private async Task DebounceSyncAsync(CancellationToken ct)
    {
        try
        {
            await Task.Delay(SyncDebounceDelay, ct);
            await SyncNowAsync();
        }
        catch (OperationCanceledException)
        {
            // Superseded by a newer edit before the debounce elapsed — expected.
        }
    }
}
