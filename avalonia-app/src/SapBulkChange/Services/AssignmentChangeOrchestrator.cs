using System.Xml.Linq;
using SapBulkChange.Models;

namespace SapBulkChange.Services;

public sealed record ExecutionOptions(
    string ODataBaseUrl,
    string SoapEndpointUrl,
    string CompanyCode,
    string StartDate,
    string EndDate,
    string SapUser,
    string SapPassword,
    bool AllowInsecureTls,
    int BatchDocs,
    int VerifyWaitSeconds,
    int? LimitDocs);

public sealed class AssignmentChangeOrchestrator
{
    private readonly AcdocaODataService _odataService;
    private readonly JournalEntrySoapService _soapService;
    private readonly AuditExportService _auditService;

    public AssignmentChangeOrchestrator(
        AcdocaODataService odataService,
        JournalEntrySoapService soapService,
        AuditExportService auditService)
    {
        _odataService = odataService;
        _soapService = soapService;
        _auditService = auditService;
    }

    public async Task<List<ChangePlanRow>> PreviewAsync(
        IReadOnlyList<ExcelInputRow> excelRows,
        ExecutionOptions options,
        Action<string> log,
        Action<double> progress,
        CancellationToken ct)
    {
        var ts = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        progress(5);

        var docGroups = GroupByDoc(excelRows, options.LimitDocs);
        var docKeys = docGroups.Keys.ToList();
        var totalLines = docGroups.Values.Sum(v => v.Count);
        log($"Preview started: {totalLines} lines in {docKeys.Count} documents (company {options.CompanyCode})");

        progress(15);
        var acdocaMap = await _odataService.FetchItemsAsync(
            options.ODataBaseUrl,
            options.CompanyCode,
            docKeys,
            options.StartDate,
            options.EndDate,
            options.SapUser,
            options.SapPassword,
            options.AllowInsecureTls,
            log,
            ct);

        progress(60);
        var plan = new List<ChangePlanRow>();
        foreach (var ((doc, year), rows) in docGroups)
        {
            acdocaMap.TryGetValue((AcdocaODataService.StripLeadingZeros(doc), year), out var items);
            items ??= [];

            foreach (var r in rows)
            {
                if (items.Count == 0)
                {
                    plan.Add(new ChangePlanRow
                    {
                        Doc = r.Doc,
                        Year = r.Year,
                        Item = string.Empty,
                        Source = r.Source,
                        GlAccount = r.GlAccount,
                        OldAssignment = string.Empty,
                        TargetAssignment = r.TargetAssignment,
                        Status = LineStatus.DOC_NOT_FOUND
                    });
                    continue;
                }

                var (line, status) = AcdocaODataService.ResolveLine(r, items);
                plan.Add(new ChangePlanRow
                {
                    Doc = r.Doc,
                    Year = r.Year,
                    Item = line?.Item ?? string.Empty,
                    Source = r.Source,
                    GlAccount = r.GlAccount,
                    OldAssignment = line?.CurrentAssignment ?? string.Empty,
                    TargetAssignment = r.TargetAssignment,
                    Status = status
                });
            }
        }

        // Local XSD validation for all PLANNED batches
        var plannedRows = plan.Where(p => p.Status == LineStatus.PLANNED).ToList();
        if (plannedRows.Count > 0)
        {
            var batches = ChunkByDoc(plannedRows, Math.Max(1, options.BatchDocs));
            var utcNow = DateTime.UtcNow;
            for (int i = 0; i < batches.Count; i++)
            {
                ct.ThrowIfCancellationRequested();
                var batchNum = i + 1;
                var batchItems = batches[i];
                var rootId = $"ZUONR{ts}_{batchNum:000}";
                var envelope = _soapService.BuildSoapEnvelope(batchItems, options.CompanyCode, rootId, utcNow);
                var reqPath = _auditService.SaveXml(envelope, $"request_{ts}_{batchNum:000}_dryrun.xml");
                var (isValid, errors) = _soapService.ValidateMessage(envelope);

                log($"Batch {batchNum}/{batches.Count}: {batchItems.Count} lines, XSD validation: {(isValid ? "VALID" : "INVALID")} -> {Path.GetFileName(reqPath)}");
                if (!isValid)
                {
                    foreach (var err in errors)
                        log($"  XSD ERROR: {err}");

                    var firstErr = errors.FirstOrDefault() ?? "XSD validation failed";
                    if (firstErr.Length > 200) firstErr = firstErr[..200];

                    foreach (var item in batchItems)
                    {
                        item.Status = LineStatus.XSD_INVALID;
                        item.Message = firstErr;
                    }
                }
            }
        }
        else
        {
            log("No PLANNED changes found after ACDOCA lookup.");
        }

        progress(100);
        return plan;
    }

    public async Task ExecuteAsync(
        IReadOnlyList<ChangePlanRow> plan,
        ExecutionOptions options,
        Action<string> log,
        Action<double> progress,
        CancellationToken ct)
    {
        var ts = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        var plannedRows = plan.Where(p => p.Status == LineStatus.PLANNED).ToList();
        if (plannedRows.Count == 0)
        {
            log("Nothing to execute (0 PLANNED rows).");
            return;
        }

        var batches = ChunkByDoc(plannedRows, Math.Max(1, options.BatchDocs));
        var utcNow = DateTime.UtcNow;

        for (int i = 0; i < batches.Count; i++)
        {
            ct.ThrowIfCancellationRequested();
            var batchNum = i + 1;
            var batchItems = batches[i];
            var rootId = $"ZUONR{ts}_{batchNum:000}";
            var envelope = _soapService.BuildSoapEnvelope(batchItems, options.CompanyCode, rootId, utcNow);
            var reqFile = _auditService.SaveXml(envelope, $"request_{ts}_{batchNum:000}.xml");

            var (isValid, errors) = _soapService.ValidateMessage(envelope);
            if (!isValid)
            {
                var firstErr = errors.FirstOrDefault() ?? "XSD validation failed";
                if (firstErr.Length > 200) firstErr = firstErr[..200];
                log($"Batch {batchNum}/{batches.Count} XSD INVALID (not sent): {firstErr}");
                foreach (var item in batchItems)
                {
                    item.Status = LineStatus.XSD_INVALID;
                    item.Message = firstErr;
                }
                continue;
            }

            try
            {
                log($"Batch {batchNum}/{batches.Count}: sending {batchItems.Count} lines ({Path.GetFileName(reqFile)})...");
                var (statusCode, reason, responseBody, msgId) = await _soapService.SendBatchAsync(
                    options.SoapEndpointUrl,
                    envelope,
                    options.SapUser,
                    options.SapPassword,
                    options.AllowInsecureTls,
                    ct);

                _auditService.SaveText(responseBody, $"response_{ts}_{batchNum:000}.xml");

                if (statusCode is >= 200 and < 300)
                {
                    log($"Batch {batchNum}/{batches.Count}: HTTP {statusCode} {reason} (MessageId={msgId.ToString().ToUpperInvariant()})");
                    foreach (var item in batchItems)
                    {
                        item.Status = LineStatus.SENT;
                        item.Message = $"HTTP {statusCode} (MessageId={msgId.ToString().ToUpperInvariant()})";
                    }
                }
                else
                {
                    var snippet = responseBody.Length > 200 ? responseBody[..200] : responseBody;
                    var errMsg = $"HTTP {statusCode} {reason}: {snippet}";
                    log($"Batch {batchNum}/{batches.Count} SEND_ERROR: {errMsg}");
                    foreach (var item in batchItems)
                    {
                        item.Status = LineStatus.SEND_ERROR;
                        item.Message = errMsg;
                    }
                }
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception ex)
            {
                var errMsg = ex.Message.Length > 200 ? ex.Message[..200] : ex.Message;
                log($"Batch {batchNum}/{batches.Count} SEND_ERROR: {errMsg}");
                foreach (var item in batchItems)
                {
                    item.Status = LineStatus.SEND_ERROR;
                    item.Message = errMsg;
                }
            }

            progress(50.0 * batchNum / batches.Count);
        }

        var sentRows = plan.Where(p => p.Status == LineStatus.SENT).ToList();
        if (sentRows.Count == 0)
        {
            log("No batches were accepted by SAP; skipping verification.");
            progress(100);
            return;
        }

        var waitSeconds = Math.Max(0, options.VerifyWaitSeconds);
        if (waitSeconds > 0)
        {
            log($"Waiting {waitSeconds}s for SAP bgRFC processing before verification...");
            for (int sec = waitSeconds; sec > 0; sec--)
            {
                ct.ThrowIfCancellationRequested();
                progress(50.0 + 30.0 * (waitSeconds - sec) / waitSeconds);
                await Task.Delay(1000, ct);
            }
        }

        await ReVerifyAsync(plan, options, log, p => progress(80.0 + 20.0 * p / 100.0), ct);
        var csvPath = _auditService.ExportCsv(plan);
        log($"Results exported -> {csvPath}");
        progress(100);
    }

    public async Task ReVerifyAsync(
        IReadOnlyList<ChangePlanRow> plan,
        ExecutionOptions options,
        Action<string> log,
        Action<double> progress,
        CancellationToken ct)
    {
        var toVerify = plan
            .Where(p => p.Status is LineStatus.SENT or LineStatus.NOT_CHANGED or LineStatus.VERIFY_ERROR)
            .ToList();

        if (toVerify.Count == 0)
        {
            log("No SENT / NOT_CHANGED / VERIFY_ERROR rows to verify.");
            progress(100);
            return;
        }

        var docKeys = toVerify
            .Select(p => (p.Doc, p.Year))
            .Distinct()
            .ToList();

        log($"Verifying {toVerify.Count} lines across {docKeys.Count} documents via ACDOCA...");
        progress(25);

        try
        {
            var nowItems = await _odataService.FetchItemsAsync(
                options.ODataBaseUrl,
                options.CompanyCode,
                docKeys,
                options.StartDate,
                options.EndDate,
                options.SapUser,
                options.SapPassword,
                options.AllowInsecureTls,
                log,
                ct);

            progress(85);
            foreach (var p in toVerify)
            {
                var docNoZero = AcdocaODataService.StripLeadingZeros(p.Doc);
                nowItems.TryGetValue((docNoZero, p.Year), out var items);
                var match = items?.FirstOrDefault(i => i.Item == p.Item);
                var currentZuonr = match?.CurrentAssignment;

                if (currentZuonr == p.TargetAssignment)
                {
                    p.Status = LineStatus.CHANGED;
                    p.Message = string.Empty;
                }
                else
                {
                    p.Status = LineStatus.NOT_CHANGED;
                    p.Message = $"current value '{currentZuonr ?? "<missing>"}'; check /AIF/ERR (e.g. FINS_ACDOC_POST089) or Re-Verify";
                }
            }

            var changedCount = toVerify.Count(p => p.Status == LineStatus.CHANGED);
            var notChangedCount = toVerify.Count(p => p.Status == LineStatus.NOT_CHANGED);
            log($"Verification complete: {changedCount} CHANGED, {notChangedCount} NOT_CHANGED.");
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            var msg = ex.Message.Length > 200 ? ex.Message[..200] : ex.Message;
            log($"Verification OData error: {msg}");
            foreach (var p in toVerify)
            {
                p.Status = LineStatus.VERIFY_ERROR;
                p.Message = msg;
            }
        }

        progress(100);
    }

    private static Dictionary<(string Doc, string Year), List<ExcelInputRow>> GroupByDoc(
        IReadOnlyList<ExcelInputRow> rows,
        int? limitDocs)
    {
        var groups = new Dictionary<(string Doc, string Year), List<ExcelInputRow>>();
        foreach (var r in rows)
        {
            var key = (r.Doc, r.Year);
            if (!groups.TryGetValue(key, out var list))
            {
                if (limitDocs is > 0 && groups.Count >= limitDocs.Value)
                    continue;
                list = [];
                groups[key] = list;
            }
            list.Add(r);
        }
        return groups;
    }

    private static List<List<ChangePlanRow>> ChunkByDoc(IReadOnlyList<ChangePlanRow> rows, int batchDocs)
    {
        var docKeys = rows.Select(r => (r.Doc, r.Year)).Distinct().ToList();
        var batches = new List<List<ChangePlanRow>>();
        for (int i = 0; i < docKeys.Count; i += batchDocs)
        {
            var keySet = docKeys.Skip(i).Take(batchDocs).ToHashSet();
            batches.Add(rows.Where(r => keySet.Contains((r.Doc, r.Year))).ToList());
        }
        return batches;
    }
}
