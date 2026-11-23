using System.Globalization;
using ClosedXML.Excel;
using SapBulkChange.Models;

namespace SapBulkChange.Services;

public sealed class ExcelReaderService
{
    public const int AssignmentMaxLength = 18;

    private static readonly string[] RequiredColumns =
    [
        "Doc Number + Year",
        "Source Data",
        "G/L Account",
        "Account",
        "KODE PROJECT"
    ];

    public ExcelReadResult Read(string filePath)
    {
        if (!File.Exists(filePath))
            throw new FileNotFoundException($"Excel file not found: {filePath}", filePath);

        using var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        using var workbook = new XLWorkbook(stream);
        var ws = workbook.Worksheets.FirstOrDefault()
            ?? throw new InvalidDataException("Excel workbook contains no worksheets.");

        var headerRow = ws.Row(1);
        var lastCol = ws.LastColumnUsed()?.ColumnNumber() ?? 0;
        var colMap = new Dictionary<string, int>(StringComparer.Ordinal);

        for (int c = 1; c <= lastCol; c++)
        {
            var header = CellToString(headerRow.Cell(c));
            if (!string.IsNullOrEmpty(header) && !colMap.ContainsKey(header))
                colMap[header] = c;
        }

        var missing = RequiredColumns.Where(req => !colMap.ContainsKey(req)).ToList();
        if (missing.Count > 0)
            throw new InvalidDataException($"Excel is missing required columns: {string.Join(", ", missing)}");

        var rows = new List<ExcelInputRow>();
        var warnings = new List<ExcelValidationWarning>();
        var lastRow = ws.LastRowUsed()?.RowNumber() ?? 1;

        for (int r = 2; r <= lastRow; r++)
        {
            var row = ws.Row(r);
            var key = CellToString(row.Cell(colMap["Doc Number + Year"]));
            if (string.IsNullOrWhiteSpace(key))
                continue;

            if (key.Length < 5)
            {
                warnings.Add(new ExcelValidationWarning(r, $"Bad 'Doc Number + Year': '{key}'"));
                continue;
            }

            var doc = key[..^4].PadLeft(10, '0');
            var year = key[^4..];
            var source = CellToString(row.Cell(colMap["Source Data"])).ToUpperInvariant();
            var target = CellToString(row.Cell(colMap["KODE PROJECT"]));

            if (source is not ("BEBAN" or "VENDOR"))
            {
                warnings.Add(new ExcelValidationWarning(r, $"Unknown Source Data '{source}' (expected BEBAN or VENDOR)"));
                continue;
            }

            if (string.IsNullOrEmpty(target))
            {
                warnings.Add(new ExcelValidationWarning(r, "KODE PROJECT is empty"));
                continue;
            }

            if (target.Length > AssignmentMaxLength)
            {
                warnings.Add(new ExcelValidationWarning(r, $"KODE PROJECT longer than {AssignmentMaxLength} chars: '{target}'"));
                continue;
            }

            var glAccount = CellToString(row.Cell(colMap["G/L Account"]));
            var account = CellToString(row.Cell(colMap["Account"]));

            rows.Add(new ExcelInputRow(r, doc, year, source, glAccount, account, target));
        }

        return new ExcelReadResult(rows, warnings);
    }

    private static string CellToString(IXLCell cell)
    {
        if (cell.IsEmpty())
            return string.Empty;

        return cell.Value.Type switch
        {
            XLDataType.Text => cell.Value.GetText().Trim(),
            XLDataType.Number => cell.Value.GetNumber().ToString(CultureInfo.InvariantCulture).Trim(),
            XLDataType.Boolean => cell.Value.GetBoolean().ToString().Trim(),
            XLDataType.DateTime => cell.Value.GetDateTime().ToString("yyyy-MM-dd", CultureInfo.InvariantCulture).Trim(),
            _ => cell.Value.ToString(CultureInfo.InvariantCulture).Trim()
        };
    }
}
