# Phase 1 · Change assignments on posted FI line items

**Design for review — not approval to build.** S/4HANA 2022 on-premise; change `ZUONR` only, not a new posting. Baseline: [Z-program specification, §3](ABAP_ZPROGRAM_PLAN.md). Limits, component names and policies below are proposals, not SAP defaults.

1. **Flow:** Download template → upload one workbook → validate/preview old and new values without writing → confirm **Apply Changes** → view results/download errors. A new file or company code invalidates the plan.
2. **Screen:** One [Fiori elements custom page](https://ui5.sap.com/test-resources/sap/fe/core/fpmExplorer/overview/introduction.html): company-code input with authorized value help, template link, [single-file picker](https://ui5.sap.com/#/api/sap.ui.unified.FileUploader), results table, Validate, Apply and Download Errors. Use [i18n resources](https://ui5.sap.com/1.38.65/docs/guide/2edc3f99883e4a068f040d9e844f14fa.html) for labels/messages; template keys stay stable.
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
| Source Data | Text up to 6 | N | `BEBAN` (default) or `VENDOR`; order only, never authorization |

¹ Required in the canonical template; alternatives above are accepted for existing exports.

4. **Validation:** Server enforces genuine `.xlsx`, ≤2 MiB, ≤500 data rows, first worksheet, unique required headers and valid types. Reject repeated normalized company/document/year/item keys; match the exact posted item, validate all three check fields, warn if cleared, skip unchanged assignments.
5. **Processing:** Proposed synchronous apply, **one document per transaction**. Bind preview to caller and immutable input. Lock, reread, reauthorize, compare with preview; reject the whole document on conflict/denial. Apply G/L before vendor, commit or roll back per document, unlock on every path, and reread before marking Changed. After timeout/re-upload, reconcile first; retry only unresolved, freshly validated documents.
6. **Errors:** Show worksheet row, field, status and actionable message; download failed rows as CSV. Do not expose protected SAP values or distinguish missing from unauthorized items to an unauthorized caller.
7. **Authorization/audit:** The **Fiori backend** checks the authenticated business user before preview, export and apply, independently of service-start or SOAP-user rights. See the [required policy and acceptance cases](FIORI_AUTHORIZATION.md). Audit run ID, requester, actual writer, time, document/item, old/new value for permitted changes, and outcome in restricted [SAP Application Log / SLG1](https://help.sap.com/docs/ABAP_PLATFORM_NEW/864321b9b3dd487d94c70f6a007b0397/c769bcc9f36611d3a6510000e835363f.html).
8. **Backend components (proposed):**
   - `ZFI_ASSIGN_UPLOAD` — OData service for template, validate, apply-one-document and authorized results/export.
   - `ZCL_FI_ASSIGN_UPLOAD` — reuse report parsing, exact-item validation, authorization gate and document change adapter; no new CDS view. Unit-test parsing, duplicate detection and policy decisions; integration-test denial, lock, rollback, read-back and retry.
9. **Open approval gates:** Confirm installed FPS/SPS and SAPUI5 level, actual volume, FI maintainer role/user count, and Security's field/applicability matrix. Release/support status of the report's `FI_DOCUMENT_CHANGE` on this stack: **unverified**. Do not substitute [Journal Entry – Change (Asynchronous)](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/3ab6e6fc510f4840a5508e126ef01e22/c3833c31e7724a79b23e4273290f3e2e.html) or promise synchronous commit semantics for SOAP; changing the write path requires design approval.

**Checklist (design coverage):** ✓ Template download · ✓ File size/type · ✓ Validate-only · ✓ Row errors/CSV · ✓ Authorization · ✓ Audit · ✓ Duplicates/re-upload · ✓ Locks/recovery · ✓ i18n · ✓ Unit/integration tests. Phase 2 starts only after explicit **approved**.
