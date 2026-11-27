# Change FI Line Item Assignments · AI agent handoff

**Start here in a fresh session.** You are the sole implementer of this Fiori app. You write the code, tests, fixtures, technical decisions, configuration artifacts and runbook. Humans provide guidance on policy/scope and perform or witness QA. Do not assign implementation to an ABAP developer, a UI team, Basis or an FI controller. Those terms in the functional designs describe expertise, application users, operational responsibilities or approval domains—not additional project staff.

## First actions

1. Open [session state](docs/fiori/SESSION.md). Check the actual branch, HEAD, working tree and relevant history against the checkpoint. Preserve unrelated work. If the record and tree disagree, reconcile them before claiming progress.
2. Read the [Fiori contract](FIORI_APP_SPEC.md), [report contract](ABAP_ZPROGRAM_PLAN.md), selected task and its linked design. Use the existing report as the parity reference. Document any discrepancy; ask for guidance if resolving it would change behavior or authority. This handoff changes delivery ownership, **not** SAP security, FI rules or release criteria.
3. Pick the first unfinished task whose inputs are available. Implement one testable slice, run its checks, record evidence, then checkpoint. Continue independently through reversible implementation decisions. If target access is missing, build the safe offline portion with doubles and queue a precise QA request. Do not declare target compatibility or release readiness from a mock.

## Design references

[Business decisions](docs/fiori/design/analysis.md) · [Screens and interactions](docs/fiori/design/experience.md) · [Service and persistence](docs/fiori/design/service-data.md) · [FI execution and recovery](docs/fiori/design/execution.md) · [Q1–Q8 verification matrix](docs/fiori/design/assurance.md).

## Implementation queue

| Task | Inputs / integration gate |
|---|---|
| [T01 · Target stack and execution identity](docs/fiori/tasks/T01-platform.md) | Start here; distinguish offline spike from target QA. |
| [T02 · Workbook planner](docs/fiori/tasks/T02-planner.md) | T01 interfaces; characterization can start offline. |
| [T03 · Run storage and claims](docs/fiori/tasks/T03-storage.md) | T01 persistence choice for target integration. |
| [T04 · Locked FI adapter](docs/fiori/tasks/T04-fi-adapter.md) | T01 identity contract; unit-test with doubles before target QA. |
| [T05 · Upload, prepare and read service](docs/fiori/tasks/T05-service.md) | T02, T03. |
| [T06 · Submission and worker](docs/fiori/tasks/T06-worker.md) | T03, T04, T05; no Test/Live enablement without T01 evidence. |
| [T07 · Fiori pages](docs/fiori/tasks/T07-ui.md) | T05; mock Submit until T06 is ready. |
| [T08 · CSV and history](docs/fiori/tasks/T08-export.md) | T03, T05; wire into T07. |
| [T09 · Qualification](docs/fiori/tasks/T09-qualification.md) | T06–T08 for end-to-end cases. |
| [T10 · Release package](docs/fiori/tasks/T10-release.md) | T09 evidence; release decision is not agent self-approval. |

Milestones: first match report and browser Plan with no FI writes; then prove restricted-user Test in QA; only then evaluate Live readiness. Do not run both entry points against the same change set during cutover.

## When to involve a human

| Situation | Agent action | Human contribution |
|---|---|---|
| Normal engineering choice; reversible and within contract | Choose, implement, test, record rationale. | None. |
| Missing target QA evidence | Supply fixture, prerequisites, steps, expected result and safe evidence to return. Continue unrelated work. | Execute/witness the QA scenario and report observation. |
| Ambiguous business behavior, data retention, permitted scope or release decision | Record options, impact, recommended default and exact decision needed. Keep the affected capability disabled. | Decide in a guiding session; no coding or debugging assignment. |
| Missing privileged access, unknown commit, destructive action or production change | Stop the affected path. Never request credentials in chat, grant roles, deploy to production or replay an uncertain FI change on the strength of this handoff. | QA/guidance only; explicit environment-specific authorization is separate. |

**Example kickoff:** “Read `FIORI_DESIGN.md` and `docs/fiori/SESSION.md` at current HEAD. Resume the next eligible task. Deliver its implementation and repeatable tests, update the checkpoint, and bring back only decisions or target QA that you cannot verify.”
