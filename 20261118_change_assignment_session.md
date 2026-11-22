# Session Notes: Mass-change Assignment (ZUONR) on FI documents

Date: 2026-11-18 (updated 2026-11-19)
System: S/4HANA on-prem 2022, `rarqasapp.telkom.co.id` (= 10.60.177.131), client 100, company code 1000

**Status (2026-11-23): done.** All 48 lines in the 24 documents carry the KODE PROJECT value in ACDOCA `zuonr`
(a read-only dry run on 2026-11-23 reports `SKIPPED_ALREADY_SET` for all 48 lines; the 2026-11-18 23:34 run changed 46 and
verified them, and the other 2 lines, document 100004137, had been processed from the two queued messages).
Still open: the AIF monitor `/AIF/ERR` (`/AIF/UI008`, section 9) and ABAP dump cause for the 22:24/22:29 `RABAX` errors (not investigated).

All files of this work live in `fi_assignment_change/` (moved there on 2026-11-23). Scripts resolve paths relative to their own
folder, so they can be started from any directory.

## 1. Objective

Create a Python script that changes the **Assignment** field of posted FI document lines, driven by
`Contoh Data SAP for change Assignment.xlsx`:

- 48 lines in 24 documents (years 2016-2020, business areas T905 and T711).
- Each document has 2 lines: BEBAN (G/L expense line) and VENDOR (vendor line).
- New Assignment value = column **KODE PROJECT** (all values <= 18 chars, the field length).

## 2. Approach chosen

Standard SAP service **JournalEntryBulkChangeRequest_In** (asynchronous SOAP, SAP Help "APIs for General
Ledger Accounting"), instead of a custom ABAP RFC wrapper or SAP GUI scripting.

- BEBAN lines -> `JournalEntryGLItem`; VENDOR lines -> `JournalEntryDebtorCreditorItem`.
- Field: `AssignmentReferenceChange/AssignmentReference` + `FieldValueChangeIsRequested=true`.
- Request order matters: all G/L items first, then D/C items (wrong order silently drops lines).
- No test mode (`TestDataIndicator` not supported). Result is asynchronous (check `/AIF/ERR`).
- Line item numbers are looked up from ACDOCA via **ZFDR_ACDOCA_V2_CDS** (no extra service activation needed).

## 3. Findings

- **ZFDR_ACDOCA_V2_CDS** metadata: mandatory parameters `p_sdate`, `p_edate`; keys `rldnr, rbukrs, gjahr, belnr, docln`;
  fields include `racct`, `zuonr`, `xblnr`, `prctr`, `rbusa`, `blart`, `budat`, `poper`, `hsl/ksl/wsl`.
  No vendor number, account type, posting key or clearing status.
- `belnr` is returned without the leading zero (`100004137`); the filter accepts the 10-digit form; the SOAP API needs 10 digits.
- All 24 documents / 48 lines found; every document has `docln` 000001 (BEBAN) and 000002 (VENDOR);
  the Assignment differs from KODE PROJECT on all 48 lines. Excel "G/L Account" equals `racct` (vendor lines carry the recon account).
- The generated request validates **VALID** against the XSD embedded in the service WSDL.

## 4. Files

| File | Purpose |
|---|---|
| `change_assignment.py` | Main script: read Excel -> look up items (CDS) -> build/validate request -> send -> wait -> verify -> results CSV |
| `fetch_acdoca_docs.py` | Fetch ACDOCA lines for the Excel documents (also used by the main script for lookup/verify) |
| `change_assignment_rfc.py` + `zrfc_fi_change_assign.abap` | Alternative route through a custom remote function module `ZRFC_FI_CHANGE_ASSIGN` over `/sap/bc/soap/rfc`, added separately while the SRT setup was blocked; not used for the final change and not described further in these notes |
| `Contoh Data SAP for change Assignment.xlsx` | Input file (default `--excel`) |
| `wsdl_je_change/journalentrybulkchangerequest.wsdl` | Service WSDL (downloaded with `--fetch-wsdl`) |
| `logs/` | `change_assignment_<ts>[_dryrun].log`, `request_*.xml`, `sent_*.xml`, `response_*.xml` |
| `assignment_change_plan_<ts>.csv` / `assignment_change_results_<ts>.csv` | Dry-run plan / real-run per-line status |
| `ZFDR_ACDOCA_V2_CDS_metadata_*.xml`, `acdoca_lines_*.csv` | Metadata and ACDOCA extract |

Folder layout: `fi_assignment_change/` also holds the generated CSV/XML outputs (`assignment_change_*.csv`, `acdoca_lines_*.csv`,
metadata XML). `config.json` stays in the parent folder (shared with the PR/PO scripts); the scripts look for it in this folder first, then the parent.
`fetch_cds_metadata.py` (generic metadata reader used once for `ZFDR_ACDOCA_V2_CDS`) also stays in the parent folder.

Run with the venv that has zeep/lxml/openpyxl:
`~/Documents/SourceCode/browser-use-test/cdspy/venv/bin/python`

```bash
PY=~/Documents/SourceCode/browser-use-test/cdspy/venv/bin/python
$PY change_assignment.py --fetch-wsdl   # once
$PY change_assignment.py --dry-run      # plan + request XML + XSD validation, sends nothing
$PY change_assignment.py --limit 1      # real run, first document only
$PY change_assignment.py                # real run, all 24 documents
```

Script behaviour: credentials from env `SAP_USER`/`SAP_PASSWORD`, else `config.json` `SAP_SOAP`, else prompt (never logged);
XSD validation before sending (invalid batch is not sent); each call carries `?MessageId=<UUID>`;
failed send is logged with stack trace and marked `SEND_ERROR`; result statuses: `CHANGED`, `NOT_CHANGED`,
`SKIPPED_ALREADY_SET`, `NO_MATCH`, `AMBIGUOUS`, `DOC_NOT_FOUND`, `XSD_INVALID`, `SEND_ERROR`, `VERIFY_ERROR`.

## 5. SAP-side setup progress

| Step | Status |
|---|---|
| AIF content `/FINAC` (`JECHANGEIN/00001`, `JECHG_CON/00001`) | Was missing; deploy with `/AIF/CONTENT_EXTRACT` (section 9). Current state in client 100 not re-confirmed |
| `/AIF/ERR` monitor | Blocked by `/AIF/UI008` "Application AIF is not defined" - **open**, see section 9 |
| SOAMANAGER binding for `JOURNALENTRYBULKCHANGEREQUEST_IN` | Created and activated: provider security Basic (User ID/Password), transport None (http), WSDL downloaded |
| Service endpoint | Reachable; requests are accepted (HTTP 202) |
| Message ID for reliable messaging | Fixed in script (`?MessageId=<UUID>`, SAP Note 2237014) |
| Web service runtime (`SRT_ADMIN`) | Done by user: client 000 first (inbound destination), then client 100 (section 10) |
| bgRFC supervisor (`SBGRFCCONF`) | `BGRFC_SUPERVISOR` was missing; created by user (section 10). The queued messages were processed afterwards (confirmed 2026-11-18 23:34) |

## 6. Run history and current state

Times are from `logs/` (local time, 2026-11-18). All runs were `--limit 1` (document 100004137, items 001/002).

| Time | Result |
|---|---|
| 22:10 | HTTP 403 "Service cannot be reached". `SRT_LOG`: `Reliable messaging (RM) configured, but no Message ID and no WSRM assertion provided` -> script now sends `?MessageId=<UUID>` (an earlier guess that the ICF node was inactive was wrong) |
| 22:20 | HTTP 500 "Web service processing error". Around this stage `SRT_UTIL` reported `WS runtime setup missing. Run report SRT_ADMIN` |
| 22:24, 22:29 | HTTP 500 `RABAX occurred on server side` (ABAP dump). Cause not investigated in this session (`ST22` would show it) |
| 23:09 | **HTTP 202 Accepted**, MessageId `703F7CC5-656B-428A-B443-36660E05AD0C` |
| 23:15 | **HTTP 202 Accepted**, MessageId `C2C3B63B-1F5C-441D-9C73-34922F140FD5` |
| 23:34 | Full run (all 24 documents): the 2 lines of 100004137 were already set (the queued messages had been processed after the supervisor was created); 46 other lines sent in one batch (HTTP 202, MessageId `ADE3F3BD-552C-4FC1-8232-8EBF1A9D269E`); verification after 30 s: **46 `CHANGED`, 2 `SKIPPED_ALREADY_SET`** |
| 2026-11-23 06:23 | Read-only dry run (nothing sent): **48 of 48 lines already equal KODE PROJECT** (`SKIPPED_ALREADY_SET`) |

After the two accepted calls:
- `SRT_MONI`: messages pending with `SRT_CORE255` "Wait for Scheduler" (bgRFC cannot process the message: resources or configuration).
- `SBGRFCMON`: inbound destination `WS_BGRFC_INBOUND000` green; two queues `SRTQP_...`, each "Queue is executable", 1 processible unit, no errors or locks -> no scheduler was picking them up.
- Cause found: the bgRFC supervisor destination `BGRFC_SUPERVISOR` did not exist; created afterwards via `SBGRFCCONF`.
- Both messages target the same document and the same value, so the second one is redundant but harmless (it may produce a warning in `/AIF/ERR`).
- Confirmed afterwards: all 48 lines show the target value (see the 23:34 and 2026-11-23 rows). The earlier `NOT_CHANGED` results of the 23:09 and 23:15 runs only reflected the 30 s wait before the scheduler existed.

## 7. Next steps

Done: supervisor created, queued messages processed, all 24 documents changed and verified (section 6).

Open / optional:
1. Fix `/AIF/ERR` (`/AIF/UI008`): run `/AIF/SETUP` and confirm the `/FINAC` content (section 9); read SAP Note 2588468.
2. Assign the user as recipient `FINAC_RECT_JECHANGE_IN` (namespace `/FINAC`) so processing errors are visible in `/AIF/ERR`.
3. Find the cause of the `RABAX` dumps from 22:24 and 22:29 (`ST22`), to be sure nothing else is wrong in the runtime.
4. Production: AIF content, SRT/bgRFC setup and the SOAMANAGER binding must be repeated or transported there (sections 9-10) before the same job can run.
5. Do not re-run `change_assignment.py` for the same documents; it would report `SKIPPED_ALREADY_SET`, but each real run with changes queues a new message.

## 8. Risks and notes

- No test mode: the first real change cannot be dry-run on the SAP side; always start with `--limit 1`.
- Some 2016-2019 vendor lines may be cleared; OB32 field-status rules can reject them (`FINS_ACDOC_POST089`). The CDS does not show clearing status.
- If the system is production, the change should follow normal change control; AIF content must be deployed in DEV and transported.
- Security: `fetch_sap_data_v2.py`, `fetch_cds_metadata.py` and `fetch_acdoca_docs.py` have SAP credentials hardcoded, and `config.json`
  holds a plain-text password. Moving them to environment variables is recommended.
- Open idea: the dry-run XSD validation is built in; a post-run read of `/AIF/ERR` is still manual.

## 9. Enabling AIF: `/AIF/CUST`, `/AIF/SETUP` and transporting the content

Why it is needed: the SAP Help page for the service lists AIF content as a prerequisite. In `/AIF/CUST` namespace `/FINAC`, the lines
`JECHANGEIN/00001` and `JECHG_CON/00001` must exist. Processing results and errors are shown in `/AIF/ERR`.
(Tcodes starting with `/` are entered as `/n/AIF/CUST` etc.)

**9.1 Check what is loaded**
- `/AIF/CONTENT_DISP` shows the loaded AIF content.
- `/AIF/CUST` -> SAP Application Interface Framework -> Interface Development -> Define Interfaces -> namespace `/FINAC`.

**9.2 Deploy the delivered content (`/AIF/CONTENT_EXTRACT`)**
- Deployment Scenario ID `SAP_COM_0002` (value from the SAP Help page; check with F4 on the field).
- Parameters: leave "No automatic registration" and "Registration in AIM table" unticked.
- Transport recording: tick "Customizing to be recorded" and "Configuration to be recorded", then supply a request when prompted.
- Run it in the **development system's customizing client** and transport on (SAP's recommendation). The extraction is per client; content extracted in another client does not help client 100.
- If the system is not production (sandbox/QA copy), running it directly is acceptable; recording a transport is still good practice.
- Do not run it directly in production; production clients are normally locked for customizing.

**9.3 Run `/AIF/SETUP` (initial AIF setup)**
- SAP KBA 3526371, "AIF - Initial setup instructions for the use of SAP Application Interface Framework using /AIF/SETUP transaction":
  AIF needs initial system configuration before use, and `/AIF/SETUP` automates it (the KBA's keywords: number range, client copy,
  standard customizing, global default recipient, AIF engines). The KBA body needs an SAP for Me login and was not read.
- Run it in each client that uses AIF (here client 100).
- Likely related to `/AIF/UI008` "Application AIF is not defined" (own inference; SAP Note 2588468 covers this exact message, but its text was not available).
- Status: what was run and the result must be filled in here by whoever runs it: `[ ] /AIF/SETUP executed in client 100  [ ] /AIF/ERR opens without /AIF/UI008`.

**9.4 Recipients**
- Assign the user (or a role/team) as recipient `FINAC_RECT_JECHANGE_IN`, namespace `/FINAC`, in `/AIF/RECIPIENTS`
  (Customizing: Cross-Application Components -> SAP Application Interface Framework -> System Configuration -> Recipients -> Assign Recipients).
  Recipient assignment is often maintained directly in each system.

**9.5 Transporting**
- The extraction writes customizing entries; when "Customizing to be recorded" is ticked they go into the transport request you choose.
  Release the request and import it through QA to production as usual.
- Alternative (from the Central Finance documentation): add the entries to a customizing request manually ("Add Transport").
- Not carried by this transport: the SOAMANAGER binding and the bgRFC/SRT runtime settings (sections 5 and 10); do these in each system.

**9.6 Monitoring**
- `/AIF/ERR`: namespace `/FINAC`, interface `JECHANGEIN`. Message IDs of requests appear as the line-level IDs (`A<doc><year><item>`).
- AIF- or SOAP-framework-level errors are not visible there: use `SRT_MONI`, `SRT_LOG`, `SRT_UTIL`.

## 10. Web service runtime (`SRT_ADMIN`) and bgRFC (`SBGRFCCONF`)

**10.1 `SRT_ADMIN`** (web service runtime administration)
- Trigger: `SRT_UTIL`/`SRT_LOG` reported "WS runtime setup missing. Run report SRT_ADMIN".
- Done by the user: ran it in **client 000** first (this created the inbound destination), then in **client 100**.
- Checks listed in the popup: `CL_SRT_ADMIN_IDP` (idempotency, used by the Message ID), `SERVICE_DEST` (service RFC destination and user),
  `INBOUND_DEST` (bgRFC inbound destination), `BGRFC_SUPERVISOR`, `TASK_WATCHER`, `WSRM_EVENT_HNDL`, `ICF_NODES`,
  `WSSE` (not needed here). Which of these are relevant is own reasoning, not confirmed by SAP documentation.
- Needs Basis-level authorizations (for example `S_RFC`, `S_ADMI_FCD`).
- Result: the messages are now accepted (HTTP 202) and queue in bgRFC destination `WS_BGRFC_INBOUND000`.

**10.2 `SBGRFCCONF`** (bgRFC configuration)
- Problem: the units sat in the queues ("Queue is executable") and `SRT_MONI` showed `SRT_CORE255` "Wait for Scheduler" because the
  supervisor destination `BGRFC_SUPERVISOR` did not exist; the supervisor is what starts the schedulers.
- Done by the user: created the supervisor destination in `SBGRFCCONF` -> "Define Supervisor Dest." (destination `BGRFC_SUPERVISOR`, user, password).
- Password: must follow the system password policy (currently understood to require lowercase, uppercase, a digit and a punctuation character).
  Use a technical user of type System/Service (no dialog logon). **Do not store the password in this file, in `config.json` or in the repo.**
- Other tabs worth checking if units still do not run: "Scheduler: App. Server" (max dialog processes above 0 for the application server),
  "Define Inbound Dest." / "Scheduler: Inbound Dest." for `WS_BGRFC_INBOUND000`. Tab names can differ slightly by release.
- Verification: `SM59` -> `BGRFC_SUPERVISOR` connection test and authorization test; `SBGRFCMON` (queues should run and empty);
  `SRT_MONI` (status moves from "Wait for Scheduler" to processed); `SM21`/`SM50` for scheduler errors and free dialog work processes.
  The user needs authorization object `S_BGRFC`.

## 11. Sources

- SAP Note 2237014 - reliable messaging error / `?MessageId=<UUID>`: https://userapps.support.sap.com/sap/support/knowledge/en/2237014
- SAP KBA 3526371 - initial AIF setup with `/AIF/SETUP`: https://userapps.support.sap.com/sap/support/knowledge/en/3526371
- SAP Note 2588468 - `/AIF/UI008` "Application AIF is not defined": https://userapps.support.sap.com/sap/support/knowledge/en/2588468
- SAP Help, Extracting the AIF Content: https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/2de74e75ac4240c68ff125a948205aee/6c590f3516bb4f4f98222e38f338e495.html
- SAP Help, Transporting AIF Content: https://help.sap.com/docs/ABAP_PLATFORM_NEW/4db1676c3f114f119b500bd80ccd944d/13f753cfe3df4437b3b1434d1170a6ae.html
- SAP Help, Journal Entry - Change (Asynchronous): PDF `pdfdownload_journalchange.pdf` from this session
