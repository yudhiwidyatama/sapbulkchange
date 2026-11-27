using System.Collections.ObjectModel;
using Avalonia.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using SapBulkChange.Models;
using SapBulkChange.Services;

namespace SapBulkChange.ViewModels;

public partial class MainWindowViewModel : ObservableObject
{
    private readonly ProfileConfigService _profileService;
    private readonly ExcelReaderService _excelService;
    private readonly AcdocaODataService _odataService;
    private readonly AuditExportService _auditService;
    private readonly AssignmentChangeOrchestrator _orchestrator;

    private readonly List<ExcelInputRow> _parsedExcelRows = [];
    private readonly List<ChangePlanRow> _allPlanRows = [];
    private CancellationTokenSource? _cts;

    public ObservableCollection<SapProfile> Profiles { get; } = [];
    public ObservableCollection<ChangePlanRow> FilteredRows { get; } = [];
    public ObservableCollection<string> LogLines { get; } = [];

    [ObservableProperty]
    private SapProfile? _selectedProfile;

    [ObservableProperty]
    private string _companyCode = "1000";

    [ObservableProperty]
    private string _startDate = "20160101";

    [ObservableProperty]
    private string _endDate = "20201231";

    [ObservableProperty]
    private string _sapUser = string.Empty;

    [ObservableProperty]
    private string _sapPassword = string.Empty;

    [ObservableProperty]
    private bool _isAdvancedExpanded;

    [ObservableProperty]
    private string _oDataBaseUrl = string.Empty;

    [ObservableProperty]
    private string _soapEndpointUrl = string.Empty;

    [ObservableProperty]
    private string _sapClient = "100";

    [ObservableProperty]
    private int _batchDocs = 50;

    [ObservableProperty]
    private int _verifyWaitSeconds = 30;

    [ObservableProperty]
    private bool _allowInsecureTls = true;

    [ObservableProperty]
    private string _excelFilePath = string.Empty;

    [ObservableProperty]
    private string _excelSummaryText = "Drop an .xlsx file here or click Browse...";

    [ObservableProperty]
    private bool _useLimitDocs;

    [ObservableProperty]
    private int _limitDocs = 1;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsNotBusy))]
    private bool _isBusy;

    public bool IsNotBusy => !IsBusy;

    [ObservableProperty]
    private double _progressValue;

    [ObservableProperty]
    private bool _isLogExpanded = true;

    [ObservableProperty]
    private string _searchText = string.Empty;

    [ObservableProperty]
    private string _activeFilter = "All";

    [ObservableProperty]
    private bool _canExecute;

    [ObservableProperty]
    private bool _canReVerify;

    [ObservableProperty]
    private bool _canExport;

    [ObservableProperty]
    private int _totalCount;

    [ObservableProperty]
    private int _plannedCount;

    [ObservableProperty]
    private int _changedCount;

    [ObservableProperty]
    private int _skippedCount;

    [ObservableProperty]
    private int _errorCount;

    public string EnvironmentBannerText
    {
        get
        {
            var name = SelectedProfile?.Name ?? "QAS";
            var host = Uri.TryCreate(SoapEndpointUrl, UriKind.Absolute, out var uri) ? uri.Host : SoapEndpointUrl;
            var tag = SelectedProfile?.IsProduction == true ? "PRODUCTION" : "NON-PRODUCTION";
            return $"ENVIRONMENT: {name} ({host}) — {tag}";
        }
    }

    public bool IsProductionEnvironment => SelectedProfile?.IsProduction == true;

    public Func<Task<string?>>? BrowseExcelRequested { get; set; }
    public Func<Task<string?>>? SaveCsvRequested { get; set; }
    public Func<ConfirmExecuteRequest, Task<bool>>? ConfirmExecuteRequested { get; set; }
    public Action<string>? OpenFolderRequested { get; set; }

    public MainWindowViewModel()
    {
        _profileService = new ProfileConfigService();
        _excelService = new ExcelReaderService();
        _odataService = new AcdocaODataService();
        _auditService = new AuditExportService();
        var soapService = new JournalEntrySoapService();
        _orchestrator = new AssignmentChangeOrchestrator(_odataService, soapService, _auditService);

        foreach (var profile in _profileService.LoadProfiles())
            Profiles.Add(profile);

        SelectedProfile = Profiles.FirstOrDefault();
    }

    partial void OnSelectedProfileChanged(SapProfile? value)
    {
        if (value is null)
            return;

        ODataBaseUrl = value.ODataBaseUrl;
        SoapEndpointUrl = value.SoapEndpointUrl;
        SapClient = value.SapClient;
        CompanyCode = value.DefaultCompanyCode;
        StartDate = value.DefaultStartDate;
        EndDate = value.DefaultEndDate;
        BatchDocs = value.BatchDocs;
        VerifyWaitSeconds = value.VerifyWaitSeconds;
        AllowInsecureTls = value.AllowInsecureTls;
        OnPropertyChanged(nameof(EnvironmentBannerText));
        OnPropertyChanged(nameof(IsProductionEnvironment));
    }

    partial void OnSoapEndpointUrlChanged(string value) => OnPropertyChanged(nameof(EnvironmentBannerText));
    partial void OnSearchTextChanged(string value) => ApplyFilterAndCounts();
    partial void OnActiveFilterChanged(string value) => ApplyFilterAndCounts();

    public void LoadExcelFile(string filePath)
    {
        try
        {
            _allPlanRows.Clear();
            _parsedExcelRows.Clear();
            ApplyFilterAndCounts();
            ExcelFilePath = filePath;
            var result = _excelService.Read(filePath);
            _parsedExcelRows.Clear();
            _parsedExcelRows.AddRange(result.Rows);

            var docCount = _parsedExcelRows.Select(r => (r.Doc, r.Year)).Distinct().Count();
            ExcelSummaryText = $"Parsed: {_parsedExcelRows.Count} rows | {docCount} documents | {result.Warnings.Count} Excel validation warnings";
            AppendLog($"Loaded Excel: {Path.GetFileName(filePath)} ({_parsedExcelRows.Count} rows, {docCount} docs, {result.Warnings.Count} warnings)");

            foreach (var w in result.Warnings)
                AppendLog($"  WARNING Excel row {w.XlRow}: {w.Message}");

            _allPlanRows.Clear();
            ApplyFilterAndCounts();
        }
        catch (Exception ex)
        {
            ExcelSummaryText = $"Error reading Excel: {ex.Message}";
            AppendLog($"ERROR reading Excel: {ex.Message}");
        }
    }

    [RelayCommand]
    private async Task BrowseExcelAsync()
    {
        if (BrowseExcelRequested is null)
            return;

        var path = await BrowseExcelRequested();
        if (!string.IsNullOrWhiteSpace(path))
            LoadExcelFile(path);
    }

    [RelayCommand]
    private async Task TestConnectionAsync()
    {
        if (!ValidateCredentials())
            return;

        await RunBusyAsync(async ct =>
        {
            AppendLog($"Testing OData connection to {ODataBaseUrl}...");
            var (ok, msg) = await _odataService.TestConnectionAsync(
                ODataBaseUrl, StartDate, EndDate, SapUser, SapPassword, AllowInsecureTls, ct);
            AppendLog(ok ? $"Connection OK: {msg}" : $"Connection FAILED: {msg}");
        });
    }

    [RelayCommand]
    private async Task PreviewPlanAsync()
    {
        if (_parsedExcelRows.Count == 0)
        {
            AppendLog("Please load a valid Excel file first.");
            return;
        }
        if (!ValidateCredentials())
            return;

        await RunBusyAsync(async ct =>
        {
            var options = BuildExecutionOptions();
            var rows = await _orchestrator.PreviewAsync(
                _parsedExcelRows,
                options,
                AppendLog,
                p => Dispatch(() => ProgressValue = p),
                ct);

            Dispatch(() =>
            {
                _allPlanRows.Clear();
                _allPlanRows.AddRange(rows);
                ApplyFilterAndCounts();
            });

            var ts = DateTime.Now.ToString("yyyyMMdd_HHmmss");
            _auditService.WriteLog(LogLines.ToList(), ts, isDryRun: true);
        });
    }

    [RelayCommand]
    private async Task ExecuteChangesAsync()
    {
        var planned = _allPlanRows.Where(r => r.Status == LineStatus.PLANNED).ToList();
        if (planned.Count == 0)
        {
            AppendLog("No PLANNED rows to execute.");
            return;
        }
        if (!ValidateCredentials())
            return;

        var docCount = planned.Select(p => (p.Doc, p.Year)).Distinct().Count();
        var host = Uri.TryCreate(SoapEndpointUrl, UriKind.Absolute, out var uri) ? uri.Host : SoapEndpointUrl;
        var request = new ConfirmExecuteRequest(
            SelectedProfile?.Name ?? "QAS",
            host,
            CompanyCode,
            docCount,
            planned.Count,
            UseLimitDocs ? LimitDocs : null,
            IsProductionEnvironment);

        if (ConfirmExecuteRequested is not null)
        {
            var confirmed = await ConfirmExecuteRequested(request);
            if (!confirmed)
            {
                AppendLog("Execution cancelled by user at confirmation dialog.");
                return;
            }
        }

        await RunBusyAsync(async ct =>
        {
            var options = BuildExecutionOptions();
            await _orchestrator.ExecuteAsync(
                _allPlanRows,
                options,
                AppendLog,
                p => Dispatch(() => ProgressValue = p),
                ct);

            Dispatch(ApplyFilterAndCounts);
            var ts = DateTime.Now.ToString("yyyyMMdd_HHmmss");
            _auditService.WriteLog(LogLines.ToList(), ts, isDryRun: false);
        });
    }

    [RelayCommand]
    private async Task ReVerifyAsync()
    {
        if (!ValidateCredentials())
            return;

        await RunBusyAsync(async ct =>
        {
            var options = BuildExecutionOptions();
            await _orchestrator.ReVerifyAsync(
                _allPlanRows,
                options,
                AppendLog,
                p => Dispatch(() => ProgressValue = p),
                ct);

            Dispatch(ApplyFilterAndCounts);
            var csvPath = _auditService.ExportCsv(_allPlanRows);
            AppendLog($"Updated CSV exported -> {csvPath}");
        });
    }

    [RelayCommand]
    private async Task ExportCsvAsync()
    {
        if (_allPlanRows.Count == 0)
            return;

        string? path = null;
        if (SaveCsvRequested is not null)
            path = await SaveCsvRequested();

        var exported = _auditService.ExportCsv(_allPlanRows, path);
        AppendLog($"Exported CSV -> {exported}");
    }

    [RelayCommand]
    private void OpenLogs()
    {
        OpenFolderRequested?.Invoke(_auditService.LogDirectory);
    }

    [RelayCommand]
    private void Cancel()
    {
        _cts?.Cancel();
        AppendLog("Cancellation requested...");
    }

    [RelayCommand]
    private void SetFilter(string filter)
    {
        ActiveFilter = filter;
    }

    private ExecutionOptions BuildExecutionOptions() => new(
        ODataBaseUrl,
        SoapEndpointUrl,
        CompanyCode.Trim(),
        StartDate.Trim(),
        EndDate.Trim(),
        SapUser.Trim(),
        SapPassword,
        AllowInsecureTls,
        BatchDocs,
        VerifyWaitSeconds,
        UseLimitDocs ? LimitDocs : null);

    private bool ValidateCredentials()
    {
        if (string.IsNullOrWhiteSpace(SapUser) || string.IsNullOrWhiteSpace(SapPassword))
        {
            AppendLog("ERROR: SAP User and Password are required.");
            return false;
        }
        return true;
    }

    private async Task RunBusyAsync(Func<CancellationToken, Task> action)
    {
        if (IsBusy)
            return;

        _cts?.Dispose();
        _cts = new CancellationTokenSource();
        IsBusy = true;
        ProgressValue = 0;

        try
        {
            await Task.Run(() => action(_cts.Token), _cts.Token);
        }
        catch (OperationCanceledException)
        {
            AppendLog("Operation cancelled.");
        }
        catch (Exception ex)
        {
            AppendLog($"ERROR: {ex.Message}");
        }
        finally
        {
            IsBusy = false;
            ApplyFilterAndCounts();
        }
    }

    private void ApplyFilterAndCounts()
    {
        TotalCount = _allPlanRows.Count;
        PlannedCount = _allPlanRows.Count(r => r.Status == LineStatus.PLANNED);
        ChangedCount = _allPlanRows.Count(r => r.Status == LineStatus.CHANGED);
        SkippedCount = _allPlanRows.Count(r => r.Status == LineStatus.SKIPPED_ALREADY_SET);
        ErrorCount = _allPlanRows.Count(r => r.Status is
            LineStatus.VALIDATION_FAILED or LineStatus.ITEM_NOT_FOUND or LineStatus.DOC_NOT_FOUND or LineStatus.NO_MATCH or LineStatus.AMBIGUOUS or
            LineStatus.XSD_INVALID or LineStatus.SEND_ERROR or LineStatus.NOT_CHANGED or LineStatus.VERIFY_ERROR);

        CanExecute = !IsBusy && PlannedCount > 0;
        CanReVerify = !IsBusy && _allPlanRows.Any(r => r.Status is LineStatus.SENT or LineStatus.NOT_CHANGED or LineStatus.VERIFY_ERROR);
        CanExport = _allPlanRows.Count > 0;

        var query = _allPlanRows.AsEnumerable();
        query = ActiveFilter switch
        {
            "Planned" => query.Where(r => r.Status == LineStatus.PLANNED),
            "Changed" => query.Where(r => r.Status == LineStatus.CHANGED),
            "Skipped" => query.Where(r => r.Status == LineStatus.SKIPPED_ALREADY_SET),
            "Errors" => query.Where(r => r.Status is
                LineStatus.VALIDATION_FAILED or LineStatus.ITEM_NOT_FOUND or LineStatus.DOC_NOT_FOUND or LineStatus.NO_MATCH or LineStatus.AMBIGUOUS or
                LineStatus.XSD_INVALID or LineStatus.SEND_ERROR or LineStatus.NOT_CHANGED or LineStatus.VERIFY_ERROR),
            _ => query
        };

        if (!string.IsNullOrWhiteSpace(SearchText))
        {
            var term = SearchText.Trim();
            query = query.Where(r =>
                r.Doc.Contains(term, StringComparison.OrdinalIgnoreCase) ||
                r.OldAssignment.Contains(term, StringComparison.OrdinalIgnoreCase) ||
                r.TargetAssignment.Contains(term, StringComparison.OrdinalIgnoreCase) ||
                r.StatusText.Contains(term, StringComparison.OrdinalIgnoreCase) ||
                r.Message.Contains(term, StringComparison.OrdinalIgnoreCase));
        }

        FilteredRows.Clear();
        foreach (var row in query)
            FilteredRows.Add(row);
    }

    private void AppendLog(string message)
    {
        var line = $"{DateTime.Now:HH:mm:ss} {message}";
        Dispatch(() => LogLines.Add(line));
    }

    private static void Dispatch(Action action)
    {
        if (Dispatcher.UIThread.CheckAccess())
            action();
        else
            Dispatcher.UIThread.Post(action);
    }
}
