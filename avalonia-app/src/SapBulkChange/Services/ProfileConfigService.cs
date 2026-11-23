using System.Text.Json;
using SapBulkChange.Models;

namespace SapBulkChange.Services;

public sealed class ProfileConfigService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public IReadOnlyList<SapProfile> LoadProfiles(string? configPath = null)
    {
        var path = configPath ?? Path.Combine(AppContext.BaseDirectory, "appsettings.json");
        if (File.Exists(path))
        {
            try
            {
                var json = File.ReadAllText(path);
                var cfg = JsonSerializer.Deserialize<ProfilesConfig>(json, JsonOptions);
                if (cfg?.Profiles is { Count: > 0 })
                    return cfg.Profiles;
            }
            catch
            {
                // Fall back to default profile if appsettings.json is malformed
            }
        }

        return
        [
            new SapProfile
            {
                Name = "QAS",
                IsProduction = false,
                ODataBaseUrl = "https://10.60.177.131:44350/sap/opu/odata/sap/ZFDR_ACDOCA_V2_CDS/ZFDR_ACDOCA_V2",
                SoapEndpointUrl = "http://rarqasapp.telkom.co.id:8001/sap/bc/srt/xip/sap/journalentrybulkchangerequest_/100/journalentrybulkchangerequest/journalentrybulkchangerequest",
                SapClient = "100",
                DefaultCompanyCode = "1000",
                DefaultStartDate = "20160101",
                DefaultEndDate = "20201231",
                BatchDocs = 50,
                VerifyWaitSeconds = 30,
                AllowInsecureTls = true
            }
        ];
    }
}
