# T01 · Prove the target stack and effective user

**Executor:** implementation agent. **Depends on:** none. **Read:** [decisions](../design/analysis.md), [session workflow](../../../FIORI_DESIGN.md).

**Produce:** a decision record, minimal harmless service/job spike, repeatable QA script and release inventory: S/4HANA, ABAP, Gateway, UI5, binding, media upload, scheduling and launchpad deployment. Propose package/namespace and transport layout. Mark unknown installed capabilities unverified.

1. Inspect available tools and repo first. Implement a harmless bytes-in/bytes-out upload, paged query and action against the proposed binding; document CSRF and supported extensions. If the stack is unavailable, supply the spike and exact target QA steps rather than claiming success.
2. Prepare a nonproduction job initiated by a restricted user. Record the effective identity and allowed/denied company and area decisions without updating FI. A username saved on the run is not proof of effective authorization.
3. Record local FI adapter support, lock/update-task assumptions, storage, scheduler, browser/server-file policy and blockers. Supply an alternative if the preferred binding is unsupported; do not broaden privilege.

**Human boundary:** QA runs/witnesses target smoke and identity tests. Ask for guidance only on environment or policy choices that cannot be inferred. No human is asked to implement the spike. **Accept:** repeatable target smoke and identity evidence linked in [checkpoint](../SESSION.md); absent that proof, no Test/Live enablement. Continue offline parity work where safe.
