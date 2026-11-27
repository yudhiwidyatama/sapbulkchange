# Verification and operating model

Use synthetic identifiers and controlled QA documents. Report, planner and browser must consume the same fixtures; do not copy finance workbooks, assignments, credentials or authorization traces into public tickets. Capture expected vs observed by worksheet row and distinct FI item. The matrix is a release checklist, not evidence that tests passed.

| ID | Scenario | Oracle / evidence | Task |
|---|---|---|---|
| Q1 | Windows/macOS workbook variants, sparse columns, formula caches, header aliases, malformed ZIP, missing headers | Exact normalized rows, distinct-document slicing and error list match report for parity cases; fatal import causes zero FI calls. | T02, T05 |
| Q2 | Duplicate same key, conflicting targets, ambiguous DOCLN suffix, stale preview | One change for identical duplicates; no guessed FI item; invalidate stale preparation. Document deliberate Fiori fail-closed additions separately from parity. | T02, T06 |
| Q3 | Forbidden company, denied nonblank area, all-blank, mixed blanks/duplicate permitted area, missing BSEG, unrelated denied line | Under actual restricted actor: no write on denial; blank does not bypass company. Capture area check count with a double and released locks in QA. | T04, T09 |
| Q4 | Two planned siblings plus independent next document; force second line failure | First document rolled back, both rows `SEND_ERROR`, independent document proceeds; verify DB after commit not just UI message. | T04, T06 |
| Q5 | Lost submit reply; double click; crash before/after FI boundary | One execution; unknown outcome requires reconciliation; known commit resumes only verification. Record executed changer call count. | T03, T06 |
| Q6 | Other user's run URL, child ID, list count and CSV; pagination/filter; CSV contains quotes/newline | No disclosure; full authorized result exports in original row order, UTF-8 bytes equal baseline. | T05, T08 |
| Q7 | Keyboard path, small viewport, cancel, reload, delayed read-back | Cancel unchanged; retained filters; queued is not success; verification pending has no rerun. | T07 |
| Q8 | Representative and over-limit files, concurrent workers, outage and purge | Record byte size, expanded size, rows/docs, elapsed prepare/execute, peak memory and lock conflicts. Approve site-specific limits and meet them. Purge expired payload only, preserve active evidence. | T09, T10 |

**Support routing.** Workbook errors → accountant corrects and reuploads. Authorization denial → FI security reviews actor/company/area; never advise bypassing the check. Lock conflict → inspect owner through normal SAP support procedures; no automatic force-unlock. Verification outage → Basis restores reads, worker resumes verification only. Unknown commit → FI controller reviews run/document evidence and records disposition.

**Operational handoff.** Monitor queue age, stalled claims, oldest pending verification, reconciliation count, document failures and purge errors; use run/document correlation IDs without logging file contents. Basis and FI set alert thresholds from QA measurements. Before enabling Live, confirm transport order, app catalog, negative authorization tests, retention and on-call ownership. Rollback means stop accepting new submissions, drain or reconcile active jobs and withdraw launchpad/worker activation; it never reverses already committed FI assignments.
