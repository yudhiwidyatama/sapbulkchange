using SapBulkChange.Models;
using SapBulkChange.Services;
using Xunit;

namespace SapBulkChange.Tests;

public class LineResolutionTests
{
    [Fact]
    public void ParseAtomFeed_ExtractsAcdocaLinesCorrectly()
    {
        const string atomXml = """
            <?xml version="1.0" encoding="utf-8"?>
            <feed xmlns="http://www.w3.org/2005/Atom"
                  xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata"
                  xmlns:d="http://schemas.microsoft.com/ado/2007/08/dataservices">
              <entry>
                <content type="application/xml">
                  <m:properties>
                    <d:belnr>0100004137</d:belnr>
                    <d:gjahr>2019</d:gjahr>
                    <d:docln>000001</d:docln>
                    <d:racct>0051000100</d:racct>
                    <d:zuonr>OLD_ASSIGN</d:zuonr>
                  </m:properties>
                </content>
              </entry>
            </feed>
            """;

        var lines = AcdocaODataService.ParseAtomFeed(atomXml);
        var line = Assert.Single(lines);
        Assert.Equal("0100004137", line.Belnr);
        Assert.Equal("2019", line.Gjahr);
        Assert.Equal("001", line.Item);
        Assert.Equal("0051000100", line.Racct);
        Assert.Equal("OLD_ASSIGN", line.CurrentAssignment);
    }

    [Fact]
    public void ResolveLine_HandlesAllResolutionCases()
    {
        var row = new ExcelInputRow(2, "0100004137", "2019", "BEBAN", "51000100", "51000100", "P-NEW");

        // 0 items -> DOC_NOT_FOUND
        var (l0, s0) = AcdocaODataService.ResolveLine(row, []);
        Assert.Null(l0);
        Assert.Equal(LineStatus.DOC_NOT_FOUND, s0);

        // No matching racct -> NO_MATCH
        var otherAcct = new AcdocaLine("0100004137", "2019", "001", "0099999999", "OLD");
        var (l1, s1) = AcdocaODataService.ResolveLine(row, [otherAcct]);
        Assert.Null(l1);
        Assert.Equal(LineStatus.NO_MATCH, s1);

        // Multiple matching racct -> AMBIGUOUS
        var m1 = new AcdocaLine("0100004137", "2019", "001", "0051000100", "OLD1");
        var m2 = new AcdocaLine("0100004137", "2019", "002", "0051000100", "OLD2");
        var (l2, s2) = AcdocaODataService.ResolveLine(row, [m1, m2]);
        Assert.Null(l2);
        Assert.Equal(LineStatus.AMBIGUOUS, s2);

        // 1 match already equal -> SKIPPED_ALREADY_SET
        var same = new AcdocaLine("0100004137", "2019", "001", "0051000100", "P-NEW");
        var (l3, s3) = AcdocaODataService.ResolveLine(row, [same]);
        Assert.NotNull(l3);
        Assert.Equal(LineStatus.SKIPPED_ALREADY_SET, s3);

        // 1 match different -> PLANNED
        var diff = new AcdocaLine("0100004137", "2019", "001", "0051000100", "P-OLD");
        var (l4, s4) = AcdocaODataService.ResolveLine(row, [diff]);
        Assert.NotNull(l4);
        Assert.Equal(LineStatus.PLANNED, s4);
    }
}
