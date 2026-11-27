using System.Globalization;
using System.Text.RegularExpressions;
using ClosedXML.Excel;
using SapBulkChange.Models;

namespace SapBulkChange.Services;

public sealed class ExcelReaderService
{
    public const int AssignmentMaxLength = 18;
    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;
    private static readonly string[][] Headers = [
        ["Doc Number + Year"], ["Document Number", "Doc Number", "Doc. No.", "Document No", "BELNR"],
        ["Fiscal Year", "Year", "GJAHR"], ["Line Item", "BUZEI", "Item", "Itm", "Line Item No", "Doc. Item"],
        ["Document Type", "Doc. Type", "Doc Type", "Type", "BLART"], ["Posting Date", "Post. Date", "Pstng Date", "BUDAT"],
        ["G/L Account", "G/L", "GL Account", "HKONT", "RACCT"], ["KODE PROJECT"], ["Source Data"], ["Account"] ];

    public ExcelReadResult Read(string filePath)
    {
        using var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        using var wb = new XLWorkbook(stream);
        var ws = wb.Worksheets.FirstOrDefault() ?? throw new InvalidDataException("No worksheets");
        var header = ws.FirstRowUsed() ?? throw new InvalidDataException("Empty worksheet");
        var cols = new Dictionary<string,int>();
        foreach (var cell in header.CellsUsed())
        {
            var name = Text(cell);
            var group = Headers.FirstOrDefault(g => g.Contains(name, StringComparer.OrdinalIgnoreCase));
            if (group != null) cols.TryAdd(group[0], cell.Address.ColumnNumber);
        }
        var missing = Headers.Skip(3).Take(5).Select(g => g[0]).Where(k => !cols.ContainsKey(k)).ToList();
        if (!cols.ContainsKey("Doc Number + Year") && !cols.ContainsKey("Document Number")) missing.Add("Doc Number + Year or Document Number");
        if (missing.Count > 0) throw new InvalidDataException("Missing required columns: " + string.Join(", ", missing));
        var rows = new List<ExcelInputRow>();
        var warnings = new List<ExcelValidationWarning>();
        foreach (var row in ws.RowsUsed().Where(r => r.RowNumber() > header.RowNumber()))
        {
            string Get(string key) => cols.TryGetValue(key, out int c) ? Text(row.Cell(c)) : "";
            var combined = Get("Doc Number + Year");
            var doc = Get("Document Number");
            if (combined == "" && doc == "") continue;
            try
            {
                var date = ParseDate(Get("Posting Date")) ?? throw new FormatException("Invalid or missing Posting Date");
                var year = Get("Fiscal Year");
                if (combined != "")
                {
                    if (combined.Length < 5) throw new FormatException("Invalid Doc Number + Year");
                    doc = combined[..^4]; year = combined[^4..];
                }
                else if (year == "") year = date.ToString("yyyy", Inv);
                if (doc.Length is 0 or > 10 || year.Length != 4 || !year.All(char.IsAsciiDigit)) throw new FormatException("Invalid document number or fiscal year");
                if (doc.All(char.IsAsciiDigit)) doc = doc.PadLeft(10, '0');
                var item = Regex.Replace(Get("Line Item"), @"\.0+$", "").TrimStart('0');
                if (item.Length is 0 or > 3 || !item.All(char.IsAsciiDigit)) throw new FormatException("Invalid BUZEI (expected 1–999)");
                var source = Get("Source Data").ToUpperInvariant();
                if (source == "") source = "BEBAN";
                if (source is not ("BEBAN" or "VENDOR")) throw new FormatException("Unknown Source Data: " + source);
                var type = Get("Document Type").ToUpperInvariant();
                var gl = Get("G/L Account");
                var target = Get("KODE PROJECT");
                if (type == "" || gl == "") throw new FormatException("Document Type and G/L Account are required");
                if (target.Length is 0 or > AssignmentMaxLength) throw new FormatException("KODE PROJECT must be 1–18 characters");
                rows.Add(new(row.RowNumber(), doc, year, source, gl, Get("Account"), target, item.PadLeft(3,'0'), type, date));
            }
            catch (FormatException e) { warnings.Add(new(row.RowNumber(), e.Message)); }
        }
        return new(rows, warnings);
    }

    internal static DateOnly? ParseDate(string value)
    {
        var raw = value.Split(' ', 'T')[0];
        string[] formats = ["yyyyMMdd", "yyyy-M-d", "yyyy/M/d", "yyyy.M.d", "d.M.yyyy", "d/M/yyyy", "d-M-yyyy"];
        if (DateOnly.TryParseExact(raw, formats, Inv, DateTimeStyles.None, out var date)) return date;
        var serial = Regex.Replace(raw, @"\.0+$", "");
        return serial.Length is >= 4 and <= 6 && int.TryParse(serial, NumberStyles.None, Inv, out int n) && n > 0
            ? new DateOnly(1899,12,30).AddDays(n) : null;
    }

    private static string Text(IXLCell cell)
    {
        var v = cell.HasFormula ? cell.CachedValue : cell.Value;
        return v.Type switch {
            XLDataType.DateTime => v.GetDateTime().ToString("yyyyMMdd", Inv),
            XLDataType.Number => v.GetNumber().ToString("0.################", Inv),
            _ => Regex.Replace(v.ToString(Inv).Trim(), @"\s+", " ")
        };
    }
}
