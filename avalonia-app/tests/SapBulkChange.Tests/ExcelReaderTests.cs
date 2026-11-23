using ClosedXML.Excel;
using SapBulkChange.Services;
using Xunit;

namespace SapBulkChange.Tests;

public class ExcelReaderTests
{
    private readonly ExcelReaderService _sut = new();

    [Fact]
    public void Read_SampleExcelFile_ParsesValidRows()
    {
        var samplePath = FindSampleExcel();
        if (samplePath is null)
            return;

        var result = _sut.Read(samplePath);
        Assert.NotEmpty(result.Rows);
        Assert.All(result.Rows, r =>
        {
            Assert.Equal(10, r.Doc.Length);
            Assert.Equal(4, r.Year.Length);
            Assert.True(r.Source is "BEBAN" or "VENDOR");
            Assert.InRange(r.TargetAssignment.Length, 1, ExcelReaderService.AssignmentMaxLength);
        });
    }

    [Fact]
    public void Read_MissingRequiredColumn_ThrowsInvalidDataException()
    {
        var path = CreateTempWorkbook(ws =>
        {
            ws.Cell(1, 1).Value = "Doc Number + Year";
            ws.Cell(1, 2).Value = "Source Data";
        });

        try
        {
            var ex = Assert.Throws<InvalidDataException>(() => _sut.Read(path));
            Assert.Contains("KODE PROJECT", ex.Message);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void Read_MixedValidAndInvalidRows_RecordsWarningsAndExcludesInvalid()
    {
        var path = CreateTempWorkbook(ws =>
        {
            ws.Cell(1, 1).Value = "Doc Number + Year";
            ws.Cell(1, 2).Value = "Source Data";
            ws.Cell(1, 3).Value = "G/L Account";
            ws.Cell(1, 4).Value = "Account";
            ws.Cell(1, 5).Value = "KODE PROJECT";

            // Row 2: Valid BEBAN
            ws.Cell(2, 1).Value = "1000041372019";
            ws.Cell(2, 2).Value = "beban";
            ws.Cell(2, 3).Value = "51000100";
            ws.Cell(2, 4).Value = "51000100";
            ws.Cell(2, 5).Value = "P-1409SCC-TTES0601";

            // Row 3: Blank key (skipped silently)
            ws.Cell(3, 1).Value = "";

            // Row 4: Short key -> warning
            ws.Cell(4, 1).Value = "1234";
            ws.Cell(4, 2).Value = "VENDOR";
            ws.Cell(4, 5).Value = "P-123";

            // Row 5: Unknown Source Data -> warning
            ws.Cell(5, 1).Value = "1000041372019";
            ws.Cell(5, 2).Value = "OTHER";
            ws.Cell(5, 5).Value = "P-123";

            // Row 6: Target > 18 chars -> warning
            ws.Cell(6, 1).Value = "1000041372019";
            ws.Cell(6, 2).Value = "VENDOR";
            ws.Cell(6, 5).Value = "1234567890123456789";

            // Row 7: Valid VENDOR
            ws.Cell(7, 1).Value = "1000109202019";
            ws.Cell(7, 2).Value = "VENDOR";
            ws.Cell(7, 3).Value = "21000100";
            ws.Cell(7, 4).Value = "V001";
            ws.Cell(7, 5).Value = "P-1411SCC-TTES0717";
        });

        try
        {
            var result = _sut.Read(path);
            Assert.Equal(2, result.Rows.Count);
            Assert.Equal(3, result.Warnings.Count);

            Assert.Equal("0100004137", result.Rows[0].Doc);
            Assert.Equal("2019", result.Rows[0].Year);
            Assert.Equal("BEBAN", result.Rows[0].Source);
            Assert.Equal("S", result.Rows[0].ItemType);

            Assert.Equal("0100010920", result.Rows[1].Doc);
            Assert.Equal("VENDOR", result.Rows[1].Source);
            Assert.Equal("K", result.Rows[1].ItemType);
        }
        finally
        {
            File.Delete(path);
        }
    }

    private static string CreateTempWorkbook(Action<IXLWorksheet> populate)
    {
        var path = Path.Combine(Path.GetTempPath(), $"sapbulk_test_{Guid.NewGuid():N}.xlsx");
        using var wb = new XLWorkbook();
        var ws = wb.Worksheets.Add("Sheet1");
        populate(ws);
        wb.SaveAs(path);
        return path;
    }

    private static string? FindSampleExcel()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            var candidate = Path.Combine(dir.FullName, "Contoh Data SAP for change Assignment.xlsx");
            if (File.Exists(candidate))
                return candidate;
            dir = dir.Parent;
        }
        return null;
    }
}
