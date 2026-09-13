namespace Todo.Core.Tests;

/// <summary>
/// BCL-only fake transport for HttpSyncClient tests — never touches the network, and definitely
/// never the real deployed Worker (that would pollute Michael's live D1 data).
/// </summary>
public sealed class FakeHttpMessageHandler : HttpMessageHandler
{
    public HttpRequestMessage? LastRequest { get; private set; }

    public string? LastRequestBody { get; private set; }

    public int CallCount { get; private set; }

    public Func<HttpRequestMessage, HttpResponseMessage> ResponseFactory { get; set; } =
        _ => new HttpResponseMessage(System.Net.HttpStatusCode.OK)
        {
            Content = new StringContent("{}", System.Text.Encoding.UTF8, "application/json"),
        };

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        CallCount++;
        LastRequest = request;
        LastRequestBody = request.Content is null
            ? null
            : await request.Content.ReadAsStringAsync(cancellationToken);

        return ResponseFactory(request);
    }
}
