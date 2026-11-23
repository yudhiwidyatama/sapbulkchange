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

    public static string StripLeadingZeros(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
            return string.Empty;
        return value.Trim().TrimStart('0');
    }

    public async Task<(bool Success, string Message)> TestConnectionAsync(
        string oDataBaseUrl,
        string startDate,
        string endDate,
        string user,
        string password,
        bool allowInsecureTls,
        CancellationToken ct = default)
    {
        using var client = CreateHttpClient(user, password, allowInsecureTls);
        var url = $"{oDataBaseUrl.TrimEnd('/')}(p_sdate='{startDate}',p_edate='{endDate}')/Set?$top=1";
        using var response = await client.GetAsync(url, ct);
        if (response.IsSuccessStatusCode)
            return (true, $"HTTP {(int)response.StatusCode} {response.ReasonPhrase}");

        var body = await response.Content.ReadAsStringAsync(ct);
        var snippet = body.Length > 300 ? body[..300] : body;
        return (false, $"HTTP {(int)response.StatusCode} {response.ReasonPhrase}: {snippet}");
    }

    public async Task<Dictionary<(string DocNoZero, string Year), List<AcdocaLine>>> FetchItemsAsync(
        string oDataBaseUrl,
        string companyCode,
        IReadOnlyList<(string Doc, string Year)> docKeys,
        string startDate,
        string endDate,
        string user,
        string password,
        bool allowInsecureTls,
        Action<string>? log = null,
        CancellationToken ct = default)
    {
        var result = new Dictionary<(string DocNoZero, string Year), List<AcdocaLine>>();
        if (docKeys.Count == 0)
            return result;

        using var client = CreateHttpClient(user, password, allowInsecureTls);
        var totalChunks = (int)Math.Ceiling(docKeys.Count / (double)DefaultChunkSize);
        var totalLines = 0;

        for (int i = 0; i < docKeys.Count; i += DefaultChunkSize)
        {
            ct.ThrowIfCancellationRequested();
            var chunkIndex = i / DefaultChunkSize + 1;
            var part = docKeys.Skip(i).Take(DefaultChunkSize).ToList();

            var docClauses = string.Join(" or ", part.Select(d => $"(belnr eq '{d.Doc}' and gjahr eq '{d.Year}')"));
            var filter = $"rbukrs eq '{companyCode}' and rldnr eq '0L' and ({docClauses})";
            var url = $"{oDataBaseUrl.TrimEnd('/')}(p_sdate='{startDate}',p_edate='{endDate}')/Set?$filter={Uri.EscapeDataString(filter)}";

            using var response = await client.GetAsync(url, ct);
            var content = await response.Content.ReadAsStringAsync(ct);

            if (!response.IsSuccessStatusCode)
            {
                var snippet = content.Length > 500 ? content[..500] : content;
                throw new HttpRequestException(
                    $"OData lookup failed with HTTP {(int)response.StatusCode} {response.ReasonPhrase}: {snippet}");
            }

            var lines = ParseAtomFeed(content);
            totalLines += lines.Count;
            log?.Invoke($"Lookup ZFDR_ACDOCA_V2_CDS: chunk {chunkIndex}/{totalChunks} ({part.Count} docs) -> {lines.Count} lines");

            foreach (var line in lines)
            {
                var key = (StripLeadingZeros(line.Belnr), line.Gjahr);
                if (!result.TryGetValue(key, out var list))
                {
                    list = [];
                    result[key] = list;
                }
                list.Add(line);
            }
        }

        return result;
    }

    public static List<AcdocaLine> ParseAtomFeed(string xmlContent)
    {
        var doc = XDocument.Parse(xmlContent);
        var lines = new List<AcdocaLine>();

        foreach (var entry in doc.Descendants(AtomNs + "entry"))
        {
            var props = entry.Element(AtomNs + "content")?.Element(MetaNs + "properties");
            if (props is null)
                continue;

            var fields = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var el in props.Elements())
            {
                fields[el.Name.LocalName] = el.Value?.Trim() ?? string.Empty;
            }

            fields.TryGetValue("belnr", out var belnr);
            fields.TryGetValue("gjahr", out var gjahr);
            fields.TryGetValue("docln", out var docln);
            fields.TryGetValue("racct", out var racct);
            fields.TryGetValue("zuonr", out var zuonr);

            var rawDocln = docln ?? string.Empty;
            var item = rawDocln.Length >= 3 ? rawDocln[^3..] : rawDocln.PadLeft(3, '0');

            lines.Add(new AcdocaLine(
                belnr ?? string.Empty,
                gjahr ?? string.Empty,
                item,
                racct ?? string.Empty,
                zuonr ?? string.Empty));
        }

        return lines;
    }

    public static (AcdocaLine? Line, LineStatus Status) ResolveLine(
        ExcelInputRow row,
        IReadOnlyList<AcdocaLine> items)
    {
        if (items.Count == 0)
            return (null, LineStatus.DOC_NOT_FOUND);

        var targetRacct = StripLeadingZeros(row.GlAccount);
        var hits = items.Where(i => StripLeadingZeros(i.Racct) == targetRacct).ToList();

        if (hits.Count == 0)
            return (null, LineStatus.NO_MATCH);

        if (hits.Count > 1)
            return (null, LineStatus.AMBIGUOUS);

        var hit = hits[0];
        var status = hit.CurrentAssignment == row.TargetAssignment
            ? LineStatus.SKIPPED_ALREADY_SET
            : LineStatus.PLANNED;

        return (hit, status);
    }

    private static HttpClient CreateHttpClient(string user, string password, bool allowInsecureTls)
    {
        var handler = new HttpClientHandler();
        if (allowInsecureTls)
        {
            handler.ServerCertificateCustomValidationCallback =
                HttpClientHandler.DangerousAcceptAnyServerCertificateValidator;
        }

        var client = new HttpClient(handler)
        {
            Timeout = TimeSpan.FromSeconds(120)
        };

        var token = Convert.ToBase64String(Encoding.UTF8.GetBytes($"{user}:{password}"));
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", token);
        return client;
    }
}
