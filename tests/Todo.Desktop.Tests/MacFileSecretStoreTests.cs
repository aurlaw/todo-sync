using System.Runtime.Versioning;
using Todo.Desktop;

namespace Todo.Desktop.Tests;

[SupportedOSPlatform("macos")]
public sealed class MacFileSecretStoreTests : IDisposable
{
    private readonly string _filePath;
    private readonly MacFileSecretStore _store;

    public MacFileSecretStoreTests()
    {
        _filePath = Path.Combine(Path.GetTempPath(), $"todo-sync-secrets-tests-{Guid.NewGuid():N}.json");
        _store = new MacFileSecretStore(_filePath);
    }

    public void Dispose()
    {
        if (File.Exists(_filePath))
        {
            File.Delete(_filePath);
        }
    }

    [Fact]
    public async Task GetAsync_for_missing_key_returns_null()
    {
        var result = await _store.GetAsync("missing");

        Assert.True(result.IsSuccess);
        Assert.Null(result.Value);
    }

    [Fact]
    public async Task SetAsync_then_GetAsync_round_trips_the_value()
    {
        await _store.SetAsync("token", "s3cr3t");

        var result = await _store.GetAsync("token");

        Assert.True(result.IsSuccess);
        Assert.Equal("s3cr3t", result.Value);
    }

    [Fact]
    public async Task SetAsync_overwrites_an_existing_value()
    {
        await _store.SetAsync("token", "first");
        await _store.SetAsync("token", "second");

        var result = await _store.GetAsync("token");

        Assert.Equal("second", result.Value);
    }

    [Fact]
    public async Task DeleteAsync_removes_the_key()
    {
        await _store.SetAsync("token", "s3cr3t");

        await _store.DeleteAsync("token");
        var result = await _store.GetAsync("token");

        Assert.True(result.IsSuccess);
        Assert.Null(result.Value);
    }

    [Fact]
    public async Task DeleteAsync_for_missing_key_still_succeeds()
    {
        var result = await _store.DeleteAsync("missing");

        Assert.True(result.IsSuccess);
    }

    [Fact]
    public async Task SetAsync_creates_the_file_with_owner_only_permissions()
    {
        await _store.SetAsync("token", "s3cr3t");

        Assert.True(File.Exists(_filePath));
        var mode = File.GetUnixFileMode(_filePath);
        Assert.Equal(UnixFileMode.UserRead | UnixFileMode.UserWrite, mode);
    }
}
