using Avalonia.Controls;
using Avalonia.Interactivity;
using Todo.App.ViewModels;
using Todo.Core.Models;

namespace Todo.App.Views;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
    }

    private MainViewModel ViewModel => (MainViewModel)DataContext!;

    private async void OnOpened(object? sender, System.EventArgs e)
    {
        await ViewModel.LoadAsync();
    }

    private async void OnNewClick(object? sender, RoutedEventArgs e)
    {
        var result = await ShowEditDialogAsync(existing: null);
        if (result is not null)
        {
            await ViewModel.AddAsync(result);
        }
    }

    private async void OnEditClick(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { DataContext: TodoItemViewModel itemViewModel })
        {
            return;
        }

        var result = await ShowEditDialogAsync(itemViewModel.ToDomainModel());
        if (result is not null)
        {
            await ViewModel.UpdateAsync(itemViewModel, result);
        }
    }

    private void OnDeleteClick(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { DataContext: TodoItemViewModel itemViewModel })
        {
            return;
        }

        ViewModel.DeleteCommand.Execute(itemViewModel);
    }

    private async Task<TodoItem?> ShowEditDialogAsync(TodoItem? existing)
    {
        var dialogViewModel = existing is null
            ? new TodoEditDialogViewModel()
            : new TodoEditDialogViewModel(existing);

        var dialog = new TodoEditDialog { DataContext = dialogViewModel };
        dialogViewModel.RequestClose = result => dialog.Close(result);

        return await dialog.ShowDialog<TodoItem?>(this);
    }
}
