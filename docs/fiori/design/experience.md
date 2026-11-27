# Page and interaction design

Launchpad intent `#ZFIItemAssignment-manage` → **Assignment Runs** → **Run details**. Deep links carry a run identifier, never file paths, workbook values or permission decisions. Use Fiori elements annotations for list fields, filters, object sections and navigation. Use documented SAPUI5 extension points only for binary upload, review and confirmation. No controller writes FI data.

| Screen | Information hierarchy | Actions and guards |
|---|---|---|
| Assignment Runs | Filter: company, mode, state, created date; default to own runs. Columns: run ID, file, company, ledger, creator/time, mode, state, counts. | New Run; open authorized run. Empty states distinguish “No runs yet” from “No matches for these filters.” |
| New Run | Source → company (`1000`) and ledger (`0L`) → distinct-document limit (`0` means all) → mode (Plan Only by default). Keep selected filename visible. | Label the limit “First N distinct documents”, not rows. Prepare enabled after required fields and one upload. Replacing source or changing any parameter invalidates the plan. No editable business area. |
| Review | Scope summary → eligible documents/items → skips/errors → clearings → row comparisons. Show original worksheet row even after sorting. Use separate counts for source rows and deduplicated FI items. | Finish Plan, Test Locks and Authorization, or Apply Changes according to immutable mode. No live submission for zero eligible items. No area approval inferred from `PLANNED`. |
| Run details | Parameters, timestamp and actor; completed/total document count; result counts; pageable table with row/key, old/target/verified, status, message. | Refresh from server, filter by status, download full result. Refresh is GET-only. Retain list filters on Back. No retry-all button. |

**Live confirmation example** (values bound to the server preview): “Change Assignment (ZUONR) for {itemCount} eligible items in {docCount} documents in company {company}? A document is changed only if all its planned items pass the checks.” Buttons: **Apply Changes**, Cancel. Cancel leaves Prepared unchanged. Disable duplicate invocation while waiting. Lost response: read run state or resubmit the same token; never create a fresh submission automatically.

| Condition | Presentation / next step |
|---|---|
| Invalid date or assignment | Text beside field or source-row detail; message popover jumps to the error. Correct the workbook and prepare a new version. |
| Missing required headers | Persistent error listing all missing names. No eligible counts or Live action. |
| Scope changed since preview | “This preview is out of date. Prepare it again.” Do not silently confirm revised counts. |
| Document denied | Show `SEND_ERROR` and backend diagnostic for all planned siblings. Distinguish a missing BSEG item from a denied nonblank area. A blank GSBER alone gets no warning. |
| Queued / verification pending | “Submitted” / “Verification pending”, not “Changed”. Show latest checkpoint and Refresh; no resubmission. |
| Reconciliation required | “The result of this document is uncertain. Contact FI support with run {id}.” Provide read-only details. |

One emphasized action per step. On narrow screens retain document/item, target and textual status; move comparisons into accessible details. Support keyboard-only selection and submit, focus return after cancel, text equivalents for semantic icons, localized text via i18n and screen-reader announcement of progress without stealing focus. UI acceptance uses both macOS and Windows browsers, not SAP GUI.
