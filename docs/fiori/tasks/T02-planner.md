# T02 · Extract and characterize the workbook planner

**Owner:** ABAP domain developer. **Depends on:** T01. **Inputs:** [Z-program contract](../../../ABAP_ZPROGRAM_PLAN.md), `zfi_bulk_change_assign.abap`, `test_abap_xlsx_logic.py`. **Output:** shared byte-reader/parser, resolver, row DTOs, data-provider interface, fixtures and ABAP Unit tests; keep the existing report callable.

1. Characterize existing report results before refactoring. Separate binary input from GUI and extract deterministic OpenXML and key normalization routines. Preserve aliases, date forms, 10-character BELNR, 3-digit BUZEI and 18-character target maximum.
2. Bulk-load ACDOCA by company/ledger/doc/year and BSEG clearing facts by entry-view key. Return worksheet row, plan status, comparison values and all mismatch reasons. Preserve first-seen document order; limit documents, not rows.
3. At the Fiori planning boundary add conflict/ambiguity handling and identical-duplicate links. Keep these policy additions distinct from shared report behavior. Do not update FI or inspect GSBER from the workbook.

**Accept:** ABAP Unit covers sparse/rich/cached cells, missing headers, skipped whitespace doc, date serial `43496`, duplicate keys, 18/19-character boundary and A/B/A with limit `1`. Compare sanitized golden outputs before/after extraction; record intentional differences. Assert zero locks, changes and FI commits during Prepare.
