# T09 · Qualify end-to-end behavior

**Executor:** agent authors fixtures, automation, QA script, defect fixes and reruns. **Human role:** execute/witness nonproduction QA and report observed results; no implementation assignment. **Depends on:** T06–T08. **Read:** [Q1–Q8](../design/assurance.md).

1. Produce versioned synthetic workbooks, expected rows/CSV, repeatable ABAP Unit, service and UI runs. Compare report/app Plans and distinguish intentional ambiguity/duplicate safeguards from regressions.
2. Prepare a restricted-user QA packet: prerequisites, exact steps, expected rows/statuses, FI before/after and released lock evidence for allowed/denied company and area, blank GSBER, missing-item double, lock conflict, failing second line and read-back. Use controlled QA documents only. No credentials or raw sensitive traces in repo.
3. Inject duplicate submit and worker failures, compare export bytes, check keyboard/access behavior, benchmark representative and over-limit sizes. Record client/software level, role (not credentials), timestamp, fixture digest and correlation ID. Reproduce and fix reported defects yourself.

**Accept:** map each Q ID to repeatable evidence or a blocking defect. Distinguish local, mock, actual QA and unrun cases. Syntax activation is not restricted-user end-to-end evidence. Save human QA disposition and guidance on numeric limits in [session state](../SESSION.md). T10 cannot substitute a self-issued sign-off for missing evidence.
