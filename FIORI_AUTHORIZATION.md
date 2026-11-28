# FI assignment upload · signed-in-user authorization contract

Companion to [the approved design](FIORI_APP_SPEC.md). This is an application policy for S/4HANA 2022, not a claim of FB02 parity, a PFCG role delivery, or an assertion that SOAP invokes SACF.

**Trust boundary.** Capture client and user from the authenticated ABAP session when staging an immutable run. Never trust a client-supplied requester, company authorization, group, account type or business area. A service-start or AIF processing check does not establish FI change authority. A configured SACF scenario is not proof of a call ([SAP: scenario-based checks](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/c6e6d078ab99452db94ed7b3b7bbcccf/a9a721a34a4b4e2fa5c12947022c7d76.html)).

**Policy inventory.** Cover all eight objects observed in `FI_DOC_CHANGE`. Security must sign off fields, activities, applicability by item type, data source, and initial-value handling on the installed stack. This is not a list of eight unconditional checks. Deny unresolved requirements; only explicit approved rules may mark an object not applicable. Evaluate every targeted item.

| Object | Proposed decision input / applicability |
|---|---|
| `F_BKPF_BUK` | Posted company code `BUKRS`; change activity `02`. |
| `F_BKPF_GSB` | Posted item business area `GSBER`; change activity `02`. Branch baseline denies a missing item or blank area. |
| `F_BKPF_BLA` | Authorization group applicable to the posted document type. |
| `F_BKPF_KOA` | Posted account type, never spreadsheet `Source Data`. |
| `F_BKPF_BES` | Applicable G/L account group; confirm treatment of reconciliation accounts. |
| `F_BKPF_BEK` | Applicable supplier account group for vendor items. |
| `F_BKPF_BED` | Applicable customer account group; reject customer items outside G/L/vendor scope rather than reclassifying. |
| `F_FAGL_SEG` | Applicable segments of the targeted journal item; ambiguous mapping denies the document. |

Sources: [branch change adapter](zfi_bulk_change_assign.abap), [SAP FI object descriptions](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/ee6ff9b281d8448f96b4fe6c89f2bdc8/d339c2b9a6314e308e96e92635ef61f4.html), [SAP account-group and segment examples](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/ee6ff9b281d8448f96b4fe6c89f2bdc8/023dddaf0890434fb01f79b2852bd12d.html). These do not establish the write API's runtime checks.

**Background execution (approved).** Schedule validation and apply as distinct job steps under the authenticated requester; never allow the client to choose a job user. Before reading protected values or performing work, compare effective job client and user with the owner from trusted persistent storage. On mismatch, stop, record denial and perform no FI read/write. No SOAP or shared technical writer fallback. See [SAP background authorizations](https://help.sap.com/saphelp_snc70/helpdata/en/4b/2b51594c594ba2e10000000a42189c/content.htm); verify actual configuration and job traces in QAS.

**Decision points.** Preview is for change-authorized users; check applicable permissions before disclosing values (including already-set rows). Reauthorize results/exports and enforce ownership. Apply needs explicit owner confirmation of the validated plan. Under the document lock, derive values afresh and repeat applicable checks under the effective requester before any update. A denial blocks the entire document. Return a generic error; limit diagnostic details to restricted audit. Log requester and actual writer independently.

**QA acceptance (not executed).** Exercise allowed and denied scope for each applicable object, blank areas, mixed-scope documents, missing/foreign/stale plans, forged input, wrong job user/client, role changes between steps, direct service calls, deduplicated job confirmation, interrupted commits and safe retries. Capture [STAUTHTRACE callpoints and outcomes](https://help.sap.com/docs/ABAP_PLATFORM_NEW/c6e6d078ab99452db94ed7b3b7bbcccf/927ac87d293a47d8a17368c9f45661f4.html), before/after FI values and requester/writer in QAS. Technical-user success is not a negative control.
