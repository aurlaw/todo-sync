using Avalonia.Controls;
using Avalonia.Interactivity;
using Todo.App.ViewModels;

namespace Todo.App.Views;

public partial class MainView : UserControl
{
    public MainView()
    {
        InitializeComponent();
    }

    private MainViewModel ViewModel => (MainViewModel)DataContext!;

    private async void OnLoaded(object? sender, RoutedEventArgs e)
    {
        await ViewModel.LoadAsync();
        _ = ViewModel.SyncNowAsync();
    }

    private void OnNewClick(object? sender, RoutedEventArgs e)
    {
        ViewModel.OpenNewCommand.Execute(null);
    }

    private void OnSettingsClick(object? sender, RoutedEventArgs e)
    {
        ViewModel.OpenSettingsCommand.Execute(null);
    }

    private void OnEditClick(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { DataContext: TodoItemViewModel itemViewModel })
        {
            return;
        }

        ViewModel.OpenEditCommand.Execute(itemViewModel);
    }

    private void OnDeleteClick(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { DataContext: TodoItemViewModel itemViewModel })
        {
            return;
        }

        ViewModel.DeleteCommand.Execute(itemViewModel);
    }
}
