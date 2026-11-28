# T01: effective background user — nonproduction QA only

Decision: isolate the execution-context question from the file/service question. The probe checks four policy fixtures under the runtime user (no `FOR USER`); it neither reads BSEG nor simulates locked FI preflight. It has no FI update, lock or commit path. Fixture areas are not proposed workbook fields. A job owner, a saved creator, a green SM37 state or a matching username alone proves nothing about change authority.

## Run card

1. Prerequisites: approved nonproduction client, reviewed executable report `ZFI_T01_IDENTITY` from `spikes/t01/zfi_t01_identity.abap` staged through the approved QA process, and an existing restricted QA account permitted to run the report and schedule its own step. Syntax check and activate only in an authorized development environment. If any prerequisite is missing, record NOT RUN. Do not grant roles, switch to a batch administrator or use a production client.
2. Before execution, record the expected SID, three-character client, restricted logon and exact fixture values from the approved test profile. `P_CA`/`P_CD`: distinct allowed/denied companies for `F_BKPF_BUK`; `P_AA`/`P_AD`: distinct nonblank allowed/denied areas for `F_BKPF_GSB`; all at activity `02`. Use the same values both times. No workbook or accounting document required.
3. As that user in SE38, execute the report interactively with those values and save a QA variant. Save the list as UTF-8 plain text `dialog.txt` in the approved evidence store. Expect DIALOG, the restricted user and return codes `0,4,0,4` in the order company+, company-, area+, area-. Other codes are inconclusive/fail, not an acceptable denial.
4. Without changing account or variant, use SM36 to define a one-time job, add the ABAP program and variant, leave the step user as self, choose Immediate, then save. In SM37 locate this exact job by name, creator and start time; check job count, client, step program/variant/user and finished status. Open its spool and save the plain text as `job.txt`. Expect BATCH with the same principal, SID, client, fixture values and four return codes. If the job cannot run under the restricted actor, stop.
5. On the approved evidence workstation run `python3 spikes/t01/check_identity.py dialog.txt job.txt SID CLIENT ACTOR CA CD AA AD` from the repository root, replacing the final seven arguments with the independently recorded values (preserve leading zeros). Expect exit 0 only for matching lists. Nonzero, missing spool, incorrect provenance, or an unexpected allow: retain the failure; do not retry under a broader account. Do not substitute the unit-test strings for observed output.
6. Record date, sanitized client/environment and actor aliases, job evidence reference, code matrix, syntax/activation and observed result in SESSION. Keep raw spool, usernames and any traces in the approved evidence store, not Git. Remove disposable variants/job artifacts per QA retention policy. Even a match qualifies only this classic scheduling route. Repeat through the selected service submission and actual worker path before considering the execution gate.

## Platform decision log — proposed, not installed facts

| Area | Candidate / open verification |
|---|---|
| Stack | S/4HANA on-premise 2022+ design target. Inventory S4CORE, SAP_BASIS, SAP_GWFND and SAP_UI release/SP via System > Status; record actual browser UI5 version from launchpad technical information. All unverified. |
| Binding/UI | Prefer RAP OData V4 + Fiori elements upload/review extension. If unsupported evaluate Gateway V2 media entity/action with identical owner checks, CSRF, bytes, paging and job semantics. No binding, extension or FLP content verified. |
| Upload/storage | Browser `.xlsx` only; no server paths. Propose client-dependent private run/header/item/binary tables. Size/expansion/retention require approved limits. No production defaults. |
| Scheduling/FI | Classic own-user step is a diagnostic candidate, not an approved service scheduler. Local FI_DOCUMENT_CHANGE support, OB32, enqueue/dequeue scope, rollback and update-task/commit-and-wait behavior remain unverified. No FI calls in this probe. |
| Deployment | Propose ZFI_ASSIGN subpackages for service/storage, worker and UI; separate workbench objects from client-specific FLP catalog/role configuration. Isolate QA probe from release transports. No deployment authorized. |

Next implementation slice: a separate harmless binary round-trip, ordered paged read and CSRF-protected no-op action contract with offline doubles; then obtain target binding and launchpad evidence. No Test/Live enablement.
