# SAP FI Bulk Assignment Change — Avalonia UI Design Spec

## 1. Purpose & Scope

Desktop application (.NET 9 + Avalonia UI) replacing the CLI scripts [`change_assignment.py`](../change_assignment.py) and [`fetch_acdoca_docs.py`](../fetch_acdoca_docs.py) for end users who need to bulk-update the **Assignment (`ZUONR`)** field on posted SAP S/4HANA FI documents from an Excel file.

### MVP Goals
- **Zero-CLI experience** for Finance end users: pick Excel → enter SAP credentials → preview changes (Dry Run) → execute → verify → export CSV report.
- **100% parity** with the proven Python workflow (ACDOCA OData lookup, G/L-before-Vendor SOAP ordering, local XSD validation, `?MessageId=<UUID>`, async verification, XML/CSV audit trail).
- **Safe by default**: mandatory Dry Run preview before Execute, optional canary limit (`Limit to first N documents`), explicit confirmation modal, and clear environment indicator (`QAS` vs `PRD`).
- **Single-file self-contained distribution** for Windows (`win-x64`) and macOS (`osx-arm64`) with no Python or .NET runtime prerequisite on user machines.

### Non-Goals (Keep It Simple)
- No local database (state is per-session; outputs are CSV + XML/log files).
- No custom ABAP RFC path (`change_assignment_rfc.py` / `ZRFC_FI_CHANGE_ASSIGN`).
- No storing SAP passwords on disk (session-only in memory).
- No built-in auto-updater infrastructure.

---

## 2. Tech Stack & Dependencies

Keep dependencies minimal and MIT/Apache-licensed:

| Concern | Package / Technology | Rationale |
|---|---|---|
| Runtime & UI | `.NET 9` + `Avalonia` 11 (`Avalonia.Desktop`, `Avalonia.Themes.Fluent`, `Avalonia.Controls.DataGrid`) | Cross-platform native desktop, single-file publishable. |
| MVVM | `CommunityToolkit.Mvvm` | Source-generated `[ObservableProperty]` and `[RelayCommand]`; minimal boilerplate. |
| Excel Reading | `ClosedXML` | Pure .NET `.xlsx` parser, no Microsoft Excel installation needed. |
| HTTP / OData | Built-in `HttpClient` + `System.Xml.Linq` (`XDocument`) | Zero external dependencies for Atom XML parsing. |
| SOAP & XSD | Built-in `XDocument` + `System.Xml.Schema.XmlSchemaSet` | **Avoid WCF / SvcUtil.** The SOAP payload is small and fixed; building XML directly avoids .NET Core WCF quirks with SAP reliable messaging (`?MessageId=...`). |
| CSV Export | Built-in RFC-4180 writer (or `CsvHelper`) | Simple 8-column output matching the Python CSV format. |

---

## 3. Project Structure

A single project is sufficient for a focused internal utility (plus an optional unit test project):

```text
avalonia-app/
├── DESIGN_SPEC.md
├── SapBulkChange.sln
├── src/SapBulkChange/
│   ├── SapBulkChange.csproj
│   ├── appsettings.json                  # Environment presets (QAS, PRD) - NO credentials
│   ├── Assets/
│   │   └── journalentrybulkchangerequest.wsdl   # Embedded resource for XSD validation
│   ├── Models/
│   │   ├── SapProfile.cs                 # Name, ODataBaseUrl, SoapEndpointUrl, SapClient, CompanyCode, AllowInsecureTls, IsProduction
│   │   ├── ExcelInputRow.cs              # XlRow, Doc (10-digit), Year, Source (BEBAN|VENDOR), GlAccount, Account, TargetAssignment
│   │   ├── AcdocaLine.cs                 # Belnr, Gjahr, Item (3-digit), Racct, CurrentAssignment
│   │   ├── ChangePlanRow.cs              # Observable row bound to DataGrid
│   │   └── LineStatus.cs                 # Enum for all row statuses
│   ├── Services/
│   │   ├── ExcelReaderService.cs         # Validates headers & rows from .xlsx
│   │   ├── AcdocaODataService.cs         # Queries ZFDR_ACDOCA_V2_CDS in chunks of 10 docs
│   │   ├── JournalEntrySoapService.cs    # Builds SOAP XML, validates XSD, POSTs with ?MessageId=<UUID>
│   │   ├── AssignmentChangeOrchestrator.cs # Coordinates Preview, Execute, and Re-Verify flows
│   │   ├── AuditExportService.cs         # Writes CSV results, logs, and sent/received XML
│   │   └── ProfileConfigService.cs       # Loads appsettings.json profiles
│   ├── ViewModels/
│   │   └── MainWindowViewModel.cs        # Commands, progress, filtering, cancellation
│   └── Views/
│       ├── MainWindow.axaml              # Single-window layout
│       └── ConfirmExecuteDialog.axaml    # Explicit confirmation modal before sending to SAP
└── tests/SapBulkChange.Tests/
    ├── ExcelReaderTests.cs
    ├── LineResolutionTests.cs
    └── SoapPayloadAndXsdTests.cs
```

---

## 4. UI / UX Design (Single-Window Workflow)

### Layout Wireframe

```text
+------------------------------------------------------------------------------------+
| [Env: QAS v]  Company: [1000]  Dates: [20160101]-[20201231]   [v Connection/Adv]   |
| SAP User: [___________]   Password: [***********]   [Test Connection]              |
+------------------------------------------------------------------------------------+
| (!) ENVIRONMENT: QAS (rarqasapp.telkom.co.id)  [Amber for QAS / Red for PRD]       |
+------------------------------------------------------------------------------------+
| Excel File: [ C:\Users\...\Contoh Data SAP...xlsx              ] [Browse...]       |
| Parsed: 48 rows | 24 documents | 0 Excel validation warnings                       |
+------------------------------------------------------------------------------------+
| [ 1. Preview Plan (Dry Run) ]  [ 2. Execute Changes ]  [ 3. Re-Verify ]            |
| [ ] Limit docs: [ 1 ]   Wait(s): [30]     [Export CSV]  [Open Logs]                |
+------------------------------------------------------------------------------------+
| Filter: (All: 48) (Planned: 46) (Changed: 0) (Skipped: 2) (Errors: 0)  [Search...] |
| +------------+------+------+--------+----------+-----------+-----------+---------+ |
| | Doc        | Year | Item | Source | Old ZUONR| New ZUONR | Status    | Message | |
| +------------+------+------+--------+----------+-----------+-----------+---------+ |
| | 0100004137 | 2019 | 001  | BEBAN  | P-1409.. | P-1409..  | SKIPPED   |         | |
| | 0100010920 | 2019 | 001  | BEBAN  | BPR TA.. | P-1411..  | PLANNED   |         | |
| | 0100010920 | 2019 | 002  | VENDOR | BPR TA.. | P-1411..  | PLANNED   |         | |
| +------------+------+------+--------+----------+-----------+-----------+---------+ |
+------------------------------------------------------------------------------------+
| [v] Execution Log                                      [=====>     ] 60% [Cancel]  |
| 16:34:25 INFO  Lookup ZFDR_ACDOCA_V2_CDS: chunk 1/3 (10 docs) -> 20 lines          |
| 16:34:26 INFO  Batch 1/1: 46 lines XSD validation: VALID                           |
+------------------------------------------------------------------------------------+
```

### Interaction Rules
1. **Collapsible Connection/Advanced panel**: hides OData URL, SOAP Endpoint URL, SAP Client (`100`), Batch Size (`50` docs/request), and `AllowInsecureTls` so normal users aren't overwhelmed, while power users/admins can override them.
2. **Drag-and-drop** `.xlsx` onto the window or use the native file picker (`StorageProvider.OpenFilePickerAsync`).
3. **Preview Plan (Dry Run)** is always step 1:
   - Reads Excel → queries ACDOCA → resolves line items → generates SOAP XML per batch → validates against WSDL XSD locally → displays exact plan in the `DataGrid`.
   - **Execute Changes** remains disabled until Preview completes and at least one row has status `PLANNED`.
4. **Execute Confirmation Modal**:
   - Displays target environment name, host, company code, number of documents/lines to update, and whether `Limit` is active.
   - If `IsProduction == true`, requires checking `"I confirm this will modify Production FI documents"` before enabling the Confirm button.
5. **Re-Verify Button**:
   - Because `JournalEntryBulkChangeRequest_In` is asynchronous (bgRFC), 30 seconds may occasionally be too short under load. A dedicated **Re-Verify** button re-queries ACDOCA for any `SENT` or `NOT_CHANGED` rows without resending SOAP messages.
6. **Cancellation**:
   - All network calls and the verification wait timer accept a `CancellationToken`. Clicking **Cancel** stops pending batches or skips the wait timer cleanly.

---

## 5. Exact Business Logic & SAP Integration Contracts

### 5.1 Excel Input Validation (`ExcelReaderService`)
- Reads worksheet 1, row 1 as trimmed headers.
- Required columns (exact names):
  - `Doc Number + Year`
  - `Source Data`
  - `G/L Account`
  - `Account`
  - `KODE PROJECT`
- Per-row rules (skip completely blank `Doc Number + Year` rows):
  - `Doc Number + Year`: length `>= 5`; `Doc = key[..^4].PadLeft(10, '0')`; `Year = key[^4..]`.
  - `Source Data`: trimmed, uppercased; must be `BEBAN` (maps to G/L type `S`) or `VENDOR` (maps to D/C type `K`).
  - `KODE PROJECT`: trimmed, non-empty, length `<= 18` (`ZUONR` max length).
- Invalid Excel rows are recorded as warnings (displayed in log & summary) and excluded from the SAP plan rather than crashing the load.

### 5.2 ACDOCA OData Lookup (`AcdocaODataService`)
- **Endpoint**:
  ```text
  {ODataBaseUrl}(p_sdate='{sdate}',p_edate='{edate}')/Set?$filter={Uri.EscapeDataString(filter)}
  ```
  Default QAS base: `https://10.60.177.131:44350/sap/opu/odata/sap/ZFDR_ACDOCA_V2_CDS/ZFDR_ACDOCA_V2`
- **Filter** (chunked at **10 documents per request** to keep URL length safe):
  ```text
  rbukrs eq '{company}' and rldnr eq '0L' and ((belnr eq '{doc1}' and gjahr eq '{yr1}') or ...)
  ```
- **Auth**: HTTP Basic Auth using the session credentials from the UI.
- **TLS**: Support per-profile `AllowInsecureTls` (needed for IP-based QAS certs like `10.60.177.131`; keep `false` for PRD with valid hostname certs).
- **Atom XML Parsing**:
  - Iterate `{http://www.w3.org/2005/Atom}entry` → `content` → `{http://schemas.microsoft.com/ado/2007/08/dataservices/metadata}properties`.
  - Extract `belnr` (strip leading zeros for dictionary key), `gjahr`, `docln` (take last 3 chars as `AccountingDocumentItemID`), `racct`, `zuonr`.
- **Line Resolution**:
  - Match Excel row to ACDOCA lines for `(doc.TrimStart('0'), year)` where `line.Racct.TrimStart('0') == row.GlAccount.TrimStart('0')`.
  - `0` matches → `NO_MATCH`; `> 1` matches → `AMBIGUOUS`; `1` match and `line.Zuonr == row.Target` → `SKIPPED_ALREADY_SET`; otherwise → `PLANNED`.

### 5.3 SOAP Change Request (`JournalEntrySoapService`)
- **Endpoint**:
  ```text
  {SoapEndpointUrl}?MessageId={Guid.NewGuid().ToString().ToUpperInvariant()}
  ```
  *(If `SoapEndpointUrl` already contains `?`, append `&MessageId=...` — required by SAP Note 2237014 for Plain SOAP reliable messaging.)*
  Default QAS URL:
  `http://rarqasapp.telkom.co.id:8001/sap/bc/srt/xip/sap/journalentrybulkchangerequest_/100/journalentrybulkchangerequest/journalentrybulkchangerequest`
- **HTTP Headers**:
  - `Authorization: Basic <base64(user:pass)>`
  - `Content-Type: text/xml; charset=utf-8`
  - `SOAPAction: "http://sap.com/xi/SAPSCORE/SFIN/JournalEntryBulkChangeRequest_In/JournalEntryBulkChangeRequest_InRequest"`
- **Batching**: Group `PLANNED` items by `(Doc, Year)` and chunk into batches of `BatchDocs` (default `50` documents).
- **CRITICAL SAP Ordering Rule**:
  - Inside `<ns0:JournalEntryBulkChangeRequestMessage>`, emit **all** `<JournalEntryGLItem>` (`BEBAN` / `S`) elements first, followed by **all** `<JournalEntryDebtorCreditorItem>` (`VENDOR` / `K`) elements. Mixing or reversing them causes SAP to silently drop lines.
- **Exact XML Structure**:
  ```xml
  <soap-env:Envelope xmlns:soap-env="http://schemas.xmlsoap.org/soap/envelope/">
    <soap-env:Body>
      <ns0:JournalEntryBulkChangeRequestMessage xmlns:ns0="http://sap.com/xi/SAPSCORE/SFIN">
        <MessageHeader>
          <ID>ZUONR{yyyyMMdd_HHmmss}_{batch:000}</ID>
          <CreationDateTime>{utcIso:yyyy-MM-ddTHH:mm:ss.fffffffZ}</CreationDateTime>
        </MessageHeader>
        <!-- 1. All G/L items (BEBAN) first -->
        <JournalEntryGLItem>
          <MessageHeader>
            <ID>A{doc10}{year}{item3}</ID>
            <CreationDateTime>{utcIso}</CreationDateTime>
          </MessageHeader>
          <ItemKey>
            <AccountingDocument>{doc10}</AccountingDocument>
            <CompanyCode>{company}</CompanyCode>
            <FiscalYear>{year}</FiscalYear>
            <AccountingDocumentItemID>{item3}</AccountingDocumentItemID>
          </ItemKey>
          <AssignmentReferenceChange>
            <AssignmentReference>{target}</AssignmentReference>
            <FieldValueChangeIsRequested>true</FieldValueChangeIsRequested>
          </AssignmentReferenceChange>
        </JournalEntryGLItem>
        <!-- 2. All Vendor items (VENDOR) second -->
        <JournalEntryDebtorCreditorItem>
          <!-- same inner structure as JournalEntryGLItem -->
        </JournalEntryDebtorCreditorItem>
      </ns0:JournalEntryBulkChangeRequestMessage>
    </soap-env:Body>
  </soap-env:Envelope>
  ```
- **Local XSD Validation**:
  - Load embedded `journalentrybulkchangerequest.wsdl` once at startup, extract `<wsdl:types>/<xsd:schema>`, compile into `XmlSchemaSet`.
  - Validate the `<JournalEntryBulkChangeRequestMessage>` element before sending. If invalid, mark all rows in that batch `XSD_INVALID` and do not send.
- **Expected Response**: HTTP `202 Accepted` (or `200 OK`). Any non-2xx status or exception marks the batch's rows `SEND_ERROR` with the truncated error message while continuing remaining batches.

### 5.4 Status State Machine

| Status | Color Badge | Meaning |
|---|---|---|
| `PLANNED` | Blue | Resolved cleanly, differs from current `ZUONR`, ready to send. |
| `SKIPPED_ALREADY_SET` | Gray | Current `ZUONR` already equals `KODE PROJECT`. |
| `DOC_NOT_FOUND` | Orange | Document not returned by `ZFDR_ACDOCA_V2_CDS` for the date range/company. |
| `NO_MATCH` | Orange | Document found, but no line matches Excel `G/L Account`. |
| `AMBIGUOUS` | Orange | Multiple ACDOCA lines match the same `G/L Account` in the document. |
| `XSD_INVALID` | Red | Local XSD validation failed; batch not sent. |
| `SENT` | Teal | HTTP 202 accepted; awaiting verification. |
| `SEND_ERROR` | Red | HTTP/network error when calling SOAP endpoint. |
| `CHANGED` | Green | Verified via ACDOCA re-read: `zuonr == target`. |
| `NOT_CHANGED` | Amber/Red | Still old value after wait; prompt user to **Re-Verify** or check `/AIF/ERR` (`FINS_ACDOC_POST089`). |
| `VERIFY_ERROR` | Red | Verification OData call failed. |

---

## 6. Configuration, Security & Audit Trail

### `appsettings.json` (shipped next to executable)
```json
{
  "Profiles": [
    {
      "Name": "QAS",
      "IsProduction": false,
      "ODataBaseUrl": "https://10.60.177.131:44350/sap/opu/odata/sap/ZFDR_ACDOCA_V2_CDS/ZFDR_ACDOCA_V2",
      "SoapEndpointUrl": "http://rarqasapp.telkom.co.id:8001/sap/bc/srt/xip/sap/journalentrybulkchangerequest_/100/journalentrybulkchangerequest/journalentrybulkchangerequest",
      "SapClient": "100",
      "DefaultCompanyCode": "1000",
      "DefaultStartDate": "20160101",
      "DefaultEndDate": "20201231",
      "BatchDocs": 50,
      "VerifyWaitSeconds": 30,
      "AllowInsecureTls": true
    }
  ]
}
```

### Security Rules
- **No hardcoded credentials** anywhere in code or `appsettings.json`.
- **Never log** passwords or `Authorization` headers in the UI log or file logs.
- **Audit artifacts** written to `%LocalAppData%/SapBulkChange/logs/` (Windows) or `~/Library/Application Support/SapBulkChange/logs/` (macOS):
  - `change_assignment_<ts>[_dryrun].log`
  - `request_<ts>_<batch>.xml` and `response_<ts>_<batch>.xml`
  - `assignment_change_results_<ts>.csv` (same 8 columns as Python: `doc,year,item,source,old,target,status,message`).

---

## 7. Build, Packaging & End-User Deployment

### Publish Commands
```bash
# Windows x64 (single self-contained executable)
dotnet publish src/SapBulkChange/SapBulkChange.csproj \
  -c Release -r win-x64 --self-contained true \
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true

# macOS Apple Silicon (if needed)
dotnet publish src/SapBulkChange/SapBulkChange.csproj \
  -c Release -r osx-arm64 --self-contained true \
  -p:PublishSingleFile=true
```

### Deployment Checklist
1. Bundle `SapBulkChange.exe` + `appsettings.json` in a versioned zip (e.g., `SapBulkChange-v1.0.0-win-x64.zip`).
2. **WSDL is embedded** as a compiled resource so end users never have to run `--fetch-wsdl`.
3. **Corporate IT / SmartScreen**: Sign the `.exe` with an internal code-signing certificate if available, or request IT allow-listing to avoid Windows Defender SmartScreen warnings.
4. **Network prerequisites**: End-user workstations must be able to reach the configured SAP OData (`44350`) and SOAP (`8001`) ports over the corporate network/VPN.

---

## 8. Phased Implementation Plan (~3–4 Days Total)

| Phase | Deliverables | Effort |
|---|---|---|
| **Phase 1: Core Engine & Tests** | `Models/`, `ExcelReaderService`, `AcdocaODataService`, `JournalEntrySoapService` (XML builder + embedded WSDL XSD validation), `AuditExportService`, and unit tests against `Contoh Data SAP for change Assignment.xlsx` and sample XML. | ~1 day |
| **Phase 2: Avalonia UI & Orchestration** | `MainWindow.axaml`, `MainWindowViewModel`, `ConfirmExecuteDialog`, `AssignmentChangeOrchestrator` (Preview / Execute / Re-Verify / Cancel), status filter pills, live log drawer. | ~1.5 days |
| **Phase 3: QAS Verification & Packaging** | End-to-end test against QAS (`--limit 1` equivalent), verify CSV/XML outputs, publish single-file `win-x64` binary, write 1-page user guide. | ~0.5–1 day |
