using SapBulkChange.Models;
using SapBulkChange.Services;
using Xunit;

namespace SapBulkChange.Tests;

public class LineResolutionTests
{
    private static readonly DateOnly Date = new(2019,1,31);
    private static readonly ExcelInputRow Row = new(2,"0000000042","2019","BEBAN","4000","","NEW","002","SA",Date);
    private static readonly AcdocaLine Hit = new("42","2019","002","00004000","OLD","SA",Date);

    [Fact] public void AtomPostingDateAndTypeReachThePlanner()
    {
        const string xml = """
        <feed xmlns="http://www.w3.org/2005/Atom" xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata"><entry><content><m:properties><belnr>42</belnr><gjahr>2019</gjahr><docln>000002</docln><racct>00004000</racct><blart>SA</blart><budat>2019-01-31T00:00:00</budat><zuonr>OLD</zuonr></m:properties></content></entry></feed>
        """;
        Assert.Equal(Hit,Assert.Single(AcdocaODataService.ParseAtomFeed(xml)));
    }
    [Fact] public void ExactItemFlowsIntoBulkRequestEvenWhenGlIsShared()
    {
        var plan = AcdocaODataService.PlanLine(Row,[Hit with {Item="001"},Hit]);
        Assert.Equal(LineStatus.PLANNED,plan.Status);
        var soap = new JournalEntrySoapService();
        var envelope = soap.BuildSoapEnvelope([plan],"1000","TEST",DateTime.UtcNow);
        Assert.Equal("002",Assert.Single(envelope.Descendants("AccountingDocumentItemID")).Value);
        Assert.Equal("NEW",Assert.Single(envelope.Descendants("AssignmentReference")).Value);
    }
    [Fact] public void MissingAmbiguousAndUnchangedAreNeverPlanned()
    {
        Assert.Equal(LineStatus.DOC_NOT_FOUND,AcdocaODataService.PlanLine(Row,[]).Status);
        Assert.Equal(LineStatus.ITEM_NOT_FOUND,AcdocaODataService.PlanLine(Row,[Hit with { Item="001" }]).Status);
        Assert.Equal(LineStatus.AMBIGUOUS,AcdocaODataService.PlanLine(Row,[Hit,Hit]).Status);
        Assert.Equal(LineStatus.SKIPPED_ALREADY_SET,AcdocaODataService.PlanLine(Row,[Hit with {CurrentAssignment="NEW"}]).Status);
    }
    [Fact] public void AllMismatchesReportedEvenIfAssignmentAlreadyEqualsTarget()
    {
        var p = AcdocaODataService.PlanLine(Row,[Hit with { DocumentType="KR",PostingDate=null,Racct="41",CurrentAssignment="NEW" }]);
        Assert.Equal(LineStatus.VALIDATION_FAILED,p.Status);
        foreach(var field in new[]{"Document Type","Posting Date","G/L Account"}) Assert.Contains(field,p.Message);
    }
}
