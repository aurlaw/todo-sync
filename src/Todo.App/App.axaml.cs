using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using Todo.App.ViewModels;
using Todo.App.Views;

namespace Todo.App;

public partial class App : Application
{
    private readonly MainViewModel _mainViewModel;

    public App(MainViewModel mainViewModel)
    {
        _mainViewModel = mainViewModel;
    }

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
                DataContext = _mainViewModel,
            };
        }

        base.OnFrameworkInitializationCompleted();
    }
}
