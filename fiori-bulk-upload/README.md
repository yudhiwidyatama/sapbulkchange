# FI Assignment (ZUONR) bulk upload - Fiori elements app (S/4HANA 2022 on-premise)

Implements the approved Phase 1 design (revision 2): upload an `.xlsx`, **Validate** (authority + file/row
checks + `ACDOCA` resolution + lock check, background job), **Post** (background job, one document per LUW),
view results per row. Business rules come from `ABAP_ZPROGRAM_PLAN.md` (`ZFI_BULK_CHANGE_ASSIGN`).

> **Status: written but NOT compiled or run.** There is no SAP system in the build environment. Only the
> UI5 pieces were executed (`node webapp/test/Template.test.js`, `manifest.json` JSON check). All ABAP/CDS/BDEF
> must be activated and the ABAP Unit classes run in ADT before anything is trusted. Expect small syntax fixes.

## Layout

| Path | Content |
|---|---|
| `backend/ddic` | `ZFI_UPL_BATCH`, `ZFI_UPL_ITEM` tables |
| `backend/cds` | interface + projection views, metadata extensions, access control (`F_BKPF_BUK`, ACTVT 03) |
| `backend/bdef` | managed BDEF (`with additional save`), projection BDEF |
| `backend/srv` | service definition `ZFI_UI_UPL` |
| `backend/classes` | `zbp_fi_i_upl_batch` (handler + saver), `zcl_fi_upload_job`, `zcl_fi_upload_engine`, `zcl_fi_upload_parser`, `zcl_fi_xlsx_reader`, `zcl_fi_db_provider`, `zcl_fi_doc_changer`, `zcl_fi_upl_log`, `zcl_fi_upl_msg`, `zcx_fi_upload`, `zif_*`, plus `*.testclasses.abap` |
| `backend/programs` | report `ZFI_UPL_RUN`, function module `Z_FI_UPL_SCHEDULE` |
| `backend/messages/zfi_bulk.txt` | message class `ZFI_BULK` texts |
| `webapp` | Fiori elements V4 List Report + Object Page, template download, i18n |
| `TEST_SCRIPT.md` | manual end-to-end test |

## Creation order

1. **SE91** message class `ZFI_BULK` from `backend/messages/zfi_bulk.txt`. **SLG0** log object `ZFI_BULK`, subobject `UPLOAD`.
2. Tables, then `zif_fi_upl_types`, then CDS views, access controls, BDEFs, `zbp_fi_i_upl_batch`, remaining classes, service definition.
3. **SE80/SE37:** function group `ZFI_UPL`, function module `Z_FI_UPL_SCHEDULE` set to *Remote-Enabled Module*; report `ZFI_UPL_RUN`.
4. ADT: OData V4 - UI service binding `ZFI_UI_UPL_O4` for `ZFI_UI_UPL`, publish. Check that the service URL equals `dataSources.mainService.uri` in `webapp/manifest.json` (adjust if not).
5. Deploy `webapp` (SAP Fiori tools) to the ABAP repository, create the launchpad tile / target mapping.
6. PFCG: `F_BKPF_BUK` (BUKRS, ACTVT 02 for Validate/Post, 03 for display), `S_SERVICE` for the service, `S_BTCH_JOB` (job scheduling), `S_APPL_LOG` for ZFI_BULK, `S_TCODE`/launchpad catalog.
7. Run ABAP Unit for the three `ZCL_FI_*` test classes; `node webapp/test/Template.test.js`.

## Step 0 spike - findings and what you must verify first

Nothing could be executed here, so these are documentation findings plus a checklist for the first day on the system.

* **bgPF is not available on 2022.** SAP community sources say the background processing framework reached
  S/4HANA on-premise with release **2023**. The job is therefore scheduled with `JOB_OPEN`/`SUBMIT`/`JOB_CLOSE`
  inside a tRFC (`Z_FI_UPL_SCHEDULE`), started from `save_modified`. This pattern follows a published RAP example
  (function module `IN BACKGROUND TASK` from the saver class).
* Verify (all **unverified**):
  1. Large-object upload works in the Create page of a **non-draft** managed BO on 2022 (file name and MIME type are derived; a 2023 on-premise gap was reported). The `PK` magic-byte check in `checkInput` does not depend on this.
  2. `CALL FUNCTION ... IN BACKGROUND TASK` is accepted in `save_modified` under `strict ( 2 )`, and the job runs as the saving user (needed for the authority check inside the job).
  3. `ENQUEUE_READ` with `gname = 'BKPF'` returns one entry per lock and `garg` = `MANDT(3) BUKRS(4) BELNR(10) GJAHR(4)` (used by `read_locks`).
  4. `ACDOCA-AUGBL` exists (cleared items). If not, read `BSEG-AUGBL` in `zcl_fi_db_provider`.
  5. `FI_DOCUMENT_CHANGE` changes `ZUONR` on a **G/L (`BEBAN`) line** (one source reports it cannot change `KOART = S`). `ZRFC_FI_CHANGE_ASSIGN` is the reference; test it first.
  6. `ENQUEUE_EFBKPF` before `FI_DOCUMENT_CHANGE` (which locks the document itself) does not return `foreign_lock` for the same session.
  7. **Throughput:** parse + validate 50,000 rows (memory of `CL_ABAP_ZIP` + sXML for a ~20 MB file) and time 1,000 document changes. Tune `gc_doc_chunk`/`gc_post_chunk` in `zif_fi_upl_types`.
  8. `CDS` access control `pfcg_auth( F_BKPF_BUK, BUKRS, ACTVT = '03' )` syntax, `BAL_*` function-module parameter names, `calculate_hash_for_raw` parameter names.
  9. Export to Spreadsheet of up to 50,000 error rows in the browser.

## Deviations from the approved design

* Job scheduling through a tRFC + classic job (bgPF unavailable on 2022).
* Item rows carry `bukrs` so the item access control does not depend on parent inheritance.
* Cleared-item flag is read from `ACDOCA-AUGBL` instead of `BSEG` (one table fewer; verify, see 4 above).
* Lock check = one `ENQUEUE_READ` per Validate, filtered in memory (instead of one call per document).
* The combined `Doc Number + Year` column of the plan is **not** accepted; use `Document Number` + `Fiscal Year`.

## Not built (explicitly)

* CSV export, `Account` metadata column, job-monitoring screen, auto-refresh of the Object Page (press refresh).
* Server-side error file: the built-in *Export to Spreadsheet* of the items table is used (filter the table to the error statuses first).
* UI5 OPA / QUnit tests (only a node test for the template). No ABAP integration test automation: see `TEST_SCRIPT.md`.
* Holding locks between Validate and Post; Post takes the real lock per document.
* Translations other than English (CDS labels via SE63/translation, `i18n_<lang>.properties`, message class translations).
* Service binding, launchpad tile and PFCG roles are setup steps above, not delivered objects.
