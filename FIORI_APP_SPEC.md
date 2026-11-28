# Phase 1 · Change assignments on posted FI line items

**Phase 1 approved with a capacity amendment: up to 50,000 data rows per workbook.** This is a design limit, not a measured throughput guarantee. S/4HANA 2022 on-premise; change `ZUONR` only, not a new posting. Baseline: [Z-program specification, §3](ABAP_ZPROGRAM_PLAN.md).

1. **Flow:** Download template → upload one workbook → validate/preview old and new values without writing → confirm **Apply Changes** → view results/download errors. A new file or company code invalidates the plan.
2. **Screen:** One [Fiori elements custom page](https://ui5.sap.com/test-resources/sap/fe/core/fpmExplorer/overview/introduction.html): company-code input with authorized value help, template link, [single-file picker](https://ui5.sap.com/#/api/sap.ui.unified.FileUploader), paged preview/results, Validate, Apply and Download Errors. Use [i18n resources](https://ui5.sap.com/1.38.65/docs/guide/2edc3f99883e4a068f040d9e844f14fa.html) for labels/messages; template keys stay stable.
3. **Template:** One company code per upload (screen, text 4, mandatory → `I_BUKRS`); ledger `0L` for validation. Canonical worksheet below; retain the [baseline header aliases, combined document/year and posting-date year fallback](ABAP_ZPROGRAM_PLAN.md). Mappings are to the **project adapter**, not a released BAPI claim; [SAP item-key reference](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/3ab6e6fc510f4840a5508e126ef01e22/8247ba7cf3344cb6b1092443d10cdebf.html).

| Worksheet field | Type / length | Required | Adapter input or validation-only source |
|---|---|:---:|---|
| Document Number | Text 10 | Y | `I_BELNR` |
| Fiscal Year | Numeric text 4 | Y¹ | `I_GJAHR` |
| Line Item | Numeric text 3 (`001`–`999`) | Y | `I_BUZEI` |
| Document Type | Text 2 | Y | Check `ACDOCA-BLART`; do not change |
| Posting Date | Excel date or date text; normalize to 8 digits | Y | Check `ACDOCA-BUDAT`; do not change |
| G/L Account | Text 10 | Y | Check `ACDOCA-RACCT`; do not change |
| KODE PROJECT | Text 1–18 | Y | `T_ACCCHG-NEWVAL`, field `ZUONR` |
| Source Data | Text up to 6 | N | `BEBAN` (default) or `VENDOR` |

¹ Required in the canonical template; alternatives above are accepted for existing exports.

4. **Validation:** Server enforces genuine `.xlsx`, ≤2 MiB pending file-size qualification, and ≤50,000 nonblank data rows in the first worksheet (header excluded; invalid nonblank rows count). At 50,001 reject the entire upload before applying anything; never truncate. Validate headers and types; detect duplicate normalized keys across the whole file, not just within a processing chunk. Match exact posted items, compare all three check fields, warn if cleared and skip unchanged assignments.
5. **Processing:** Approved baseline: synchronous apply, **one document per transaction**, not one transaction per file. Bind preview to caller and immutable input. Lock, reread, reauthorize, compare with preview; reject the whole document on conflict/denial. Apply G/L before vendor, commit or roll back per document, unlock on every path, and reread before marking Changed. After interruption, reconcile first; retry only unresolved, freshly validated documents.
6. **Errors:** Show worksheet row, field, status and actionable message; download failed rows across all pages as CSV. Do not expose protected SAP values or distinguish missing from unauthorized items to an unauthorized caller.
7. **Authorization/audit:** The **Fiori backend** checks the authenticated business user before preview, export and apply, independently of service-start or SOAP-user rights. See the [required policy and acceptance cases](FIORI_AUTHORIZATION.md). Audit run ID, requester, actual writer, time, document/item, old/new value for permitted changes, and outcome in restricted [SAP Application Log / SLG1](https://help.sap.com/docs/ABAP_PLATFORM_NEW/864321b9b3dd487d94c70f6a007b0397/c769bcc9f36611d3a6510000e835363f.html).
8. **Backend components:**
   - `ZFI_ASSIGN_UPLOAD` — OData service for template, validate, apply-one-document and authorized results/export.
   - `ZCL_FI_ASSIGN_UPLOAD` — parsing, exact-item validation, authorization gate and document change adapter. Unit-test parsing and duplicates; integration-test denial, lock, rollback, read-back and retry. In QAS test 49,999/50,000/50,001 data rows, compressed and expanded workbook size, peak memory, elapsed time and interruption/restart, including many distinct documents.
9. **Open gates:** Qualify the 2 MiB cap against representative full-size files; do not silently raise system limits. Recommended high-volume alternative (not yet approved): upload once, stage by requester/run, validate and apply in separate resumable background steps after confirmation, and retain per-document transactions. Require the actual execution principal to equal the authenticated requester; fail closed otherwise. Verify job identity on the installed stack ([SAP background authorizations](https://help.sap.com/saphelp_snc70/helpdata/en/4b/2b51594c594ba2e10000000a42189c/content.htm)). Confirm FPS/SPS, UI5, role/user count, Security's matrix and write adapter before live use. Release/support status of `FI_DOCUMENT_CHANGE`: **unverified**. Do not substitute [Journal Entry – Change (Asynchronous)](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/3ab6e6fc510f4840a5508e126ef01e22/c3833c31e7724a79b23e4273290f3e2e.html).

**Checklist (design coverage):** ✓ Template download · ✓ File size/type · ✓ Validate-only · ✓ Row errors/CSV · ✓ Authorization · ✓ Audit · ✓ Duplicates/re-upload · ✓ Locks/recovery · ✓ i18n · ✓ Unit/integration tests.
