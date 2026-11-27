using ClosedXML.Excel;
using SapBulkChange.Services;
using Xunit;

namespace SapBulkChange.Tests;

public class ExcelReaderTests
{
    private static readonly string[] Headers = [" BELNR ", "Itm", "Doc. Type", "Pstng Date", "HKONT", "KODE PROJECT"];
    private static Models.ExcelReadResult Read(string[] headers, params string[][] rows)
    {
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".xlsx");
        try {
            using (var wb = new XLWorkbook()) {
                var ws = wb.AddWorksheet("FI");
                int r = 0;
                foreach (var values in new[] {headers}.Concat(rows)) {
                    r++; for (int c=0;c<values.Length;c++) ws.Cell(r,c+1).Value = values[c];
                }
                wb.SaveAs(path);
            }
            return new ExcelReaderService().Read(path);
        } finally { File.Delete(path); }
    }

    [Theory]
    [InlineData("43496.0")][InlineData("31.01.2019")][InlineData("20190131")][InlineData("2019-01-31")]
    public void SeparateKeyAndDateFallback(string date)
    {
        var row = Assert.Single(Read(Headers, new string[]{"42","2.0","sa",date,"4000","NEW"}).Rows);
        Assert.Equal(("0000000042","2019","002","SA",new DateOnly(2019,1,31),"BEBAN"),
            (row.Doc,row.Year,row.Item,row.DocumentType,row.PostingDate,row.Source));
    }
    [Fact] public void CombinedKeyAndExplicitSource()
    {
        var h = Headers.Append("Source Data").ToArray(); h[0] = "Doc Number + Year";
        var row = Assert.Single(Read(h,new string[]{"422020","001","KR","2019-12-31","4000","NEW","vendor"}).Rows);
        Assert.Equal("2020",row.Year); Assert.Equal("K",row.ItemType);
    }
    [Fact] public void MissingRequiredColumnsAreFatal() => Assert.Contains("Line Item",Assert.Throws<InvalidDataException>(() => Read(["BELNR"])).Message);
    [Fact] public void InvalidRowsAreExcludedAndIdentified()
    {
        var result = Read(Headers,["42","1000","SA","20190131","4000","NEW"], ["42","1","SA","bad","4000","NEW"],
            ["42","1","SA","20190131","4000","1234567890123456789"], ["","1","","","",""], ["42","1","SA","20190131","4000","VALID"]);
        Assert.Single(result.Rows); Assert.Equal(new[]{2,3,4},result.Warnings.Select(w => w.XlRow));
    }
}
