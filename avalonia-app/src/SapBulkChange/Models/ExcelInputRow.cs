namespace SapBulkChange.Models;

public sealed record ExcelInputRow(int XlRow, string Doc, string Year, string Source,
    string GlAccount, string Account, string TargetAssignment, string Item, string DocumentType, DateOnly PostingDate)
{
    public string ItemType => Source == "BEBAN" ? "S" : "K";
}

public sealed record ExcelValidationWarning(int XlRow, string Message);
public sealed record ExcelReadResult(IReadOnlyList<ExcelInputRow> Rows, IReadOnlyList<ExcelValidationWarning> Warnings);
