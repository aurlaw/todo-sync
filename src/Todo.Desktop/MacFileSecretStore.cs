using System.Runtime.Versioning;
using System.Text.Json;
using Todo.Core;

namespace Todo.Desktop;

/// <summary>
/// Stores secrets in a chmod 600 JSON file. Chosen over the macOS Keychain (via the
/// `security` CLI) because a background sync call can otherwise trigger an interactive
/// Keychain access prompt.
/// </summary>
[SupportedOSPlatform("macos")]
public sealed class MacFileSecretStore : ISecretStore
{
    private readonly string _filePath;
    private readonly SemaphoreSlim _lock = new(1, 1);

    public MacFileSecretStore(string filePath)
    {
        _filePath = filePath;
    }

    public async Task<Result<string?>> GetAsync(string key, CancellationToken ct = default)
    {
        await _lock.WaitAsync(ct);
        try
        {
            var secrets = await ReadAllAsync(ct);
            return Result.Ok(secrets.GetValueOrDefault(key));
        }
        catch (Exception ex)
        {
            return Result.Fail<string?>($"Failed to read secret: {ex.Message}");
        }
        finally
        {
            _lock.Release();
        }
    }

    public async Task<Result> SetAsync(string key, string value, CancellationToken ct = default)
    {
        await _lock.WaitAsync(ct);
        try
        {
            var secrets = await ReadAllAsync(ct);
            secrets[key] = value;
            await WriteAllAsync(secrets, ct);
            return Result.Ok();
        }
        catch (Exception ex)
        {
            return Result.Fail($"Failed to write secret: {ex.Message}");
        }
        finally
        {
            _lock.Release();
        }
    }

    public async Task<Result> DeleteAsync(string key, CancellationToken ct = default)
    {
        await _lock.WaitAsync(ct);
        try
        {
            var secrets = await ReadAllAsync(ct);
            secrets.Remove(key);
            await WriteAllAsync(secrets, ct);
            return Result.Ok();
        }
        catch (Exception ex)
        {
            return Result.Fail($"Failed to delete secret: {ex.Message}");
        }
        finally
        {
            _lock.Release();
        }
    }

    private async Task<Dictionary<string, string>> ReadAllAsync(CancellationToken ct)
    {
        if (!File.Exists(_filePath))
        {
            return new Dictionary<string, string>();
        }

        await using var stream = File.OpenRead(_filePath);
        var secrets = await JsonSerializer.DeserializeAsync<Dictionary<string, string>>(stream, cancellationToken: ct);
        return secrets ?? new Dictionary<string, string>();
    }

    private async Task WriteAllAsync(Dictionary<string, string> secrets, CancellationToken ct)
    {
        var directory = Path.GetDirectoryName(_filePath);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        await using (var stream = File.Create(_filePath))
        {
            await JsonSerializer.SerializeAsync(stream, secrets, cancellationToken: ct);
        }

        File.SetUnixFileMode(_filePath, UnixFileMode.UserRead | UnixFileMode.UserWrite);
    }
}
