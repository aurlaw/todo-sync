namespace Todo.Core;

public static class SyncSettings
{
    /// <summary>
    /// Fallback used when nothing is stored under <see cref="SecretKeys.SyncBaseUrl"/> yet — the
    /// user can point the app at a different Worker (e.g. a local dev instance) via Settings.
    /// </summary>
    public const string DefaultBaseUrl = "https://todo-sync-worker.aurlaw.dev";
}
