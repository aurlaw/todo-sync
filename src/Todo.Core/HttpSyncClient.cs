using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Todo.Core.Models;

namespace Todo.Core;

/// <summary>
/// Talks to the Cloudflare Worker built in Phase 2. Reads both the bearer token and the base URL
/// from <see cref="ISecretStore"/> fresh on every call (not cached at construction) so a value
/// saved later via the Settings view takes effect immediately, without an app restart. Falls back
/// to <see cref="SyncSettings.DefaultBaseUrl"/> when no base URL has been configured yet.
/// </summary>
public sealed class HttpSyncClient : ISyncClient
{
    private readonly HttpClient _httpClient;
    private readonly ISecretStore _secretStore;

    public HttpSyncClient(HttpClient httpClient, ISecretStore secretStore)
    {
        _httpClient = httpClient;
        _secretStore = secretStore;
    }

    public async Task<Result<PushResult>> PushAsync(IReadOnlyList<TodoItem> items, CancellationToken ct = default)
    {
        var authResult = await PrepareRequestAsync(HttpMethod.Post, "push", ct);
        if (!authResult.IsSuccess)
        {
            return Result.Fail<PushResult>(authResult.Error!);
        }

        var request = authResult.Value;
        request.Content = JsonContent.Create(new PushRequestDto { Items = items.Select(TodoWireDto.FromDomain).ToList() });

        try
        {
            using var response = await _httpClient.SendAsync(request, ct);
            if (!response.IsSuccessStatusCode)
            {
                return Result.Fail<PushResult>($"Push failed: HTTP {(int)response.StatusCode}");
            }

            var body = await response.Content.ReadFromJsonAsync<PushResponseDto>(cancellationToken: ct);
            if (body is null)
            {
                return Result.Fail<PushResult>("Push failed: empty response body");
            }

            return Result.Ok(new PushResult
            {
                Applied = body.Applied.Select(a => new PushedItem(a.Id, a.ServerSeq)).ToList(),
                Rejected = body.Rejected.Select(r => new RejectedItem(r.Id, r.Reason)).ToList(),
            });
        }
        catch (Exception ex)
        {
            return Result.Fail<PushResult>($"Push failed: {ex.Message}");
        }
    }

    public async Task<Result<ChangesResult>> GetChangesAsync(long since, CancellationToken ct = default)
    {
        var authResult = await PrepareRequestAsync(HttpMethod.Get, $"changes?since={since}", ct);
        if (!authResult.IsSuccess)
        {
            return Result.Fail<ChangesResult>(authResult.Error!);
        }

        try
        {
            using var response = await _httpClient.SendAsync(authResult.Value, ct);
            if (!response.IsSuccessStatusCode)
            {
                return Result.Fail<ChangesResult>($"Changes failed: HTTP {(int)response.StatusCode}");
            }

            var body = await response.Content.ReadFromJsonAsync<ChangesResponseDto>(cancellationToken: ct);
            if (body is null)
            {
                return Result.Fail<ChangesResult>("Changes failed: empty response body");
            }

            return Result.Ok(new ChangesResult
            {
                Items = body.Items.Select(i => i.ToDomain()).ToList(),
                Cursor = body.Cursor,
            });
        }
        catch (Exception ex)
        {
            return Result.Fail<ChangesResult>($"Changes failed: {ex.Message}");
        }
    }

    private async Task<Result<HttpRequestMessage>> PrepareRequestAsync(HttpMethod method, string relativeUrl, CancellationToken ct)
    {
        var tokenResult = await _secretStore.GetAsync(SecretKeys.ApiToken, ct);
        if (!tokenResult.IsSuccess)
        {
            return Result.Fail<HttpRequestMessage>(tokenResult.Error!);
        }

        if (string.IsNullOrWhiteSpace(tokenResult.Value))
        {
            return Result.Fail<HttpRequestMessage>("API token not configured");
        }

        var baseUrlResult = await _secretStore.GetAsync(SecretKeys.SyncBaseUrl, ct);
        if (!baseUrlResult.IsSuccess)
        {
            return Result.Fail<HttpRequestMessage>(baseUrlResult.Error!);
        }

        var baseUrl = string.IsNullOrWhiteSpace(baseUrlResult.Value) ? SyncSettings.DefaultBaseUrl : baseUrlResult.Value;
        if (!Uri.TryCreate(baseUrl.TrimEnd('/') + "/" + relativeUrl, UriKind.Absolute, out var uri))
        {
            return Result.Fail<HttpRequestMessage>($"Invalid sync server URL: {baseUrl}");
        }

        var request = new HttpRequestMessage(method, uri);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tokenResult.Value);
        return Result.Ok(request);
    }

    private sealed class PushRequestDto
    {
        [JsonPropertyName("items")]
        public required IReadOnlyList<TodoWireDto> Items { get; init; }
    }

    private sealed class PushResponseDto
    {
        [JsonPropertyName("applied")]
        public required IReadOnlyList<AppliedDto> Applied { get; init; }

        [JsonPropertyName("rejected")]
        public required IReadOnlyList<RejectedDto> Rejected { get; init; }
    }

    private sealed class AppliedDto
    {
        [JsonPropertyName("id")]
        public required Guid Id { get; init; }

        [JsonPropertyName("serverSeq")]
        public required long ServerSeq { get; init; }
    }

    private sealed class RejectedDto
    {
        [JsonPropertyName("id")]
        public required Guid Id { get; init; }

        [JsonPropertyName("reason")]
        public required string Reason { get; init; }
    }

    private sealed class ChangesResponseDto
    {
        [JsonPropertyName("items")]
        public required IReadOnlyList<TodoWireDto> Items { get; init; }

        [JsonPropertyName("cursor")]
        public required long Cursor { get; init; }
    }

    /// <summary>
    /// The camelCase wire shape from `worker/src/types.ts`'s TodoDto. Dates are plain strings
    /// (via <see cref="Iso8601"/>), not DateTimeOffset — System.Text.Json's own DateTimeOffset
    /// converter isn't guaranteed to match the exact "O" format the Worker's string-comparison
    /// upsert relies on. `recurrence` is passed through completely opaque: whatever
    /// SqliteTodoRepository already serialized (default JsonSerializer settings, PascalCase,
    /// integer enums), never re-parsed or re-shaped here.
    /// </summary>
    private sealed class TodoWireDto
    {
        [JsonPropertyName("id")]
        public required Guid Id { get; init; }

        [JsonPropertyName("title")]
        public required string Title { get; init; }

        [JsonPropertyName("notes")]
        public string? Notes { get; init; }

        [JsonPropertyName("isDone")]
        public required bool IsDone { get; init; }

        [JsonPropertyName("dueAt")]
        public string? DueAt { get; init; }

        [JsonPropertyName("recurrence")]
        public string? Recurrence { get; init; }

        [JsonPropertyName("createdAt")]
        public required string CreatedAt { get; init; }

        [JsonPropertyName("updatedAt")]
        public required string UpdatedAt { get; init; }

        [JsonPropertyName("isDeleted")]
        public required bool IsDeleted { get; init; }

        [JsonPropertyName("serverSeq")]
        public long? ServerSeq { get; init; }

        public static TodoWireDto FromDomain(TodoItem item) => new()
        {
            Id = item.Id,
            Title = item.Title,
            Notes = item.Notes,
            IsDone = item.IsDone,
            DueAt = item.DueAt is { } dueAt ? Iso8601.Format(dueAt) : null,
            Recurrence = item.Recurrence is { } recurrence
                ? JsonSerializer.Serialize(recurrence)
                : null,
            CreatedAt = Iso8601.Format(item.CreatedAt),
            UpdatedAt = Iso8601.Format(item.UpdatedAt),
            IsDeleted = item.IsDeleted,
            ServerSeq = item.ServerSeq,
        };

        public TodoItem ToDomain() => new()
        {
            Id = Id,
            Title = Title,
            Notes = Notes,
            IsDone = IsDone,
            DueAt = DueAt is { } dueAt ? Iso8601.Parse(dueAt) : null,
            Recurrence = Recurrence is { } recurrence
                ? JsonSerializer.Deserialize<RecurrenceRule>(recurrence)
                : null,
            CreatedAt = Iso8601.Parse(CreatedAt),
            UpdatedAt = Iso8601.Parse(UpdatedAt),
            IsDeleted = IsDeleted,
            ServerSeq = ServerSeq,
        };
    }
}
