# Session summary: FI Assignment (ZUONR) bulk-upload Fiori app

Repository `yudhiwidyatama/sapbulkchange`, branch **`fiori-sonnet5`** (created from `before-fiori-app-spec` at commit `698bcfa`).
Session date: 2026-11-28.

## 1. Status at a glance

| Item | Status |
|---|---|
| Branch `fiori-sonnet5` | Created, all work pushed |
| Phase 1 design (revision 2) | Approved by the user |
| Phase 2 build | Code written and pushed |
| ABAP / CDS / BDEF compile and activation | **Not done** (no SAP system or ADT access in the session) |
| ABAP Unit | Written, **not run** |
| UI5 template test | Run: `node webapp/test/Template.test.js` passed; `manifest.json` validated as JSON |
| Deployment into the S/4HANA 2022 dev system and a transport | **Not done**; runbook for an ADT MCP agent written |
| Functional / end-to-end test | Not done (script written: `TEST_SCRIPT.md`) |

## 2. What the user asked for, in order

1. Create `fiori-sonnet5` from `before-fiori-app-spec` and build a small bulk-upload app from the ABAP Z-program spec in the repo (`ABAP_ZPROGRAM_PLAN.md`), in **two phases**: minimal design first, build only after the reply "approved".
2. Revise the design: **Validate** must also include a lock check and an authority check; allow **up to 50,000 rows**.
3. "approved" -> build Phase 2.
4. Write a markdown runbook for an agent with an **ADT MCP tool** to put the app into the S/4HANA 2022 dev system in a transport request. Clarified: it is the **ADT MCP server in VS Code** (SAP's official one).
5. This summary.

## 3. Phase 1: design decisions

Based on `ABAP_ZPROGRAM_PLAN.md` and `zrfc_fi_change_assign.abap` (not on the full 97 KB `zfi_bulk_change_assign.abap`, which was never read in full).

* **Scope:** bulk change of the Assignment field `ZUONR` of posted FI line items, through `FI_DOCUMENT_CHANGE` (one call per line, one document per LUW).
* **Frontend:** SAP Fiori elements, OData V4, List Report (batch history, Create, Download Template) + Object Page (header counts, rows table, Validate / Post).
* **Backend:** RAP business object, managed with additional save, non-draft; large-object attachment for the `.xlsx`.
* **Template columns:** Document Number, Fiscal Year (defaults to year of Posting Date), Line Item, Document Type, Posting Date, G/L Account, KODE PROJECT (target `ZUONR`, max 18), Source Data (`BEBAN` default / `VENDOR`).
* **Row key:** (company code of the batch, document number, fiscal year, line item `BUZEI` = last 3 characters of `ACDOCA-DOCLN`); document type, posting date and G/L account must match the system line.
* **Item statuses:** `EXCEL_ERROR`, `DOC_NOT_FOUND`, `ITEM_NOT_FOUND`, `VALIDATION_FAILED`, `SKIPPED_ALREADY_SET`, `PLANNED`, `LOCKED`, `SEND_ERROR`, `CHANGED`, `NOT_CHANGED`. Batch statuses: `UPLOADED`, `VALIDATING`, `VALIDATED`, `FILE_ERROR`, `POSTING`, `DONE`.
* **Revision 2 changes (user request):**
  * Validate = authority check (`F_BKPF_BUK`, ACTVT 02) + file/row checks + `ACDOCA` resolution + **lock check**.
  * Limit raised to **50,000 rows / 20 MB** (assumption). Because of the volume, **Validate and Post both run as background jobs**; parsing moved into the Validate job; chunked reads and commits.
  * The earlier "out of scope: test-run mode" is now covered by Validate.
* **Mandatory checklist** (template download, upload with size/type limit, validate-only, row-level error report, authorization, application log, duplicate/re-upload, locking/recovery, i18n, tests): each item covered or explicitly marked out of scope in the design.
* **Questions left unanswered by the user** (defaults taken): Excel/CSV error file = built-in *Export to Spreadsheet* of the rows table; partial posting is acceptable (rows in error are excluded, only `PLANNED` rows are posted); very large single documents untested.

## 4. Phase 2: what was built (all under `fiori-bulk-upload/`)

| Path | Content |
|---|---|
| `backend/ddic/` | `ZFI_UPL_BATCH` (incl. attachment, hash, counters), `ZFI_UPL_ITEM` |
| `backend/cds/` | interface views `ZFI_I_UPL_BATCH/ITEM`, projections `ZFI_C_UPL_BATCH/ITEM`, metadata extensions, access controls (display by company code via `F_BKPF_BUK`, ACTVT 03) |
| `backend/bdef/` | managed BDEF (`validate`, `post` actions, feature control, global + instance authorization, determination `onFile`, validation `checkInput`), projection BDEF |
| `backend/srv/` | service definition `ZFI_UI_UPL` |
| `backend/classes/` | behavior pool `ZBP_FI_I_UPL_BATCH` (handler + saver that schedules the job), `ZCL_FI_UPLOAD_JOB`, `ZCL_FI_UPLOAD_ENGINE`, `ZCL_FI_UPLOAD_PARSER`, `ZCL_FI_XLSX_READER`, `ZCL_FI_DB_PROVIDER`, `ZCL_FI_DOC_CHANGER`, `ZCL_FI_UPL_LOG`, `ZCL_FI_UPL_MSG`, `ZCX_FI_UPLOAD`, interfaces `ZIF_FI_UPL_TYPES`, `ZIF_FI_DB_PROVIDER`, `ZIF_FI_DOC_CHANGER`, and ABAP Unit include files for the reader, parser and engine (test doubles for DB and changer) |
| `backend/programs/` | report `ZFI_UPL_RUN` (job entry), function module `Z_FI_UPL_SCHEDULE` (tRFC, schedules the classic job) |
| `backend/messages/zfi_bulk.txt` | message class `ZFI_BULK`, 000-032 |
| `webapp/` | Fiori elements V4 app: `manifest.json`, `Component.js`, `ext/Template.js` (Download Template via `sap.ui.export.Spreadsheet`), `i18n/i18n.properties`, `test/Template.test.js` |
| `README.md` | layout, creation order, spike checklist, deviations, not built |
| `TEST_SCRIPT.md` | 14-step manual end-to-end test |
| `ADT_DEPLOYMENT_RUNBOOK.md` | agent instructions for deploying with the ADT MCP server in VS Code |
| `SESSION_SUMMARY.md` | this file |

### Deviations from the approved design

* **Job scheduling:** the background processing framework (bgPF) is, per SAP community sources, available on-premise only from release 2023. On 2022 the saver calls `Z_FI_UPL_SCHEDULE` with `IN BACKGROUND TASK`, which does `JOB_OPEN` / `SUBMIT ZFI_UPL_RUN` / `JOB_CLOSE`.
* Item rows carry the company code (`bukrs`) for access control.
* Cleared-item flag read from `ACDOCA-AUGBL` (existence unverified).
* Lock check = one `ENQUEUE_READ` per Validate, filtered in memory.
* The plan's combined "Doc Number + Year" column is not accepted.
* The xlsx reader was **written fresh** (not copied from the existing `lcl_xlsx_reader`).

### Fixes made while building (self-review, nothing was compiled)

* Behavior definition: `authorization master ( global, instance )` (a global authorization method existed without being declared).
* DDLX syntax slip removed; typing issues fixed in parser, engine, job and `ZCL_FI_DOC_CHANGER` (inline `VALUE STANDARD TABLE OF` replaced by a declared table); unverified `%element` typing dropped from the behavior pool.

## 5. Verification actually performed

* `node webapp/test/Template.test.js` -> passed (template headers match the parser's names and order, example row lengths, workbook build call).
* `manifest.json` parsed as valid JSON; JS syntax checked with `node --check`.
* Repository contents checked through the GitHub API after the pushes.
* **Nothing in ABAP, CDS or BDEF has been compiled, activated or unit-tested.**

## 6. Open risks and unverified items (details in `README.md` -> "Step 0 spike")

1. `FI_DOCUMENT_CHANGE` on G/L (`BEBAN`) lines: one community source says it cannot change `KOART S` lines; the plan's own flow depends on it. Test via `ZRFC_FI_CHANGE_ASSIGN` first.
2. Large-object upload in a non-draft managed BO on 2022 on-premise; file name / MIME binding.
3. `IN BACKGROUND TASK` in `save_modified` under `strict ( 2 )`, and the job running as the saving user.
4. `ENQUEUE_READ` result layout, `ENQUEUE_EFBKPF` before `FI_DOCUMENT_CHANGE`, `ACDOCA-AUGBL`.
5. Throughput at 50,000 rows (xlsx parsing memory, 1,000+ document changes); chunk sizes are constants in `ZIF_FI_UPL_TYPES`.
6. Browser-side *Export to Spreadsheet* with up to 50,000 error rows.
7. Syntax details: DCL `pfcg_auth`, BAL parameter names, `calculate_hash_for_raw`, OData service URL in `manifest.json` (guessed, must be replaced by the published URL).
8. `FI_DOCUMENT_CHANGE` is reported as "not released" (supported through KBA 2713775): clean-core risk accepted for on-premise.
9. ADT MCP server on S/4HANA 2022: announced for systems supported by ADT for Eclipse, but one SAP tutorial lists S/4HANA 2025+ as its prerequisite.

## 7. Not built

Server-side error file, CSV export, `Account` metadata column, job-monitoring screen, Object Page auto-refresh, holding locks between Validate and Post, UI5 QUnit/OPA tests, translations beyond English, `package.json` / `ui5.yaml` / `ui5-deploy.yaml` for deployment, service binding, launchpad tile and PFCG roles (setup steps, not delivered objects).

## 8. Session constraints worth knowing

* No git or curl from the shell: all pushes went through the GitHub API; the existing 97 KB ABAP report was not read in full.
* No SAP system access: all ABAP statements and API facts are from documentation and community sources, and are marked *unverified* where they could not be confirmed. Cited sources are SAP Help Portal, SAP Community and SAP Developer Center pages; several are community blogs, not official specifications.

## 9. Suggested next steps

1. Answer the open design questions above (partial posting, error file, single-document size).
2. Check the G/L-line question (item 1) on the dev system before any further work.
3. Run the ADT MCP deployment per `ADT_DEPLOYMENT_RUNBOOK.md`: create objects, fix compile errors, run ABAP Unit and ATC, publish the service, record all fixes back into the repository.
4. Add the UI5 project files, patch the service URL in `manifest.json`, deploy the app into the same transport.
5. Do the manual setup (SLG0 if needed, PFCG, launchpad, ICF) and run `TEST_SCRIPT.md` in a test company code, including the 50,000-row timing.
6. Release the transport only after those tests.
