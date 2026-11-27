# T09 · Qualify end-to-end behavior in a nonproduction client

**Owner:** test automation developer with FI/security testers. **Depends on:** T06, T07, T08. **Test charter:** [Q1–Q8 matrix](../design/assurance.md).

**Deliver:** versioned synthetic workbook fixtures, expected row/CSV files, ABAP Unit and service/UI test reports, restricted-user integration evidence and load/limits report. Never commit production workbooks, roles with credentials or personal data.

1. Run report-vs-app Plan on identical fixtures. Separate intentional duplicate/ambiguity safeguards from regressions; reconcile worksheet rows, unique items and per-document counts.
2. Execute both Test and Live in controlled FI QA with allowed/denied company and area profiles, real blank GSBER, missing-item double, lock conflict, failing second line, and positive/negative read-back. Record FI before/after and lock release, not just screenshots. PR #3 syntax activation alone does not satisfy this gate.
3. Inject duplicate submit and worker failures from T06. Verify safe recovery, CSV byte parity, keyboard path, full-run export access, and performance at approved representative and over-limit sizes. Record client/software level, test identity role, timestamp, fixture digest and correlation ID.

**Accept:** map each Q ID to repeatable evidence or an explicit blocking defect; FI and security owners sign restricted-user behavior. Do not label unexecuted QA cases as passed. Hand approved numeric limits and open risks to T10.
