namespace SapBulkChange.Models;

public sealed class SapProfile
{
    public string Name { get; set; } = "QAS";
    public bool IsProduction { get; set; }
    public string ODataBaseUrl { get; set; } = string.Empty;
    public string SoapEndpointUrl { get; set; } = string.Empty;
    public string SapClient { get; set; } = "100";
    public string DefaultCompanyCode { get; set; } = "1000";
    public string DefaultStartDate { get; set; } = "20160101";
    public string DefaultEndDate { get; set; } = "20201231";
    public int BatchDocs { get; set; } = 50;
    public int VerifyWaitSeconds { get; set; } = 30;
    public bool AllowInsecureTls { get; set; }

    public override string ToString() => Name;
}

public sealed class ProfilesConfig
{
    public List<SapProfile> Profiles { get; set; } = [];
}
