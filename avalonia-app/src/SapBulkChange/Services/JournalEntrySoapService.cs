using System.Globalization;
using System.Net.Http.Headers;
using System.Reflection;
using System.Text;
using System.Xml.Linq;
using System.Xml.Schema;
using SapBulkChange.Models;

namespace SapBulkChange.Services;

public sealed class JournalEntrySoapService
{
    public static readonly XNamespace SoapEnvNs = "http://schemas.xmlsoap.org/soap/envelope/";
    public static readonly XNamespace SfinNs = "http://sap.com/xi/SAPSCORE/SFIN";
    private static readonly XNamespace WsdlNs = "http://schemas.xmlsoap.org/wsdl/";
    private static readonly XNamespace XsdNs = "http://www.w3.org/2001/XMLSchema";

    private const string SoapActionValue =
        "\"http://sap.com/xi/SAPSCORE/SFIN/JournalEntryBulkChangeRequest_In/JournalEntryBulkChangeRequest_InRequest\"";

    private readonly Lazy<XmlSchemaSet> _schemaSet;

    public JournalEntrySoapService()
    {
        _schemaSet = new Lazy<XmlSchemaSet>(LoadSchemaFromEmbeddedWsdl);
    }

    public JournalEntrySoapService(string wsdlFilePath)
    {
        _schemaSet = new Lazy<XmlSchemaSet>(() =>
        {
            var doc = XDocument.Load(wsdlFilePath);
            return CompileSchemaFromWsdl(doc);
        });
    }

    public XDocument BuildSoapEnvelope(
        IReadOnlyList<ChangePlanRow> batchItems,
        string companyCode,
        string rootId,
        DateTime utcNow)
    {
        var nowIso = utcNow.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffff'Z'", CultureInfo.InvariantCulture);

        // CRITICAL SAP ordering rule: all G/L items (BEBAN / S) first, then all Vendor items (VENDOR / K)
        var glItems = batchItems
            .Where(c => c.ItemType == "S")
            .Select(c => BuildItemElement("JournalEntryGLItem", c, companyCode, nowIso));

        var dcItems = batchItems
            .Where(c => c.ItemType == "K")
            .Select(c => BuildItemElement("JournalEntryDebtorCreditorItem", c, companyCode, nowIso));

        var message = new XElement(
            SfinNs + "JournalEntryBulkChangeRequestMessage",
            new XAttribute(XNamespace.Xmlns + "ns0", SfinNs.NamespaceName),
            new XElement("MessageHeader",
                new XElement("ID", rootId),
                new XElement("CreationDateTime", nowIso)),
            glItems,
            dcItems);

        return new XDocument(
            new XDeclaration("1.0", "utf-8", null),
            new XElement(SoapEnvNs + "Envelope",
                new XAttribute(XNamespace.Xmlns + "soap-env", SoapEnvNs.NamespaceName),
                new XElement(SoapEnvNs + "Body", message)));
    }

    public (bool IsValid, IReadOnlyList<string> Errors) ValidateMessage(XDocument envelope)
    {
        var body = envelope.Root?.Element(SoapEnvNs + "Body");
        var messageElement = body?.Elements().FirstOrDefault();
        if (messageElement is null)
            return (false, ["SOAP Body does not contain a message element."]);

        var errors = new List<string>();
        var docToValidate = new XDocument(messageElement);
        docToValidate.Validate(_schemaSet.Value, (_, e) =>
        {
            if (errors.Count < 20)
                errors.Add($"line {e.Exception?.LineNumber ?? 0}: {e.Message}");
        });

        return (errors.Count == 0, errors);
    }

    public async Task<(int StatusCode, string ReasonPhrase, string ResponseBody, Guid MessageId)> SendBatchAsync(
        string soapEndpointUrl,
        XDocument envelope,
        string user,
        string password,
        bool allowInsecureTls,
        CancellationToken ct = default)
    {
        var messageId = Guid.NewGuid();
        var sep = soapEndpointUrl.Contains('?') ? "&" : "?";
        var url = $"{soapEndpointUrl}{sep}MessageId={messageId.ToString().ToUpperInvariant()}";

        using var client = CreateHttpClient(user, password, allowInsecureTls);
        var xmlString = envelope.ToString(SaveOptions.DisableFormatting);
        using var content = new StringContent(xmlString, Encoding.UTF8, "text/xml");
        content.Headers.ContentType = new MediaTypeHeaderValue("text/xml") { CharSet = "utf-8" };

        using var request = new HttpRequestMessage(HttpMethod.Post, url) { Content = content };
        request.Headers.Add("SOAPAction", SoapActionValue);

        using var response = await client.SendAsync(request, ct);
        var responseBody = await response.Content.ReadAsStringAsync(ct);
        return ((int)response.StatusCode, response.ReasonPhrase ?? string.Empty, responseBody, messageId);
    }

    private static XElement BuildItemElement(
        string elementName,
        ChangePlanRow row,
        string companyCode,
        string nowIso)
    {
        return new XElement(elementName,
            new XElement("MessageHeader",
                new XElement("ID", $"A{row.Doc}{row.Year}{row.Item}"),
                new XElement("CreationDateTime", nowIso)),
            new XElement("ItemKey",
                new XElement("AccountingDocument", row.Doc),
                new XElement("CompanyCode", companyCode),
                new XElement("FiscalYear", row.Year),
                new XElement("AccountingDocumentItemID", row.Item)),
            new XElement("AssignmentReferenceChange",
                new XElement("AssignmentReference", row.TargetAssignment),
                new XElement("FieldValueChangeIsRequested", "true")));
    }

    private static XmlSchemaSet LoadSchemaFromEmbeddedWsdl()
    {
        var assembly = Assembly.GetExecutingAssembly();
        var resourceName = assembly.GetManifestResourceNames()
            .FirstOrDefault(n => n.EndsWith("journalentrybulkchangerequest.wsdl", StringComparison.OrdinalIgnoreCase))
            ?? throw new InvalidOperationException("Embedded WSDL resource 'journalentrybulkchangerequest.wsdl' not found.");

        using var stream = assembly.GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException($"Could not open embedded resource '{resourceName}'.");

        var wsdlDoc = XDocument.Load(stream);
        return CompileSchemaFromWsdl(wsdlDoc);
    }

    private static XmlSchemaSet CompileSchemaFromWsdl(XDocument wsdlDoc)
    {
        var schemaEl = wsdlDoc.Descendants(WsdlNs + "types")
            .Elements(XsdNs + "schema")
            .FirstOrDefault()
            ?? throw new InvalidDataException("WSDL does not contain <wsdl:types>/<xsd:schema>.");

        var schemaSet = new XmlSchemaSet();
        using var reader = schemaEl.CreateReader();
        schemaSet.Add(null, reader);
        schemaSet.Compile();
        return schemaSet;
    }

    private static HttpClient CreateHttpClient(string user, string password, bool allowInsecureTls)
    {
        var handler = new HttpClientHandler();
        if (allowInsecureTls)
        {
            handler.ServerCertificateCustomValidationCallback =
                HttpClientHandler.DangerousAcceptAnyServerCertificateValidator;
        }

        var client = new HttpClient(handler)
        {
            Timeout = TimeSpan.FromSeconds(120)
        };

        var token = Convert.ToBase64String(Encoding.UTF8.GetBytes($"{user}:{password}"));
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", token);
        return client;
    }
}
