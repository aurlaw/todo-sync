namespace Todo.Core;

public interface ISecretStore
{
    Task<Result<string?>> GetAsync(string key, CancellationToken ct = default);

    Task<Result> SetAsync(string key, string value, CancellationToken ct = default);

    Task<Result> DeleteAsync(string key, CancellationToken ct = default);
}
