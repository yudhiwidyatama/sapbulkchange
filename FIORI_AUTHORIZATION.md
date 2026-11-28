# Phase 1 · Signed-in-user authorization contract

Companion to [the one-page design](FIORI_APP_SPEC.md), §7. This is a proposed **application policy** for S/4HANA 2022, not a statement of FB02 parity, a PFCG role delivery, or an assertion that the SOAP service invokes SACF.

**Trust boundary.** Use the authenticated ABAP business principal in the receiving client, not a username, business area, account type or authorization group from the workbook or request. Resolve target keys and authorization values from SAP's posted entry-view item, journal lines and applicable master/configuration data. The observed read-side user was unrelated to the writer. Service-start and AIF processing checks are not evidence of FI authorization. A configured SACF scenario is not proof of a call on this path ([SAP: scenario-based checks](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/c6e6d078ab99452db94ed7b3b7bbcccf/a9a721a34a4b4e2fa5c12947022c7d76.html)).

**Policy inventory.** Cover all eight objects listed in the project's `FI_DOC_CHANGE` scenario evidence. This table is the review scope, **not eight unconditional checks with guessed fields**. Security must sign off each object's actual fields, activities, applicability by item type, data source, and initial-value handling on the installed stack. Unverified or unresolved requirements block apply; only an explicit approved rule may mark an object not applicable. Check all applicable values for every targeted item; do not short-circuit on a permitted company code.

| Object | Proposed decision input / applicability |
|---|---|
| `F_BKPF_BUK` | Company code of the posted document (`BUKRS`); change activity `02`. |
| `F_BKPF_GSB` | Posted item's business area (`GSBER`); change activity `02`. Baseline on this branch: missing item or blank area denies the document. No inferred exception. |
| `F_BKPF_BLA` | Authorization group applicable to the posted document type; not the uploaded document-type text. |
| `F_BKPF_KOA` | Posted account type, not the spreadsheet's `Source Data` label. |
| `F_BKPF_BES` | Applicable G/L account authorization group; confirm treatment of reconciliation accounts. |
| `F_BKPF_BEK` | Applicable supplier account authorization group for vendor items. |
| `F_BKPF_BED` | Applicable customer account authorization group; customer items are outside the G/L/vendor upload scope and must not be reclassified to pass. |
| `F_FAGL_SEG` | Applicable segment(s) of the targeted journal item; ambiguous mapping denies the document. |

Baseline checks: [project changer](zfi_bulk_change_assign.abap). Object terminology: [SAP FI object descriptions](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/ee6ff9b281d8448f96b4fe6c89f2bdc8/d339c2b9a6314e308e96e92635ef61f4.html), [SAP account-group and segment examples](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/ee6ff9b281d8448f96b4fe6c89f2bdc8/023dddaf0890434fb01f79b2852bd12d.html). These references **do not** establish runtime checks for this write API.

**Decision points.** Preview is a simulation for change users: require the applicable change permissions before revealing SAP values, even for already-set rows. Protect results, logs and downloads against cross-user access. At Apply, reject a missing/foreign/stale plan, take the document lock and repeat all checks with fresh SAP data and the current principal before any change. One denial means no lines in that document are written. Report a generic denial; retain diagnostic detail only in the restricted audit log. No UI-only validation, silent bypass or technical-user fallback.

**Writer identity.** Prefer an in-session write under the signed-in user, subject to the adapter approval gate. If a separate async writer is later proposed, restrict its credentials and direct invocation to the approved integration, audit both identities, and distinguish authorization at submission from authorization at execution. If execution-time business-user enforcement is required and cannot be demonstrated, do not enable that path.

**QA acceptance (planned, not executed).** An authorized user can preview/apply and obtain verified read-back. For each applicable object, a restricted user receives no protected values and causes no change, including direct service calls. Test mixed authorized/denied lines, blank business area, changed roles or master data after preview, forged input, foreign plan/export, lock conflict and ambiguous retry. Capture [STAUTHTRACE callpoints, checked values and outcomes](https://help.sap.com/docs/ABAP_PLATFORM_NEW/c6e6d078ab99452db94ed7b3b7bbcccf/927ac87d293a47d8a17368c9f45661f4.html), before/after FI values, and audit requester/writer in QA; never use a successful technical-user write as the negative-control result.
