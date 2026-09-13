using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using Todo.App.ViewModels;
using Todo.App.Views;

namespace Todo.App;

public partial class App : Application
{
    /// <summary>
    /// Set by each platform head's composition root before this instance is used. A settable
    /// property (rather than constructor injection) because iOS's <c>AvaloniaAppDelegate&lt;TApp&gt;</c>
    /// requires <c>TApp : new()</c> — and a type with <c>required</c> members can't satisfy that
    /// constraint (CS9040), so this can't be <c>required</c> either.
    /// </summary>
    public MainViewModel MainViewModel { get; init; } = null!;

    public override void Initialize()
    {
        AvaloniaXamlLoader.Load(this);
    }

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            desktop.MainWindow = new MainWindow
            {
                DataContext = MainViewModel,
            };
        }
        else if (ApplicationLifetime is ISingleViewApplicationLifetime singleView)
        {
            singleView.MainView = new MainView
            {
                DataContext = MainViewModel,
            };
        }

        base.OnFrameworkInitializationCompleted();
    }

    private void OnAboutClick(object? sender, EventArgs e)
    {
        var owner = (ApplicationLifetime as IClassicDesktopStyleApplicationLifetime)?.MainWindow;
        var about = new AboutDialog();
        if (owner is not null)
        {
            about.ShowDialog(owner);
        }
        else
        {
            about.Show();
        }
    }
}
