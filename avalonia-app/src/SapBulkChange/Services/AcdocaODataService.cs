using System.Net.Http.Headers;
using System.Text;
using System.Xml.Linq;
using SapBulkChange.Models;

namespace SapBulkChange.Services;

public sealed class AcdocaODataService
{
    private static readonly XNamespace AtomNs = "http://www.w3.org/2005/Atom";
    private static readonly XNamespace MetaNs = "http://schemas.microsoft.com/ado/2007/08/dataservices/metadata";
    public const int DefaultChunkSize = 10;
    public static string StripLeadingZeros(string? value) => (value ?? "").Trim().TrimStart('0');
    private static string Literal(string value) => "'" + value.Replace("'", "''") + "'";
    private static string Set(string url,string start,string end) => $"{url.TrimEnd('/')}(p_sdate={Literal(start)},p_edate={Literal(end)})/Set";

    public async Task<(bool Success, string Message)> TestConnectionAsync(string oDataBaseUrl, string startDate,
        string endDate, string user, string password, bool allowInsecureTls, CancellationToken ct = default)
    {
        using var client = CreateHttpClient(user,password,allowInsecureTls);
        using var response = await client.GetAsync(Set(oDataBaseUrl,startDate,endDate) + "?$top=1",ct);
        return (response.IsSuccessStatusCode,$"HTTP {(int)response.StatusCode} {response.ReasonPhrase}");
    }

    public async Task<Dictionary<(string DocNoZero,string Year),List<AcdocaLine>>> FetchItemsAsync(string oDataBaseUrl,
        string companyCode, IReadOnlyList<(string Doc,string Year)> docKeys, string startDate, string endDate,
        string user,string password,bool allowInsecureTls, Action<string>? log = null,CancellationToken ct = default)
    {
        var result = new Dictionary<(string,string),List<AcdocaLine>>();
        using var client = CreateHttpClient(user,password,allowInsecureTls);
        foreach (var chunk in docKeys.Chunk(DefaultChunkSize))
        {
            var clauses = string.Join(" or ",chunk.Select(d => $"(belnr eq {Literal(d.Doc)} and gjahr eq {Literal(d.Year)})"));
            var filter = $"rbukrs eq {Literal(companyCode)} and rldnr eq '0L' and ({clauses})";
            var uri = Set(oDataBaseUrl,startDate,endDate) + "?$filter=" + Uri.EscapeDataString(filter);
            using var response = await client.GetAsync(uri,ct);
            response.EnsureSuccessStatusCode();
            var lines = ParseAtomFeed(await response.Content.ReadAsStringAsync(ct));
            foreach (var line in lines)
            {
                var key = (StripLeadingZeros(line.Belnr),line.Gjahr);
                if (!result.TryGetValue(key,out var items)) result[key] = items = [];
                items.Add(line);
            }
            log?.Invoke($"ACDOCA lookup: {chunk.Length} documents, {lines.Count} lines");
        }
        return result;
    }

    public static List<AcdocaLine> ParseAtomFeed(string xmlContent)
    {
        var doc = XDocument.Parse(xmlContent);
        if (doc.Root?.Elements(AtomNs + "link").Any(l => (string?)l.Attribute("rel") == "next") == true)
            throw new InvalidDataException("ACDOCA returned a partial page. Reduce the preview scope before executing.");
        var lines = new List<AcdocaLine>();
        foreach (var entry in doc.Descendants(AtomNs + "entry"))
        {
            var props = entry.Element(AtomNs + "content")?.Element(MetaNs + "properties");
            if (props == null) continue;
            var fields = props.Elements().ToDictionary(x => x.Name.LocalName,x => x.Value.Trim(),StringComparer.OrdinalIgnoreCase);
            string F(string key) => fields.GetValueOrDefault(key, "");
            var docln = F("docln");
            if (docln.Length == 0 || !docln.All(char.IsAsciiDigit)) continue;
            var item = docln.Length >= 3 ? docln[^3..] : docln.PadLeft(3,'0');
            lines.Add(new(F("belnr"), F("gjahr"), item, F("racct"), F("zuonr"), F("blart"), ExcelReaderService.ParseDate(F("budat"))));
        }
        return lines;
    }

    public static ChangePlanRow PlanLine(ExcelInputRow row,IReadOnlyList<AcdocaLine> items)
    {
        var doc = items.Where(i => StripLeadingZeros(i.Belnr) == StripLeadingZeros(row.Doc) && i.Gjahr == row.Year).ToList();
        var hits = doc.Where(i => i.Item == row.Item).ToList();
        var hit = hits.Count == 1 ? hits[0] : null;
        var errors = new List<string>();
        var status = LineStatus.PLANNED;
        if (doc.Count == 0) status = LineStatus.DOC_NOT_FOUND;
        else if (hits.Count == 0) status = LineStatus.ITEM_NOT_FOUND;
        else if (hit == null) status = LineStatus.AMBIGUOUS;
        else
        {
            if (!string.Equals(hit.DocumentType,row.DocumentType,StringComparison.OrdinalIgnoreCase)) errors.Add($"Document Type: Excel {row.DocumentType}, SAP {hit.DocumentType}");
            if (hit.PostingDate != row.PostingDate) errors.Add($"Posting Date: Excel {row.PostingDate:yyyyMMdd}, SAP {hit.PostingDate:yyyyMMdd}");
            if (string.IsNullOrEmpty(hit.Racct) || StripLeadingZeros(hit.Racct) != StripLeadingZeros(row.GlAccount)) errors.Add($"G/L Account: Excel {row.GlAccount}, SAP {hit.Racct}");
            if (errors.Count != 0) status = LineStatus.VALIDATION_FAILED;
            else if (hit.CurrentAssignment == row.TargetAssignment) status = LineStatus.SKIPPED_ALREADY_SET;
        }
        return new ChangePlanRow { Doc = row.Doc, Year = row.Year, Item = row.Item, Source = row.Source, GlAccount = row.GlAccount,
            OldAssignment = hit?.CurrentAssignment ?? "", TargetAssignment = row.TargetAssignment, Status = status, Message = string.Join("; ",errors) };
    }

    private static HttpClient CreateHttpClient(string user,string password,bool allowInsecureTls)
    {
        var handler = new HttpClientHandler();
        if (allowInsecureTls) handler.ServerCertificateCustomValidationCallback = HttpClientHandler.DangerousAcceptAnyServerCertificateValidator;
        var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(120) };
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic",Convert.ToBase64String(Encoding.UTF8.GetBytes($"{user}:{password}")));
        return client;
    }
}
