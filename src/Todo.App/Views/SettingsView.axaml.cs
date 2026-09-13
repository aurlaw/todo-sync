using Avalonia.Controls;
using Avalonia.Input.Platform;
using Avalonia.Interactivity;
using Todo.App.ViewModels;

namespace Todo.App.Views;

public partial class SettingsView : UserControl
{
    public SettingsView()
    {
        InitializeComponent();
    }

    private async void OnLoaded(object? sender, RoutedEventArgs e)
    {
        if (DataContext is SettingsViewModel viewModel)
        {
            await viewModel.LoadAsync();
        }
    }

    // Cmd+V on a hardware keyboard is unreliable in the iOS Simulator (inserts the literal "v"
    // character instead of pasting — a gap in Avalonia's iOS hardware-keyboard handling, not
    // something fixable from app code). This button reads the clipboard directly, sidestepping
    // the OS shortcut entirely.
    private async void OnPasteClick(object? sender, RoutedEventArgs e)
    {
        if (DataContext is not SettingsViewModel viewModel)
        {
            return;
        }

        var clipboard = TopLevel.GetTopLevel(this)?.Clipboard;
        var text = clipboard is null ? null : await clipboard.TryGetTextAsync();
        if (!string.IsNullOrEmpty(text))
        {
            viewModel.ApiToken = text;
        }
    }
}
