using System.Reflection;
using Avalonia.Controls;
using Avalonia.Interactivity;

namespace Todo.App.Views;

public partial class AboutDialog : Window
{
    public AboutDialog()
    {
        InitializeComponent();

        var version = Assembly.GetEntryAssembly()?.GetName().Version;
        VersionText.Text = version is null ? string.Empty : $"Version {version.ToString(3)}";
    }

    private void OnCloseClick(object? sender, RoutedEventArgs e) => Close();
}
