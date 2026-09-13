using System.Net;
using System.Text;
using System.Text.Json;
using Todo.Core.Models;

namespace Todo.Core.Tests;

public sealed class HttpSyncClientTests
{
    private static HttpSyncClient CreateClient(FakeHttpMessageHandler handler, FakeSecretStore secretStore) =>
        new(new HttpClient(handler) { BaseAddress = new Uri("https://example.test/") }, secretStore);

    private static HttpResponseMessage JsonResponse(string json) => new(HttpStatusCode.OK)
    {
        Content = new StringContent(json, Encoding.UTF8, "application/json"),
    };

    [Fact]
    public async Task PushAsync_sends_camelCase_wire_shape_with_opaque_recurrence()
    {
        var handler = new FakeHttpMessageHandler { ResponseFactory = _ => JsonResponse("""{"applied":[],"rejected":[]}""") };
        var secretStore = new FakeSecretStore();
        await secretStore.SetAsync(SecretKeys.ApiToken, "test-token");
        var client = CreateClient(handler, secretStore);

        var item = new TodoItem
        {
            Id = Guid.NewGuid(),
            Title = "Buy milk",
            Notes = "2%",
            IsDone = false,
            DueAt = new DateTimeOffset(2026, 3, 1, 0, 0, 0, TimeSpan.Zero),
            Recurrence = new RecurrenceRule { Frequency = RecurrenceFrequency.Weekly, Interval = 1, DaysOfWeek = [DayOfWeek.Monday] },
            CreatedAt = new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero),
            UpdatedAt = new DateTimeOffset(2026, 1, 2, 0, 0, 0, TimeSpan.Zero),
            IsDeleted = false,
        };

        var result = await client.PushAsync([item]);

        Assert.True(result.IsSuccess);
        Assert.NotNull(handler.LastRequestBody);

        using var doc = JsonDocument.Parse(handler.LastRequestBody!);
        var wireItem = doc.RootElement.GetProperty("items")[0];

        Assert.Equal(item.Id.ToString(), wireItem.GetProperty("id").GetString());
        Assert.Equal("Buy milk", wireItem.GetProperty("title").GetString());
        Assert.Equal("2%", wireItem.GetProperty("notes").GetString());
        Assert.False(wireItem.GetProperty("isDone").GetBoolean());
        Assert.Equal(Iso8601.Format(item.DueAt!.Value), wireItem.GetProperty("dueAt").GetString());
        Assert.Equal(Iso8601.Format(item.UpdatedAt), wireItem.GetProperty("updatedAt").GetString());
        Assert.False(wireItem.GetProperty("isDeleted").GetBoolean());

        // recurrence must be passed through exactly as SqliteTodoRepository would serialize it —
        // opaque, never re-shaped into the wire DTO's own camelCase conventions.
        var expectedRecurrence = JsonSerializer.Serialize(item.Recurrence);
        Assert.Equal(expectedRecurrence, wireItem.GetProperty("recurrence").GetString());
    }

    [Fact]
    public async Task PushAsync_sends_bearer_token_header()
    {
        var handler = new FakeHttpMessageHandler { ResponseFactory = _ => JsonResponse("""{"applied":[],"rejected":[]}""") };
        var secretStore = new FakeSecretStore();
        await secretStore.SetAsync(SecretKeys.ApiToken, "my-secret-token");
        var client = CreateClient(handler, secretStore);

        await client.PushAsync([]);

        Assert.Equal("Bearer", handler.LastRequest!.Headers.Authorization!.Scheme);
        Assert.Equal("my-secret-token", handler.LastRequest.Headers.Authorization.Parameter);
    }

    [Fact]
    public async Task PushAsync_without_a_configured_token_short_circuits_without_a_network_call()
    {
        var handler = new FakeHttpMessageHandler();
        var secretStore = new FakeSecretStore(); // no token set
        var client = CreateClient(handler, secretStore);

        var result = await client.PushAsync([]);

        Assert.False(result.IsSuccess);
        Assert.Equal(0, handler.CallCount);
    }

    [Fact]
    public async Task GetChangesAsync_maps_camelCase_response_into_domain_items()
    {
        var id = Guid.NewGuid();
        var responseJson = $$"""
            {
              "items": [
                {
                  "id": "{{id}}",
                  "title": "From server",
                  "notes": null,
                  "isDone": true,
                  "dueAt": null,
                  "recurrence": null,
                  "createdAt": "2026-01-01T00:00:00.0000000+00:00",
                  "updatedAt": "2026-01-02T00:00:00.0000000+00:00",
                  "isDeleted": false,
                  "serverSeq": 3
                }
              ],
              "cursor": 3
            }
            """;
        var handler = new FakeHttpMessageHandler { ResponseFactory = _ => JsonResponse(responseJson) };
        var secretStore = new FakeSecretStore();
        await secretStore.SetAsync(SecretKeys.ApiToken, "test-token");
        var client = CreateClient(handler, secretStore);

        var result = await client.GetChangesAsync(0);

        Assert.True(result.IsSuccess);
        Assert.Equal(3, result.Value.Cursor);
        var item = Assert.Single(result.Value.Items);
        Assert.Equal(id, item.Id);
        Assert.Equal("From server", item.Title);
        Assert.True(item.IsDone);
        Assert.Equal(3, item.ServerSeq);
    }

    [Fact]
    public async Task GetChangesAsync_includes_since_in_the_request_url()
    {
        var handler = new FakeHttpMessageHandler { ResponseFactory = _ => JsonResponse("""{"items":[],"cursor":0}""") };
        var secretStore = new FakeSecretStore();
        await secretStore.SetAsync(SecretKeys.ApiToken, "test-token");
        var client = CreateClient(handler, secretStore);

        await client.GetChangesAsync(42);

        Assert.Contains("since=42", handler.LastRequest!.RequestUri!.ToString());
    }

    [Fact]
    public async Task Requests_use_the_default_base_url_when_none_is_configured()
    {
        var handler = new FakeHttpMessageHandler { ResponseFactory = _ => JsonResponse("""{"items":[],"cursor":0}""") };
        var secretStore = new FakeSecretStore();
        await secretStore.SetAsync(SecretKeys.ApiToken, "test-token");
        var client = CreateClient(handler, secretStore);

        await client.GetChangesAsync(0);

        Assert.StartsWith(SyncSettings.DefaultBaseUrl, handler.LastRequest!.RequestUri!.ToString());
    }

    [Fact]
    public async Task Requests_use_the_configured_base_url_when_one_is_set()
    {
        var handler = new FakeHttpMessageHandler { ResponseFactory = _ => JsonResponse("""{"items":[],"cursor":0}""") };
        var secretStore = new FakeSecretStore();
        await secretStore.SetAsync(SecretKeys.ApiToken, "test-token");
        await secretStore.SetAsync(SecretKeys.SyncBaseUrl, "https://staging.example.com");
        var client = CreateClient(handler, secretStore);

        await client.GetChangesAsync(0);

        Assert.StartsWith("https://staging.example.com/", handler.LastRequest!.RequestUri!.ToString());
    }

    [Fact]
    public async Task GetChangesAsync_reports_failure_for_a_non_success_status_code()
    {
        var handler = new FakeHttpMessageHandler { ResponseFactory = _ => new HttpResponseMessage(HttpStatusCode.Unauthorized) };
        var secretStore = new FakeSecretStore();
        await secretStore.SetAsync(SecretKeys.ApiToken, "wrong-token");
        var client = CreateClient(handler, secretStore);

        var result = await client.GetChangesAsync(0);

        Assert.False(result.IsSuccess);
    }
}
