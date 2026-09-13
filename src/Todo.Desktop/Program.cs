using Avalonia;
using Todo.App.ViewModels;
using Todo.Core;
using AvaloniaApp = Todo.App.App;

namespace Todo.Desktop;

internal static class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        var clock = new SystemClock();
        var databasePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "todo-sync",
            "todo.db");
        var repository = new SqliteTodoRepository(databasePath, clock);
        var mainViewModel = new MainViewModel(repository);

        BuildAvaloniaApp(mainViewModel)
            .StartWithClassicDesktopLifetime(args);
    }

    private static AppBuilder BuildAvaloniaApp(MainViewModel mainViewModel) =>
        AppBuilder.Configure(() => new AvaloniaApp(mainViewModel))
            .UseSkia()
            .UseHarfBuzz()
            .UseAvaloniaNative()
            .LogToTrace();
}
