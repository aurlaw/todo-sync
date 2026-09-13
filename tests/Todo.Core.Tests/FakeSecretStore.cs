namespace Todo.Core.Tests;

public sealed class FakeSecretStore : ISecretStore
{
    private readonly Dictionary<string, string> _values = new();

    public Task<Result<string?>> GetAsync(string key, CancellationToken ct = default) =>
        Task.FromResult(Result.Ok<string?>(_values.GetValueOrDefault(key)));

    public Task<Result> SetAsync(string key, string value, CancellationToken ct = default)
    {
        _values[key] = value;
        return Task.FromResult(Result.Ok());
    }

    public Task<Result> DeleteAsync(string key, CancellationToken ct = default)
    {
        _values.Remove(key);
        return Task.FromResult(Result.Ok());
    }
}
