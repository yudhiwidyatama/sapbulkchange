# T10 · Prepare transports, operations and cutover

**Executor:** implementation agent prepares artifacts and fixes. **Human role:** nonproduction rehearsal/QA and explicit go/no-go guidance. **Depends on:** T09. **Read:** [operations](../design/assurance.md). This task does not authorize an agent to deploy to production, grant roles or change posted assignments.

1. Produce ordered transport/configuration manifest: storage/shared core and FI adapter, service/worker, UI, catalog and least-privilege roles. Identify client-specific settings, actual object names, owner-of-record fields required by the environment and rollback dependencies. Leave Live disabled until restricted QA passes.
2. Deliver a destination QA script for launchpad navigation, scoped history, Plan and Test, measured limits, retention/purge and alerts for stuck queues, verification backlog and reconciliation. Provide sanitized expected evidence. Any live pilot requires separate authorization under the site's change process.
3. Prepare shutdown rehearsal: stop new submissions, drain/reconcile jobs, preserve in-flight evidence, disable scheduler/entry point as applicable. Never silently revert committed FI assignments. Purge excludes active and uncertain runs.

**Accept:** attach QA rehearsal observations, monitoring and safe-stop results, approved limits and explicit human guidance on release scope, reconciliation authority and Live enablement. Record artifact readiness separately from actual deployment in [session state](../SESSION.md). If a gate is absent, mark release blocked and leave the safe configuration in place.
