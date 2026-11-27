# T06 · Implement submission, execution and reconciliation

**Owner:** background ABAP developer. **Depends on:** T03, T04, T05. **Contract:** [execution and recovery](../design/execution.md).

**Deliver:** guarded Submit action, outbox dispatcher, job class, per-document checkpoint handler, verification-only retry and support reconciliation view/procedure.

1. Verify ownership, current plan and confirmed mode; block Live with no eligible items or no confirmation. Atomic accept/claim; identical replay returns existing execution. Finish Plan without scheduling FI work.
2. Run as the initiating user's effective identity. Before entering FI persist intent. Dispatch once per eligible document; never commit job metadata inside its FI LUW. Continue after known document failure. Persist known outcome; perform independent ACDOCA read-back and fan out statuses to linked source rows.
3. Route unknown commit to reconciliation; resume known committed work only by reading. Never convert an expired worker lease into permission to reapply a change. Preserve diagnostics and tie counters to persisted results.

**Accept:** concurrent submit, crash before dispatch, crash after commit before recording confirmation, transient verification outage and lost HTTP response. Show call counts and checkpoints: no duplicate FI update, no premature `CHANGED`, and independent documents can complete. Exercise negative identity/authority at execution time, not just at Submit.
