# T03 · Implement run persistence and concurrency guards

**Executor:** implementation agent. **Depends on:** T01 target persistence choice for integration. **Read:** [entities and states](../design/service-data.md).

**Produce:** client-dependent storage objects, keys/indexes, repository interface, versioned plan store, durable outbox, claim logic and audit transitions. Keep workbook bytes private and distinguish source rows from unique execution items.

1. Enforce one submission per `(client,runId,version)` and one active document owner. Store immutable confirmed scope, digest, version, actor and timestamp. Use ETags for edits and transactional compare-and-set for claims.
2. Persist prepared rows and counts together. Editing Prepared invalidates confirmation. Queue and submission must commit together, with no FI call in that transaction.
3. Implement scoped list/pagination, checkpoint reads, retention eligibility and reference cleanup. Active or uncertain work cannot be purged.

**Accept:** race two submitters and workers; inject outbox failure; edit with a stale ETag; attempt cross-client access. Prove a single claim, no partial plan or orphan submission, and no purge of active/reconciliation evidence. **Handoff:** link schema, repeatable concurrency test and environment in [session state](../SESSION.md); do not present an in-memory double as target database proof.
