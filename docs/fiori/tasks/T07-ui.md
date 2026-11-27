# T07 · Build Assignment Runs, review and results

**Executor:** implementation agent. **Depends on:** T05; use contract fixtures until T06 is ready. **Read:** [experience](../design/experience.md). **Produce:** manifest, annotations, List Report/Object Page, supported upload/review extension, i18n, intent definition and UI tests.

1. Bind filters, value help, required parameters and `1000`, `0L`, `0`, Plan defaults. Upload one workbook; Prepare obtains counts, warnings and version from server. Do not compute authority or authoritative eligibility in JavaScript.
2. Implement mode availability, cancellation, focus and explicit live confirmation scoped to stored plan. Require fresh review on conflict. Recover state on lost reply, not a second execution.
3. Bind persistent item details, sibling diagnostics, queued and verification-pending states. Integrate T08 full-run export. Support keyboard use and narrow layouts.

**Accept:** automate New → Review → Cancel → Apply → Reopen against fixtures; zero writes on cancel and one execution on double click. Include empty, missing-header, denied-area, no-eligible-item and reconciliation states. **Human QA:** supply exact keyboard path and expected macOS/Windows observations; request only browser checks not otherwise verified. Record environment and evidence in [session state](../SESSION.md).
