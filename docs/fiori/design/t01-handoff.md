# Assignment Runs: implementation handoff v1

Scope: posted FI item Assignment (`ZUONR`) only. This is a build contract, not evidence that the binding or scheduler is installed. Preserve [service semantics](service-data.md), [transaction boundaries](execution.md) and [Q1–Q8](assurance.md). The business user's entry point is Assignment Runs, never a separate scheduler screen.

## Decisions and remaining target questions

- Preferred implementation: ABAP RAP OData V4 UI binding, Fiori elements List Report/Object Page, supported UI5 upload/review extension. Model a private workbook stream and bound Prepare/Submit actions. If the installed release cannot support these, evaluate Gateway V2 media entity and equivalent actions. Keep identical security, status, idempotency and parity fixtures; document mapping changes before integrating T05/T07. Neither option has target proof here.
- Proposed workbench layout: `ZFI_ASSIGN_CORE` (shared planner, types, FI adapter), `ZFI_ASSIGN_RUN` (client-dependent DDIC tables, repository, outbox, worker and service), `ZFI_ASSIGN_UI` (UI and launchpad content). Transport in dependency order; keep client-specific configuration/catalog/roles separate and QA probe out of release. Actual package/transport names and component inventory require authorized target discovery.
- Persist private workbook, Run, plan rows, execution documents/items, submission/outbox and audit in client-dependent ABAP tables. Use DB uniqueness and conditional claims, not frontend state. Source row `(runId,version,sheetRow)` is not the FI target `(BUKRS,BELNR,GJAHR,BUZEI)` or ledger verification key. Owner and client come from the authenticated backend context. Read access requires owner plus approved company scope; delegation disabled until approved.
- Proposed dispatcher: after the submission/outbox transaction commits, an adapter uses the SAP application-job framework to start the fixed worker for this execution. Job payload is an opaque execution reference, not user-supplied scope or authority. Require target proof of a supported submitter-bound execution context, including delayed dispatch/recovery. A shared outbox consumer's own broad rights are **not** a substitute. The worker must compare effective identity to the saved initiator, then check current authorizations. If binding the correct principal is not supported, leave the intent blocked, keep Plan available and evaluate a supported own-user dispatch alternative before enabling Test. Do not silently schedule under another user.
- Keep an uncertain scheduling reply distinct from an absent job: correlate before retry, fence competing workers on the execution, and never redispatch an uncertain FI attempt. No scheduler or FI commit inside the HTTP/RAP save transaction. The worker owns a separate FI transaction per document. A known commit may be verified by reading again; an unknown commit goes to reconciliation.

## Shared operation map (candidate V4 external names; verify against target metadata)

| Operation | Input | Result / boundary |
|---|---|---|
| Create `Runs`, attach `Workbook` stream | Company, ledger, limit, mode; exact bytes with configured size controls | Draft, run ID and ETag. Store digest and exact length. No public media URL. |
| Bound `Prepare` | Run ID and If-Match | One immutable plan version, ETag, counts, pageable ordered Items. No FI side effects. |
| Bound `Submit` | Run ID, If-Match, planVersion, request token, confirmedLive | Use persisted scope. Plan finalizes without job. Test/Live atomically store submission plus outbox or neither. Return existing execution on identical replay before stale-ETag rejection. No Live without eligible items and confirmation. |
| `Runs`, `Items`, `ResultsCSV` | Server-scoped key, paging for lists only | Reopen by run ID. Return persisted state independently of row outcomes. Export an authorized complete snapshot in worksheet order; not the visible page. |

Example: Prepare returns `{runId:'R1',planVersion:1,etag:'E2',eligibleItems:2}`. Submit sends `{planVersion:1,token:'K1',confirmedLive:false}` with If-Match E2 for a stored Test plan; initial or identical repeated request returns execution `X1`, not evidence of a change. Changed scope requires a new review. A failed document's row status is not a failed HTTP read. See service-data for conflict/error semantics.

## Dependency notes (normative for the task queue)

| Consumer | Input from T01 | Safe work now / integration gate |
|---|---|---|
| [T02](../tasks/T02-planner.md) | Planner takes exact bytes, company, ledger, distinct-document limit and a read-only bulk provider. Returns ordered source rows, normalized FI/ledger keys, old/target, diagnostics and counts. | Characterize the existing report first. Keep duplicates/ambiguity safeguards explicit. No job/UI/storage dependency. |
| [T03](../tasks/T03-storage.md) | Keys, immutable plan version, client boundary, conditional claim, atomic submission/outbox. | Model races offline; prove database concurrency on target. |
| [T04](../tasks/T04-fi-adapter.md) | Verified effective actor at worker entry, current company authority, locked BSEG checks before writes. | Test order, failures and rollback with doubles; target identity and controlled FI tests before enablement. |
| [T05](../tasks/T05-service.md) | Operation map, planner output and repository boundary. | Publish common request/response fixtures; qualify actual media, CSRF, ETags, display scope and deterministic paging. |
| [T06](../tasks/T06-worker.md) | Same Submit, outbox, dispatch adapter and worker entry as T01-B. | Build replay/recovery with doubles; require B for real Test/Live. No second scheduler implementation. |
| [T07](../tasks/T07-ui.md) | Assignment Runs consumes T05 fixtures then the same service. | Plan first; display Submit as queued, not changed. No client-side permission or eligibility decision. |
| [T08](../tasks/T08-export.md) | Stable row IDs/order and owner/company-scoped snapshot. | Compare report CSV bytes offline; qualify full-run export independently of page and filter. |
| [T09](../tasks/T09-qualification.md) | Run/version/execution/job correlation, fixture identity, known limitations. | Map Q1–Q8 to actual, mock or unrun evidence; rerun through the product entry point. |
| [T10](../tasks/T10-release.md) | Verified stack, dependencies, transport order, evidence and disabled modes. | Prepare runbook offline; require destination rehearsal, approved limits and explicit release decision. |

Order: characterize report → browser Plan parity → harmless product-path Submit → restricted Test → separately authorized Live qualification. Offline contract development may overlap. No diagnostic gate is a release decision.
