# Change FI Line Item Assignments

**Application specification · Target: SAP S/4HANA on-premise 2022+ · Proposed launchpad intent: `#ZFIItemAssignment-manage`**

An FI accountant uploads an FBL3N workbook to set the Assignment (`ZUONR`) on specific posted line items. The accountant can see which items would change, test access and locks without writing, and obtain a verified result for each submitted item. The app changes **only** Assignment: it does not post, reverse or clear documents, change amounts, or override FI document-change rules.

**Baseline:** [`ZFI_BULK_CHANGE_ASSIGN` implementation and test plan](ABAP_ZPROGRAM_PLAN.md), including [PR #1](https://github.com/yudhiwidyatama/sapbulkchange/pull/1) and the blank-area exception in [PR #3](https://github.com/yudhiwidyatama/sapbulkchange/pull/3). Its workbook, FI processing and CSV contracts are the parity target. Launchpad navigation, persistent runs, access-controlled history and restart handling below are proposed Fiori requirements, not claims about the existing report. Public-cloud deployment is out of scope.

## 1. User journey and actions

| Surface | Accountant's task | Required behavior |
|---|---|---|
| Launchpad → Assignment Runs | Find a previous run or start a new one | Fiori elements List Report. Default to the user's runs; filter by company code, mode, run state and creation date. Show run ID, filename, creator, time, company, ledger and result counts. Open a row for details. |
| New Run | Choose source and parameters | Require one `.xlsx` binary, company code (default `1000`) and lookup ledger (default `0L`). Offer authorized value help. Document limit is a nonnegative integer, default `0` = all. Mutually exclusive modes: **Plan Only** (default), **Test Locks and Authorization**, **Apply Changes**. Use a browser file picker on macOS and Windows; no SAP GUI, local Excel installation or OLE. Where application-server input is enabled, offer an authorized logical file selection instead of accepting arbitrary server paths. |
| Review | Check scope before submitting | Display filename, company, ledger, limit, mode, distinct documents, eligible items, skips, errors and clearing warnings. Allow drill-down to worksheet row and comparison values. Editing the input invalidates the preview. A preview neither reserves an FI document nor certifies the user can change it. |
| Submit | Run the chosen mode | Plan returns the read-only results. Test checks company authority, locks and the targeted entry-view business areas. Live repeats these checks and requires explicit confirmation showing company, document and eligible item counts and the field being changed. Cancel makes no changes. Disable live submission when no items qualify. Confirmation applies to this immutable preview, not to future uploads. |
| Run details | Follow progress, diagnose or export | Object Page: parameters, progress, summary and pageable item table. Show source row, document/year/item, source, old/target/verified assignment, status and message. Filter by status; preserve original row order for export. Refreshing or closing the page must not resubmit or interrupt a job. Download the full authorized run as CSV, independent of visible page or filters. |

Use one emphasized action per step, persistent text and icons for status (never color alone), labeled inputs, keyboard-operable upload and confirmation, focus on the first invalid field, a message popover for multiple errors and a responsive table with secondary fields available in row details. A successful submission means *queued*, not *changed*. [Fiori floorplan reference](https://developers.sap.com/concepts/fiori-elements-list-report-object-page/).

## 2. Workbook contract

Parse the exact uploaded bytes as OpenXML on the ABAP server (`CL_ABAP_ZIP`, `CL_SXML_STRING_READER`). Resolve the first worksheet through `xl/workbook.xml` and `xl/_rels/workbook.xml.rels`; normalize a leading `/` and fall back to `xl/worksheets/sheet1.xml`. Support shared strings including concatenated rich-text runs (ignore phonetic `rPh`), inline strings, cached formula strings and numeric cells with `t="n"` or absent type. Never execute formulas. Resolve sparse cells by A1 reference, not position in the XML. A bad package or missing required headers stops the whole run before any FI call. List all missing headers together.

Row 1 contains trimmed, case-insensitive headers. Data starts at row 2. Ignore unrelated columns. Business area is not an input: it is determined on the server from the target FI entry-view item.

| Input | Accepted headers | Rule |
|---|---|---|
| Document and year | `Doc Number + Year`; alternatively `Document Number`, `Doc Number`, `Doc. No.`, `Document No`, `BELNR` plus optional `Fiscal Year`, `Year`, `GJAHR` | Reuse the report's combined-key parser. For separate columns without fiscal year, derive year from Posting Date as in the report. Require a valid document and 4-digit year; left-pad document to 10 characters. Skip silently if both document inputs are blank. |
| FI item | `Buzei`, `Line Item`, `Item`, `Itm`, `Line Item No`, `Doc. Item` | Integer 1–999; canonical 3 digits. `1`, `1.0` → `001`; `002` stays `002`. Reject blank, fractional, nonnumeric, zero or out-of-range values. |
| Document type | `Document Type`, `Doc. Type`, `Doc Type`, `Type`, `BLART` | Required and nonblank. |
| Posting date | `Posting Date`, `Post. Date`, `Pstng Date`, `BUDAT` | Required valid date. Accept integer Excel serial (`43496` → `20190131`), `YYYYMMDD`, `YYYY-MM-DD`, `DD.MM.YYYY`, `DD/MM/YYYY`. |
| G/L account | `G/L Account`, `G/L`, `GL Account`, `HKONT`, `RACCT` | Required and nonblank. Compare without leading zeros. |
| New assignment | `KODE PROJECT` | Trim; require 1–18 characters. Never truncate or use blank to clear an assignment. |
| Metadata | `Source Data`, `Account` | When source column is absent use `BEBAN`; if present require `BEBAN` or `VENDOR`. `Account` is optional and is not an item locator. |

Record invalid data rows as `EXCEL_ERROR` with the worksheet row and reason. Do not silently drop them. Apply the limit to the first N distinct `(BELNR,GJAHR)` pairs in discovery order, not to N lines: retain all qualifying rows of selected documents even if they occur later in the sheet. Do not treat out-of-scope documents as missing in SAP.

## 3. Resolution and row outcomes

Bulk-read ACDOCA by selected company (`RBUKRS`), ledger (`RLDNR`) and deduplicated document/year keys. Read `BELNR`, `GJAHR`, `DOCLN`, `BLART`, `BUDAT`, `RACCT`, `ZUONR`; obtain clearing document `AUGBL` from BSEG by company/document/year/item. Guard empty key sets; use set-based reads rather than selects per spreadsheet row. Resolve using `BUZEI` = last 3 characters of `DOCLN` (`docln+3(3)`); never guess from G/L, amount or source. Ledger narrows the lookup; the FI change itself is keyed by company/document/year/item, not ledger.

| Row status | Rule and next action |
|---|---|
| `EXCEL_ERROR` | Invalid workbook row. Correct input and upload again. |
| `DOC_NOT_FOUND` | No ACDOCA lines for the document/year in the selected company and ledger. |
| `ITEM_NOT_FOUND` | Document exists but no matching item. Check BUZEI. |
| `VALIDATION_FAILED` | Matched item fails document type (uppercase, condensed), posting date (normalized date) or account (strip leading zeros). List **every** mismatch with workbook and SAP values; never update this row. |
| `SKIPPED_ALREADY_SET` | All validations passed and existing assignment equals target. No lock or change call for this row. |
| `PLANNED` | Valid item, different assignment. If `AUGBL` is noninitial, show “Cleared item (AUGBL=…); verify OB32 field status.” This is a warning, not permission to bypass FI rules. Final outcome in Plan Only. |
| `TESTRUN_OK` | Company authorization passed, document was locked, every targeted BSEG item existed, all applicable business-area checks passed and the lock was released. Not a guarantee that FI will accept a live change. |
| `SEND_ERROR` | Document lock, locked preflight or change failed. Show the diagnostic on every affected planned item; continue with the next document. A denied area is not an Excel error or a warning the user may override. |
| `CHANGED` | After successful commit, an independent ACDOCA read confirms target. |
| `NOT_CHANGED` | Read-back completed but did not confirm target. Report observed value or missing item. Do not silently retry. |

**Additional fail-closed rules:** Reject conflicting upload targets for the same FI key as `EXCEL_ERROR` for each conflicting row. For identical duplicates, execute once and link each source row to that outcome. If multiple ledger lines map to the same BUZEI, use `VALIDATION_FAILED` with an ambiguity diagnostic instead of choosing one. Show these conditions during review.

## 4. FI transaction boundary

1. Authenticate and enforce company-level read authorization for preview, run detail and export. For Test and Live require `F_BKPF_BUK` with selected `BUKRS` and `ACTVT = '02'`. Deny the run before FI processing if missing; hiding a button does not enforce authorization. Execute under the initiating user's effective authorizations; a privileged worker must not expand them.
2. Group only `PLANNED` items by company/document/year. Plan makes no FI lock, FI change or FI commit. Test and Live acquire `ENQUEUE_EFBKPF` for each document. Lock conflict → `SEND_ERROR` for that group, continue. While locked, read `BUZEI, GSBER` once from `BSEG` for this `BUKRS/BELNR/GJAHR`. Match each target by `BUZEI`; apply the decision table below **before Test can succeed or Live can call `FI_DOCUMENT_CHANGE` for any item**. In Test, on success release with `DEQUEUE_EFBKPF`, return `TESTRUN_OK`; do not call `FI_DOCUMENT_CHANGE`.
3. In Live, under the document lock recheck identity, validations, clearing warning and expected old assignment against the confirmed plan. If inputs changed, do not overwrite: fail the pending document group with a stale-preview diagnostic and require a fresh review. For unchanged input, process `BEBAN` before `VENDOR`. For each eligible item call `FI_DOCUMENT_CHANGE` with `I_BUKRS`, `I_BELNR`, `I_GJAHR`, `I_BUZEI` and `ACCCHG` entry `FDNAME='ZUONR'`, `OLDVAL=old`, `NEWVAL=target`. No direct updates to ACDOCA/BSEG.
4. **One FI logical unit of work per document.** A change failure on any planned line triggers `BAPI_TRANSACTION_ROLLBACK`, unlock and `SEND_ERROR` for all participating lines with the formatted SAP message. Previously excluded lines retain their status. On success call `BAPI_TRANSACTION_COMMIT` with `WAIT='X'`, check the outcome and release the lock. Continue independently with other documents. Never commit per row or hold locks across user interaction.
5. `SENT` is internal, not final success. After commit bulk-read the selected ledger's ACDOCA `BYPASSING BUFFER` and compare each assignment with target. Publish `CHANGED` or `NOT_CHANGED` only from that read. If verification is temporarily unavailable, show **Verification pending** at run level and retry the read, not the change. Route uncertain commit outcomes to reconciliation; equality alone after a crash does not establish who changed the item.

### Locked business-area decision table (Test and Live)

| Entry-view result for a targeted item | Worker action |
|---|---|
| No BSEG row matches BUZEI | Fail this document: `No BSEG item {item}; business area cannot be verified`. A missing row is not a blank area. |
| Matching row; `BSEG-GSBER` is initial | Skip only `F_BKPF_GSB` for this item. Keep the item eligible and continue checking the other targets. No blank-area rejection or warning. |
| Nonblank area not yet checked for this document | Check `F_BKPF_GSB`, `GSBER = BSEG-GSBER`, `ACTVT = '02'` as the initiating user. On denial: `No authorization (F_BKPF_GSB ACTVT 02) for business area {area}`. |
| Same area already authorized for this document | Reuse the result within this locked document only. Never reuse a preview, a prior run or another user's result. |

On the first preflight failure, release the lock, issue no FI change or commit for that document, and return `SEND_ERROR` for **every planned sibling**, even one in a permitted or blank area. Leave previously excluded rows unchanged and continue with other documents. Show the reason in run details and the existing CSV `message` column. Untargeted items do not require area authority. The explicit local FI change checks cover company and business area only; they do not reproduce the external RFC checks for document type, customer, vendor, G/L account, account type or segment.

## 5. Service, persistence and operational controls

Proposed design: Fiori elements List Report/Object Page, SAPUI5 upload/review extension, authenticated OData service and a background ABAP worker. Extract the report's parser, lookup provider, changer and CSV serializer behind reusable interfaces; neither invoke a GUI report nor create a second FI update algorithm. Isolate classic FI calls in a target-release-approved on-premise adapter; validate support, OB32 configuration and update-task behavior in QA. The service records job intent; the worker owns FI commits outside the HTTP request or RAP save sequence.

| Service operation (logical contract) | Inputs and guarantees |
|---|---|
| Create run / attach workbook | Store run ID, creator, timestamps, company, ledger, mode, limit, filename, file digest and private binary. Validate file signature and configured upload/decompression limits. Reject malformed, encrypted or unsupported files before processing. |
| Prepare | Parse and resolve; persist worksheet row, normalized key, validation inputs, old/target, warning and immutable plan version. Return counts and paged comparisons. |
| Submit | Require mode, run ID and current plan version; require explicit live confirmation. Atomically claim a submission key. Duplicate clicks return the existing execution; stale versions are rejected. |
| Read run / items / export | Recheck ownership or delegated role and company access on every request. Return run state separately from row outcome. Export UTF-8 RFC-4180 CSV in exact order `doc,year,item,source,old,target,status,message`; retain key padding, escape quotes, commas and newlines, and compare bytes against the baseline. Do not add audit columns to the parity export. |

Run lifecycle: Draft → Prepared → Queued → Running → Completed or Completed with issues. Fatal input/authorization/job failure → Failed; unresolved commit or verification → Reconciliation required, not Completed. A document-level area denial is a completed run with issues if processing otherwise finishes; it is not a run-wide company denial. Persist a per-document checkpoint and execution identifier before calling FI; on restart never replay an uncertain document automatically. Preserve evidence of old, target, observed value, operator, scope, mode, timestamps, status and SAP messages. Restrict raw workbook retention and audit access by approved finance policy; do not write workbook contents into technical logs. Enforce CSRF protection for mutations and restrict application-server file access separately.

## 6. Acceptance and release gates

| Test | Pass criterion |
|---|---|
| Workbook parity | macOS and Windows browser uploads of equivalent Excel/openpyxl files produce identical normalized rows. In-memory ZIP fixtures cover rich/phonetic, inline, shared, cached and numeric cells, sparse `A/F/I/Y/AA`, and leading-slash sheet relationship. No client Excel or SAP GUI dependency. |
| Input boundaries | Combined key, separate key and posting-date year fallback agree. Missing headers list every omission. Blank document row ignored; blank item, `0`, `1000`, bad date, missing type/account/source value and 19-character assignment fail. An 18-character assignment succeeds. For A/B/A document order and limit `1`, both A rows are in scope. |
| Match and skip | Two items sharing a G/L resolve by BUZEI. Exercise missing document, missing item, ambiguous mapping, conflicts, already-set target, cleared warning and all three validation mismatches on one row. No excluded item reaches the changer. |
| Mode isolation | With mocked provider/changer assert zero FI writes for Plan and Test, no lock for Plan, lock/release for Test. Unauthorized Test/Live and cancelled live confirmation cause no changes. |
| Restricted user: blank and permitted areas | With company change authority, all-blank targets cause zero area checks; blank plus two targets in one permitted area causes one area check. An untargeted denied area does not block the document. Test succeeds without writing; Live may update. Remove company change authority: even the all-blank run is denied. |
| Restricted user: denied area or missing entry-view item | Put a denied area after a permitted target, then repeat with a missing BSEG item. In Test and Live the worker releases the lock, makes zero FI changes for the document, reports the appropriate diagnostic on every planned row, and continues. Check UI and CSV. A worker with broader rights cannot convert denial to success. |
| Document atomicity | With two planned items in document A and one in B, force failure on A's second item. Neither item of A changes, both report `SEND_ERROR`, and B proceeds. Verify ordering, cleanup after lock conflict, commit-and-wait, positive and negative read-back results. |
| Fiori and recovery | Verify browser reload, duplicate submit, stale preview, unauthorized direct run/export access, keyboard flow and explicit confirmation. Interrupt after commit before result persistence: recovery must not call the changer a second time. Compare full CSV bytes including a quoted message to the report fixture. |

Use harmless, short ABAP Unit tests with fake file, database, lock and change providers; UI/service automation for user actions and authorization boundaries; and controlled FI documents in a nonproduction S/4HANA client for actual locking, rollback and read-back. Before transport, pass ATC/SCI and obtain FI owner sign-off on source parity, security roles, supported release/service binding, authorized server directories, retention and measured upload/job limits. Deliver the UI app, service and worker, shared ABAP components, persistence, launchpad catalog/role mappings, automated fixtures and operations runbook. This document specifies those deliverables; it does not deploy them.
