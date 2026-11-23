using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace SapBulkChange.ViewModels;

public sealed record ConfirmExecuteRequest(
    string EnvironmentName,
    string HostSummary,
    string CompanyCode,
    int DocumentCount,
    int LineCount,
    int? LimitDocs,
    bool IsProduction);

public partial class ConfirmExecuteViewModel : ObservableObject
{
    public ConfirmExecuteRequest Request { get; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanConfirm))]
    private bool _isProductionConfirmed;

    public bool CanConfirm => !Request.IsProduction || IsProductionConfirmed;

    public string SummaryText =>
        $"Environment: {Request.EnvironmentName} ({Request.HostSummary})\n" +
        $"Company Code: {Request.CompanyCode}\n" +
        $"Scope: {Request.LineCount} line(s) across {Request.DocumentCount} document(s)" +
        (Request.LimitDocs is > 0 ? $" (Canary Limit: first {Request.LimitDocs} doc(s))" : string.Empty);

    public event Action<bool>? CloseRequested;

    public ConfirmExecuteViewModel(ConfirmExecuteRequest request)
    {
        Request = request;
    }

    [RelayCommand]
    private void Confirm()
    {
        if (CanConfirm)
            CloseRequested?.Invoke(true);
    }

    [RelayCommand]
    private void Cancel()
    {
        CloseRequested?.Invoke(false);
    }
}
