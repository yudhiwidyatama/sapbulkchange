# Business analysis and decisions

**Problem.** The accountant knows the desired project code from a workbook. The risk is not file transfer: it is updating the wrong posted item or treating a successful call as proof that the assignment changed. Keep worksheet row, FI entry-view key and ledger verification key separate throughout the run.

| Need / actor | Current evidence | Proposed decision | Proof |
|---|---|---|---|
| Accountant: reproduce a report plan in a browser | [Report](../../../ABAP_ZPROGRAM_PLAN.md) parses OpenXML and resolves FBL3N BUZEI | Share the parser/resolver, not the selection screen, GUI upload or ALV. Preserve workbook/header aliases and distinct-document limit. | T02, T09: identical normalized keys, order, statuses and CSV for parity fixtures. |
| FI controller: protect posted items | PR [#1](https://github.com/yudhiwidyatama/sapbulkchange/pull/1) plus [#3](https://github.com/yudhiwidyatama/sapbulkchange/pull/3) | Keep company and targeted BSEG business-area change checks on server. Blank area differs from a missing BSEG entry. No new spreadsheet field or user override. | T04/T09: restricted actor, mixed document, lock release, following document succeeds. |
| Accountant: know whether changes persisted | FI commits per document, not per workbook | Return row outcomes, not a single green success flag. Read back committed items. Allow a run to finish with issues. | T06/T07: mixed result and uncertain-commit examples. |
| Support: diagnose without changing FI | Browser sessions can end before work does | Store immutable plan versions, worker checkpoints and authorized results. Support gets no implicit execute or download right. | T03/T06/T08. |

**Example for design reviews.** Worksheet rows 2 and 5 target different items of the same document. Row 2 has a blank area; row 5 is in a denied area. Both validate and appear planned. Test and Live reject both before changing either. An unrelated document can still succeed. If row 5 is instead an unrelated *untargeted* BSEG line, it does not block row 2. Changing the workbook cannot grant the missing authority.

**Scope boundaries.** Only `ZUONR` on existing items. No posting, reversal, clearing, interactive editing of SAP facts, blanket delegation to a batch user or imitation of every standard external RFC authorization. Launchpad access does not imply FI authority. Adding four-eyes approval or supporting public cloud requires a separate design.

## Decisions to record before development or release

| Decision / owner | Recommended starting position | Gate if unresolved |
|---|---|---|
| Release, installed UI5, binding, media upload and job identity / Basis + ABAP lead | Prefer Fiori elements with OData V4; verify on the actual on-premise stack. Use a documented compatible binding if necessary without weakening the logical contract. | T01 records an executable spike. No Test/Live without proven effective-user checks. |
| Display authorization and delegated history / FI security | Default to owner plus approved company read scope; deny delegation until an explicit role and data scope exist. | Negative read/export tests before pilot. |
| Permitted file sizes, expansion, expected volume, throughput and retention / Basis + data owner | Benchmark sanitized representative inputs; record numeric limits, expiry and purge exceptions in client configuration. No invented production defaults. | No unrestricted upload or go-live with unset limits. |
| Application-server files / security | Browser upload by default. Enable alternate input only for approved logical names, directories and role. | Disable alternate input until approved and tested. |
| FI adapter compatibility and OB32 / FI lead | Verify local function, update-task and locking behavior for target release. | No Live until rollback and independent read-back pass in QA. |
