using SapBulkChange.Models;
using SapBulkChange.Services;
using Xunit;

namespace SapBulkChange.Tests;

public class SoapPayloadAndXsdTests
{
    private readonly JournalEntrySoapService _sut = new();

    [Fact]
    public void BuildSoapEnvelope_EmitsGlItemsBeforeVendorItems_AndValidatesAgainstWsdlXsd()
    {
        var items = new List<ChangePlanRow>
        {
            new()
            {
                Doc = "0100010920",
                Year = "2019",
                Item = "002",
                Source = "VENDOR",
                OldAssignment = "OLD",
                TargetAssignment = "P-1411SCC-TTES0717",
                Status = LineStatus.PLANNED
            },
            new()
            {
                Doc = "0100010920",
                Year = "2019",
                Item = "001",
                Source = "BEBAN",
                OldAssignment = "OLD",
                TargetAssignment = "P-1411SCC-TTES0717",
                Status = LineStatus.PLANNED
            }
        };

        var envelope = _sut.BuildSoapEnvelope(items, "1000", "ZUONR20261122_001", DateTime.UtcNow);
        var msg = envelope.Root!
            .Element(JournalEntrySoapService.SoapEnvNs + "Body")!
            .Element(JournalEntrySoapService.SfinNs + "JournalEntryBulkChangeRequestMessage")!;

        var childNames = msg.Elements().Select(e => e.Name.LocalName).ToList();
        Assert.Equal(["MessageHeader", "JournalEntryGLItem", "JournalEntryDebtorCreditorItem"], childNames);

        var (isValid, errors) = _sut.ValidateMessage(envelope);
        Assert.True(isValid, string.Join(Environment.NewLine, errors));
    }

    [Fact]
    public void ValidateMessage_AssignmentExceeding18Chars_FailsXsdValidation()
    {
        var items = new List<ChangePlanRow>
        {
            new()
            {
                Doc = "0100010920",
                Year = "2019",
                Item = "001",
                Source = "BEBAN",
                OldAssignment = "OLD",
                TargetAssignment = "TOO_LONG_ASSIGNMENT_12345",
                Status = LineStatus.PLANNED
            }
        };

        var envelope = _sut.BuildSoapEnvelope(items, "1000", "ZUONR20261122_001", DateTime.UtcNow);
        var (isValid, errors) = _sut.ValidateMessage(envelope);

        Assert.False(isValid);
        Assert.NotEmpty(errors);
    }
}
