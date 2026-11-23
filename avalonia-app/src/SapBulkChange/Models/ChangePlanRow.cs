using CommunityToolkit.Mvvm.ComponentModel;

namespace SapBulkChange.Models;

public partial class ChangePlanRow : ObservableObject
{
    public string Doc { get; init; } = string.Empty;
    public string Year { get; init; } = string.Empty;
    public string Item { get; init; } = string.Empty;
    public string Source { get; init; } = string.Empty;
    public string GlAccount { get; init; } = string.Empty;
    public string OldAssignment { get; init; } = string.Empty;
    public string TargetAssignment { get; init; } = string.Empty;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(StatusText))]
    private LineStatus _status;

    [ObservableProperty]
    private string _message = string.Empty;

    public string StatusText => Status.ToString();
    public string ItemType => Source == "BEBAN" ? "S" : "K";
}
