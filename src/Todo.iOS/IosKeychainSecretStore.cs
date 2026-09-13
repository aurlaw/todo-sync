using Foundation;
using Security;
using Todo.Core;

namespace Todo.iOS;

public sealed class IosKeychainSecretStore : ISecretStore
{
    private const string ServiceName = "com.aurlaw.todosync";

    public Task<Result<string?>> GetAsync(string key, CancellationToken ct = default)
    {
        var query = new SecRecord(SecKind.GenericPassword) { Service = ServiceName, Account = key };
        var record = SecKeyChain.QueryAsRecord(query, out var status);

        if (status == SecStatusCode.ItemNotFound)
        {
            return Task.FromResult(Result.Ok<string?>(null));
        }

        if (status != SecStatusCode.Success || record?.ValueData is null)
        {
            return Task.FromResult(Result.Fail<string?>($"Keychain read failed: {status}"));
        }

        return Task.FromResult(Result.Ok<string?>(record.ValueData.ToString(NSStringEncoding.UTF8)));
    }

    public Task<Result> SetAsync(string key, string value, CancellationToken ct = default)
    {
        var query = new SecRecord(SecKind.GenericPassword) { Service = ServiceName, Account = key };
        var valueData = NSData.FromString(value, NSStringEncoding.UTF8);

        var existing = SecKeyChain.QueryAsRecord(query, out var findStatus);
        SecStatusCode status;
        if (findStatus == SecStatusCode.Success && existing is not null)
        {
            // The "new attributes" record must NOT set SecKind — that implicitly sets kSecClass,
            // which SecItemUpdate rejects with errSecNoSuchAttr (class isn't an updatable attribute).
            status = SecKeyChain.Update(query, new SecRecord { ValueData = valueData });
        }
        else
        {
            var record = new SecRecord(SecKind.GenericPassword) { Service = ServiceName, Account = key, ValueData = valueData };
            status = SecKeyChain.Add(record);
        }

        return Task.FromResult(status == SecStatusCode.Success
            ? Result.Ok()
            : Result.Fail($"Keychain write failed: {status}"));
    }

    public Task<Result> DeleteAsync(string key, CancellationToken ct = default)
    {
        var query = new SecRecord(SecKind.GenericPassword) { Service = ServiceName, Account = key };
        var status = SecKeyChain.Remove(query);

        return Task.FromResult(status is SecStatusCode.Success or SecStatusCode.ItemNotFound
            ? Result.Ok()
            : Result.Fail($"Keychain delete failed: {status}"));
    }
}
