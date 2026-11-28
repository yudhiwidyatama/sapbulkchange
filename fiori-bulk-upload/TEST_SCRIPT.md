# Manual end-to-end test (after activation; use a test client / test company code)

Prepare: 3 test FI documents in company code `TST1` (ledger `0L`), one with a cleared line, and `.xlsx` files made from the downloaded template.

| # | Step | Expected |
|---|---|---|
| 1 | List Report > **Download Template** | `FI_Assignment_Upload_Template.xlsx`, 8 headers + 1 example row |
| 2 | Create: company code, ledger, attach a `.txt` renamed to `.xlsx` | Save blocked: message 001 (not a zip) |
| 3 | Create with a real `.xlsx` > 20 MB | Save blocked: message 005 |
| 4 | Create with a valid file | Batch `UPLOADED`, file size and hash filled; **Post** disabled |
| 5 | **Validate** with a user without `F_BKPF_BUK` ACTVT 02 | Action refused: message 006 |
| 6 | **Validate** (authorized) | `VALIDATING`, then `VALIDATED` after refresh; counts filled; log in SLG1 (`ZFI_BULK`/`UPLOAD`) |
| 7 | File with: wrong doc type, wrong date, wrong G/L, missing doc, missing line, duplicate row, bad date text, 51 chars in KODE PROJECT | Each row has the expected status and a readable message with field |
| 8 | In another session lock one document (FB02), Validate again | That row `LOCKED` with the user name; other rows `PLANNED` |
| 9 | Release the lock, Validate, **Post** | `POSTING` then `DONE`; rows `CHANGED`; `ZUONR` correct in FBL3N / `ACDOCA` |
| 10 | Post the same file in a new batch | Post refused: message 024 |
| 11 | Re-validate the finished batch | Changed rows now `SKIPPED_ALREADY_SET` |
| 12 | Lock a document during Post | That document `SEND_ERROR`, the others continue |
| 13 | Table of items > filter on error statuses > Export to Spreadsheet | File with row number, field, message |
| 14 | 50,000-row file | Validate and Post complete; record durations (spike item 7) |
