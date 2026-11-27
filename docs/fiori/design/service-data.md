# Service and persistence contract

Proposed logical names, not claims about installed service bindings. T01 selects the concrete transport mapping. UTC timestamps; key fields serialized as strings to preserve leading zeroes. CSV is a separate compatibility interface.

| Entity (key) | Required data and constraints |
|---|---|
| Run (`client, runId`) | Owner, creation/update timestamps, company, ledger, mode, limit, state, plan version, ETag, file reference, count snapshot. Only Draft inputs are mutable. A revision of Prepared returns to Draft and invalidates confirmation. Queued and later are immutable. Index owner/company/date and queue state. |
| Workbook (`client, fileId`) | Private bytes or approved private storage handle, filename, media type, exact bytes, digest, expiry. Not listable as a public attachment. |
| Plan row (`client, runId, version, sheetRow`) | Raw validation inputs as policy permits, normalized key, source, expected old and target, warning/mismatch list, status, observed value; link duplicates to one execution item. Stable export order by sheetRow. |
| Execution document (`client, runId, version, BUKRS, BELNR, GJAHR`) | Attempt/claim, worker identity, phase, last checkpoint, outcome, diagnostic. Unique per submitted version and document. Compare-and-set claims, never two active workers. |
| Execution item (document key + `BUZEI`) | Source row references, `DOCLN`/ledger used for read-back, old, target, observed and result. Separate FI target uniqueness from worksheet row identity. |
| Submission/audit | Unique `(client, runId, version)` submission; request token, mode, confirmer/time, immutable digest, execution ID; append-only state transitions with actor, timestamp, reason and correlation ID. |

### Operations (illustrative resource names)

| Request | Server behavior | Result / conflict |
|---|---|---|
| CreateRun(company,ledger,limit,mode) → attach binary | Check read scope; server assigns owner and ID. Stream binary, enforce configured size/decompression limits, parse no macros or external resources. Server-file source, if enabled, goes through the same checks. | Draft + ETag. Unsupported source → localized input error; no FI action. |
| Prepare(run,If-Match) | Resolve exact file/version; bulk-plan rows, persist all rows and counts together. No lock or FI update. | Prepared + planVersion/ETag. Fatal format/header error → Failed with actionable diagnostics; corrected file can start a new draft. |
| Submit(run,version,token,confirmedLive,If-Match) | Authorize caller; validate scope and mode from stored plan. Plan Only finalizes results without FI dispatch. Test/Live atomically claim submission and enqueue durable work. Live needs explicit confirmation and eligible items. | Return stable run/execution reference. Recognized identical replay returns original result before rejecting stale ETag; altered mode/version/token payload cannot start a second worker. |
| ReadRuns / ReadRun / ReadItems / ResultsCSV | Apply owner/delegate AND company scope to list, keys, children, counts and downloads. Page results; deterministic sort with row/key tie-breaker. | Fresh counts and persisted statuses. Export covers full authorized run, not the current page. |

Example logical submit body: `{"planVersion":3,"token":"<unique-request-id>","confirmedLive":true}`. Company, user, areas, old values, target count and eligible items are **not** accepted from this request. Return validation errors with code, severity, field or sheet row and human-readable text. Use binding-appropriate equivalents of 400 (bad input), 403 (action forbidden), 404 (unavailable resource without disclosing ownership), 409 (state conflict), 412 (stale ETag) and 413 (size limit). `SEND_ERROR` is a persisted FI row result, not an HTTP error for a successfully retrieved run.

**State rules.** Draft → Prepared → Completed/Completed with issues for Plan; Draft → Prepared → Queued → Running for Test/Live. From Running: Completed, Completed with issues, Failed or Reconciliation required. A known commit awaiting read-back remains nonfinal. A missing company permission is run-fatal; a single document area denial is not. Keep counts derived from one persisted snapshot; do not mark the run complete while a document is unresolved. Retention must not purge active/reconciliation evidence; after expiry no orphan file or download handle remains.
