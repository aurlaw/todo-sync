using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Todo.Core;

namespace Todo.App.ViewModels;

public sealed partial class SettingsViewModel : ObservableObject
{
    private readonly ISecretStore _secretStore;

    [ObservableProperty]
    private string? _apiToken;

    [ObservableProperty]
    private string? _baseUrl;

    [ObservableProperty]
    private string? _statusMessage;

    /// <summary>Set by the view. Invoked on Save (after a successful write) or Cancel.</summary>
    public Action? RequestClose { get; set; }

    public SettingsViewModel(ISecretStore secretStore)
    {
        _secretStore = secretStore;
    }

    public async Task LoadAsync()
    {
        var tokenResult = await _secretStore.GetAsync(SecretKeys.ApiToken);
        if (tokenResult.IsSuccess)
        {
            ApiToken = tokenResult.Value;
        }

        var baseUrlResult = await _secretStore.GetAsync(SecretKeys.SyncBaseUrl);
        BaseUrl = baseUrlResult.IsSuccess && !string.IsNullOrWhiteSpace(baseUrlResult.Value)
            ? baseUrlResult.Value
            : SyncSettings.DefaultBaseUrl;
    }

    [RelayCommand]
    private async Task Save()
    {
        if (string.IsNullOrWhiteSpace(ApiToken))
        {
            StatusMessage = "Token can't be empty.";
            return;
        }

        if (string.IsNullOrWhiteSpace(BaseUrl) || !Uri.TryCreate(BaseUrl.Trim(), UriKind.Absolute, out _))
        {
            StatusMessage = "Sync server URL must be a valid absolute URL.";
            return;
        }

        var tokenResult = await _secretStore.SetAsync(SecretKeys.ApiToken, ApiToken.Trim());
        if (!tokenResult.IsSuccess)
        {
            StatusMessage = tokenResult.Error;
            return;
        }

        var baseUrlResult = await _secretStore.SetAsync(SecretKeys.SyncBaseUrl, BaseUrl.Trim());
        if (!baseUrlResult.IsSuccess)
        {
            StatusMessage = baseUrlResult.Error;
            return;
        }

        RequestClose?.Invoke();
    }

    [RelayCommand]
    private void Cancel() => RequestClose?.Invoke();
}
