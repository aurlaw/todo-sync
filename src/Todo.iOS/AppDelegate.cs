using Avalonia;
using Avalonia.iOS;
using Foundation;
using Todo.App.ViewModels;
using Todo.Core;
using AvaloniaApp = Todo.App.App;

namespace Todo.iOS;

[Register("AppDelegate")]
public partial class AppDelegate : AvaloniaAppDelegate<AvaloniaApp>
{
    // AvaloniaAppDelegate<TApp> requires TApp : new() for CreateAppBuilder's default
    // AppBuilder.Configure<TApp>(); overriding CreateAppBuilder lets us inject MainViewModel
    // via AppBuilder.Configure(Func<TApp>) instead, matching Todo.Desktop's composition root.
    protected override AppBuilder CreateAppBuilder()
    {
        var clock = new SystemClock();
        var databasePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.Personal),
            "todo.db");
        var repository = new SqliteTodoRepository(databasePath, clock);

        var secretStore = new IosKeychainSecretStore();

        // No BaseAddress here — HttpSyncClient resolves the base URL itself (from ISecretStore,
        // falling back to SyncSettings.DefaultBaseUrl), the same way it resolves the bearer token,
        // so Settings can change it at runtime without a restart.
        var httpClient = new HttpClient();
        var syncClient = new HttpSyncClient(httpClient, secretStore);
        var syncEngine = new SyncEngine(repository, syncClient);

        var mainViewModel = new MainViewModel(repository, syncEngine, secretStore);

        return AppBuilder.Configure(() => new AvaloniaApp { MainViewModel = mainViewModel })
            .UseiOS(this)
            .WithInterFont();
    }
}
