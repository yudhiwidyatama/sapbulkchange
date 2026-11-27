# T06 · Implement submission, execution and reconciliation

**Executor:** implementation agent. **Depends on:** T03, T04, T05. **Read:** [execution and recovery](../design/execution.md). **Produce:** guarded Submit, durable dispatch, job class, per-document checkpoints, verification-only retry and support reconciliation procedure.

1. Verify ownership, current plan and stored mode. No Live without eligible items and explicit confirmation. Atomically claim submission; identical replay returns existing execution. Finish Plan without FI dispatch.
2. Run under the initiator's current effective authority. Persist intent before entering FI; never commit job metadata inside its LUW. Dispatch once per eligible document; continue after known document failure. Persist known outcome, read back ACDOCA independently and fan statuses out to linked rows.
3. Unknown commit goes to reconciliation; resume known committed work only by reading. An expired lease is not permission to reapply a change. Counters reflect persisted results.

**Accept:** inject concurrent submits, crash before dispatch, crash after commit before confirmation is recorded, verification outage and lost HTTP response. Show no duplicate FI update, premature `CHANGED` or cross-document rollback. Prove effective permission at execution, not just at Submit. **Handoff:** link fault-injection tests/checkpoints in [session state](../SESSION.md); humans verify restricted target behavior in QA, not by providing a privileged service account.
