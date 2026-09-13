using System.Runtime.Versioning;
using Avalonia;
using Todo.App.ViewModels;
using Todo.Core;
using AvaloniaApp = Todo.App.App;

namespace Todo.Desktop;

internal static class Program
{
    // Todo.Desktop targets bare net10.0 (no platform qualifier) but only ever runs on macOS
    // (Avalonia Native backend, per the stack lock) — this satisfies CA1416 for MacFileSecretStore.
    [SupportedOSPlatform("macos")]
    [STAThread]
    public static void Main(string[] args)
    {
        var clock = new SystemClock();
        var databasePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "todo-sync",
            "todo.db");
        var repository = new SqliteTodoRepository(databasePath, clock);

        var secretsPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "todo-sync",
            "secrets.json");
        var secretStore = new MacFileSecretStore(secretsPath);

        // No BaseAddress here — HttpSyncClient resolves the base URL itself (from ISecretStore,
        // falling back to SyncSettings.DefaultBaseUrl), the same way it resolves the bearer token,
        // so Settings can change it at runtime without a restart.
        var httpClient = new HttpClient();
        var syncClient = new HttpSyncClient(httpClient, secretStore);
        var syncEngine = new SyncEngine(repository, syncClient);

        var mainViewModel = new MainViewModel(repository, syncEngine, secretStore);

        BuildAvaloniaApp(mainViewModel)
            .StartWithClassicDesktopLifetime(args);
    }

    private static AppBuilder BuildAvaloniaApp(MainViewModel mainViewModel) =>
        AppBuilder.Configure(() => new AvaloniaApp { MainViewModel = mainViewModel })
            .UseSkia()
            .UseHarfBuzz()
            .UseAvaloniaNative()
            .LogToTrace();
}
