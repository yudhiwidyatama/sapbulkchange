# T02 · Extract and characterize the workbook planner

**Executor:** implementation agent. **Depends on:** T01 interfaces; characterization can begin offline. **Read:** [report contract](../../../ABAP_ZPROGRAM_PLAN.md), `zfi_bulk_change_assign.abap`, `test_abap_xlsx_logic.py`.

**Produce:** shared binary reader/parser, resolver, row DTOs, data-provider interface, synthetic fixtures and ABAP Unit tests; preserve the callable report. Inspect the existing test entry point before choosing commands.

1. Capture current expected results before refactoring. Separate GUI input from deterministic OpenXML and key normalization. Preserve aliases, supported dates, 10-character BELNR, 3-digit BUZEI and 18-character assignment maximum.
2. Bulk-load ACDOCA by company/ledger/doc/year and BSEG clearing facts by entry-view key. Preserve worksheet row, old/target, all comparison reasons and first-seen document order; limit documents, not rows.
3. Isolate Fiori duplicate/conflict/ambiguity policy from shared report behavior. Do not use workbook GSBER for authority. Do not lock or change FI in Prepare.

**Accept:** exercise sparse/rich/cached cells, missing headers, blank doc, serial `43496`, duplicate keys, 18/19-character boundary and A/B/A with limit `1`. Compare sanitized golden outputs before/after and explain intentional differences. Assert zero FI changes, commits and locks. **Handoff:** record fixture paths, exact commands and observed results in [session state](../SESSION.md); queue QA only for parity cases that require SAP.
