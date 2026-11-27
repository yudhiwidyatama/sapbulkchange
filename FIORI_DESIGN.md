# Change FI Line Item Assignments · developer handoff

Start with the [application contract](FIORI_APP_SPEC.md) and [report contract](ABAP_ZPROGRAM_PLAN.md). This pack adds implementation decisions and tests; it does not change the report or authorize a production deployment. Baseline: `f5dce3957f3373cbb1b03a5ebc82e157a2fe208d` on `main`, after PR #3. All technical names below are proposed unless they refer to existing SAP or repository objects.

## Design set

| Read when deciding… | Document |
|---|---|
| What must stay equivalent, who benefits and what still needs approval? | [Business analysis and decisions](docs/fiori/design/analysis.md) |
| What should an accountant see, and when is an action enabled? | [Page and interaction design](docs/fiori/design/experience.md) |
| What crosses the browser/service boundary and what must be persisted? | [Service and data contract](docs/fiori/design/service-data.md) |
| Where do authority checks, locking, commit and recovery belong? | [Worker, security and recovery](docs/fiori/design/execution.md) |
| How will the team prove this is safe to release? | [Verification and operations](docs/fiori/design/assurance.md) |

## Build sequence

Each link is a separately assignable Markdown task. Dependencies are finish-to-start unless the teams agree to develop against the written contract with doubles. A task is complete only with its listed evidence. Tests described here are planned, not executed.

| ID | Programmer work package | Depends on |
|---|---|---|
| T01 | [Prove the target stack and effective user](docs/fiori/tasks/T01-platform.md) | — |
| T02 | [Extract workbook and planning core](docs/fiori/tasks/T02-planner.md) | T01 |
| T03 | [Create run store and state guards](docs/fiori/tasks/T03-storage.md) | T01 |
| T04 | [Implement locked FI adapter](docs/fiori/tasks/T04-fi-adapter.md) | T01 |
| T05 | [Publish secured upload, plan and query service](docs/fiori/tasks/T05-service.md) | T02, T03 |
| T06 | [Submit, dispatch, verify and reconcile](docs/fiori/tasks/T06-worker.md) | T03, T04, T05 |
| T07 | [Build launchpad pages and review flow](docs/fiori/tasks/T07-ui.md) | T05; use T06 for integrated submission |
| T08 | [Deliver full-run CSV and protected history](docs/fiori/tasks/T08-export.md) | T03, T05; integrate into T07 |
| T09 | [Verify parity, permissions and failure recovery](docs/fiori/tasks/T09-qualification.md) | T06, T07, T08 |
| T10 | [Package transports, monitoring and cutover](docs/fiori/tasks/T10-release.md) | T09 |

First milestone: plan the same workbook in report and browser with no FI writes (T01–T03, T05, T07 plan flow). Second: prove restricted-user Test in QA. Enable Live only after T09/T10 sign-off. The report remains a separate entry point; no one should run both against the same change set during cutover.
