# T03 · Implement run persistence and concurrency guards

**Owner:** ABAP persistence developer. **Depends on:** T01. **Contract:** [entities and states](../design/service-data.md).

**Deliver:** client-dependent tables/objects, keys and indexes, repository interface, versioned plan store, durable outbox/claim and audit transitions. Keep raw workbook in private storage and separate planned rows from unique execution items.

1. Enforce one submission for `(client,runId,version)` and one document attempt owner. Store immutable confirmed scope plus input digest, version, actor and timestamp. Use ETags for edits and transactional compare-and-set for claims.
2. Persist all prepared rows and counts together. A revised Prepared run loses its prior authorization to submit. Queue record and accepted submission must commit together; do not call FI in this transaction.
3. Implement scoped list/pagination and checkpoint reads, retention eligibility and reference cleanup. Active or uncertain work cannot be purged.

**Accept:** integration tests race two submitters and two workers, inject an outbox write failure, edit using a stale ETag and attempt cross-client access. Prove one claim, no queued-without-work state, no partial plan visibility, and no purge of active or reconciliation evidence. Attach schema and transaction test output.
