using System.Text;
using System.Xml.Linq;
using SapBulkChange.Models;

namespace SapBulkChange.Services;

public sealed class AuditExportService
{
    public string LogDirectory { get; }

    public AuditExportService(string? customLogDirectory = null)
    {
        LogDirectory = customLogDirectory ?? GetDefaultLogDirectory();
        Directory.CreateDirectory(LogDirectory);
    }

    public static string GetDefaultLogDirectory()
    {
        if (OperatingSystem.IsMacOS())
        {
            var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            return Path.Combine(home, "Library", "Application Support", "SapBulkChange", "logs");
        }

        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(localAppData, "SapBulkChange", "logs");
    }

    public string SaveXml(XDocument doc, string fileName)
    {
        Directory.CreateDirectory(LogDirectory);
        var path = Path.Combine(LogDirectory, fileName);
        doc.Save(path);
        return path;
    }

    public string SaveText(string content, string fileName)
    {
        Directory.CreateDirectory(LogDirectory);
        var path = Path.Combine(LogDirectory, fileName);
        File.WriteAllText(path, content, Encoding.UTF8);
        return path;
    }

    public string WriteLog(IEnumerable<string> logLines, string timestamp, bool isDryRun)
    {
        Directory.CreateDirectory(LogDirectory);
        var suffix = isDryRun ? "_dryrun" : string.Empty;
        var path = Path.Combine(LogDirectory, $"change_assignment_{timestamp}{suffix}.log");
        File.WriteAllLines(path, logLines, Encoding.UTF8);
        return path;
    }

    public string ExportCsv(IEnumerable<ChangePlanRow> rows, string? explicitPath = null)
    {
        var ts = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        var path = explicitPath ?? Path.Combine(LogDirectory, $"assignment_change_results_{ts}.csv");
        var dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir))
            Directory.CreateDirectory(dir);

        var sb = new StringBuilder();
        sb.AppendLine("doc,year,item,source,old,target,status,message");
        foreach (var r in rows)
        {
            sb.Append(EscapeCsv(r.Doc)).Append(',')
              .Append(EscapeCsv(r.Year)).Append(',')
              .Append(EscapeCsv(r.Item)).Append(',')
              .Append(EscapeCsv(r.Source)).Append(',')
              .Append(EscapeCsv(r.OldAssignment)).Append(',')
              .Append(EscapeCsv(r.TargetAssignment)).Append(',')
              .Append(EscapeCsv(r.StatusText)).Append(',')
              .AppendLine(EscapeCsv(r.Message));
        }

        File.WriteAllText(path, sb.ToString(), new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        return path;
    }

    private static string EscapeCsv(string? value)
    {
        if (string.IsNullOrEmpty(value))
            return string.Empty;

        if (value.Contains(',') || value.Contains('"') || value.Contains('\n') || value.Contains('\r'))
            return $"\"{value.Replace("\"", "\"\"")}\"";

        return value;
    }
}
