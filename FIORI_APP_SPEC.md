# FI assignment upload · approved design

S/4HANA 2022 on-premise. Change only `ZUONR` on existing posted FI items; do not create postings. Baseline: [Z-program specification §3](ABAP_ZPROGRAM_PLAN.md). Approved application limits are inclusive, not measured capacity or SAP system settings.

1. **Flow:** Download template → upload once → validate in background and preview → explicitly confirm Apply → view paged results/download errors. Validation never changes FI data. Changing file/company creates a new run and invalidates the previous confirmation.
2. **Screen:** One [Fiori elements custom page](https://ui5.sap.com/test-resources/sap/fe/core/fpmExplorer/overview/introduction.html): authorized company-code value help, template link, [single-file picker](https://ui5.sap.com/#/api/sap.ui.unified.FileUploader), run status, paged table, Validate, Apply and Download Errors. Use [i18n texts](https://ui5.sap.com/1.38.65/docs/guide/2edc3f99883e4a068f040d9e844f14fa.html); template keys are stable.
3. **Template:** One company code per upload (screen, text 4, mandatory → `I_BUKRS`); ledger `0L` for validation. Support baseline FBL3N aliases and combined document/year or posting-date year fallback. The table maps the project adapter, not a released BAPI claim ([SAP item-key reference](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/3ab6e6fc510f4840a5508e126ef01e22/8247ba7cf3344cb6b1092443d10cdebf.html)).

| Worksheet field | Type / length | Required | Adapter input or validation-only source |
|---|---|:---:|---|
| Document Number | Text 10 | Y | `I_BELNR` |
| Fiscal Year | Numeric text 4 | Y in canonical template | `I_GJAHR` |
| Line Item | Numeric text 3 (`001`–`999`) | Y | `I_BUZEI` |
| Document Type | Text 2 | Y | Validate `ACDOCA-BLART` |
| Posting Date | Excel date or date text; normalized length 8 | Y | Validate `ACDOCA-BUDAT` |
| G/L Account | Text 10 | Y | Validate `ACDOCA-RACCT` |
| KODE PROJECT | Text 1–18 | Y | `T_ACCCHG-NEWVAL` for `ZUONR` |
| Source Data | Text up to 6 | N | `BEBAN` (default) or `VENDOR`; order only |

4. **Validation:** Server measures raw uploaded XLSX bytes: **≤20 MiB (20,971,520 bytes)**. Validate the package and bound expanded content separately before parsing. First worksheet: **≤50,000 nonblank data rows**, excluding header, counting invalid rows. Reject the entire file at 20,971,521 bytes or 50,001 rows; never truncate. Validate headers/types, detect duplicate normalized keys across the whole run, check all three posted values, warn if cleared, skip unchanged assignments.
5. **Processing:** Persist immutable input by client/requester/run; return a run ID. Separate resumable background **Validate** and **Apply** jobs. Only an authorized owner may confirm the validated run; atomically queue it once. Each worker verifies its effective client/user against the stored owner. Apply locks, rereads, reauthorizes, compares and updates **one whole FI document per transaction**; G/L before vendor. Roll back the document on failure, unlock, checkpoint and reread before marking Changed. Reconcile uncertain outcomes before retry; never blindly resubmit.
6. **Errors:** Show row, field, status and actionable message; export failed rows across all pages. No protected SAP values or distinguishable missing/unauthorized errors for an unauthorized caller.
7. **Authorization/audit:** Enforce [the backend authorization contract](FIORI_AUTHORIZATION.md) before preview/export and under lock at apply. Record run, requester, actual writer, time, document/item, permitted old/new values and outcome in restricted [Application Log / SLG1](https://help.sap.com/docs/ABAP_PLATFORM_NEW/864321b9b3dd487d94c70f6a007b0397/c769bcc9f36611d3a6510000e835363f.html).
8. **Backend components:** `ZFI_ASSIGN_UPLOAD` — upload, template, queue validation, confirm/queue apply and authorized results/export. `ZCL_FI_ASSIGN_UPLOAD` and job worker — parser, persistent run/checkpoints, policy checks, change adapter and read-back. No new CDS view. Test exact and over-limit sizes/rows, cross-chunk duplicates, identity mismatch, concurrency, lock, rollback, recovery and end-to-end authorization.
9. **Deployment gates:** Confirm installed FPS/SPS/UI5, user roles/count, complete Security matrix and supported FI write adapter. `FI_DOCUMENT_CHANGE` release/support status for this stack: **unverified**. No substitution of the [async SOAP change service](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/3ab6e6fc510f4840a5508e126ef01e22/c3833c31e7724a79b23e4273290f3e2e.html). Qualify ingress/proxy limits, job identity, expanded XLSX size, peak memory, runtime and restart in QAS; do not silently change infrastructure limits.

**Checklist (design):** ✓ Template · ✓ Limited upload · ✓ Validate-only · ✓ Row errors/CSV · ✓ Authorization · ✓ Audit · ✓ Duplicates/re-upload · ✓ Locks/recovery · ✓ i18n · ✓ Unit/integration tests.
