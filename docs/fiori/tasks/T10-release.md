# T10 · Transport, operate and release the app

**Owner:** release developer with Basis, FI and security. **Depends on:** T09. **Runbook basis:** [verification and operations](../design/assurance.md).

**Deliver:** ordered transports and configuration manifest, least-privilege catalog/roles, launchpad target mapping, measured limits, retention/purge job, monitoring, recovery runbook and signed go/no-go checklist. Record actual object names and owners in the transport inventory.

1. Import storage/shared core and FI adapter before service/worker, then UI, catalog and roles. Apply client-specific service, logical-file and scheduling settings explicitly. Keep Live disabled until restricted-user and FI gates are signed.
2. Smoke-test launchpad navigation, scoped history, Plan and Test in the destination. Use the approved change procedure for any live pilot; no unattended test updates to production. Verify alert routing for stuck queues, verification backlog, reconciliation and purge errors.
3. Rehearse stopping new submissions while preserving pending/in-flight evidence. Drain/reconcile jobs, disable scheduling and withdraw tile/roles as needed. Never roll back deployment by silently reverting posted FI assignments. Purge must exclude active/uncertain runs and obey approved retention.

**Accept:** Basis and FI independently follow the runbook in QA, capture evidence of monitoring, restricted access, retention and safe shutdown, and sign handover. Record who can resolve an uncertain commit and who can enable Live. A transport import by itself is not acceptance.
