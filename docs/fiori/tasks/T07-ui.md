# T07 · Build Assignment Runs, review and result pages

**Owner:** SAPUI5/Fiori elements developer. **Depends on:** T05; mock Submit until T06. **Contract:** [page and interaction design](../design/experience.md).

**Deliver:** app manifest, annotations, List Report/Object Page, supported upload/review extension, i18n texts, launchpad intent definition and UI tests. Fixture-driven mock service must implement the same fields and error shape as the actual binding.

1. Bind list filters, value helps and required parameters; show `1000`, `0L`, `0` and Plan defaults. Upload one workbook; Prepare obtains counts, warnings and version from server. Don't calculate authorization or target eligibility in JavaScript.
2. Add mode-specific action availability, cancellation, focus management and live confirmation scoped to stored plan. Handle stale/conflict by refreshing and requiring review; on lost response recover run state rather than generating a new execution.
3. Bind item detail and status text to persistent outcomes, show the group diagnostic and pending verification distinctly, expose authorized full-run download (T08). Support keyboard-only operation and narrow layout.

**Accept:** UI automation walks new → review → cancel → apply → reopen; zero writes on cancel and one execution on double click. Include empty-state, missing-header, denied-area, no-eligible-item and reconciliation examples. Demonstrate with keyboard and both macOS/Windows browsers.
