# T01 · Prove the target stack and worker identity

**Owner:** ABAP platform lead with Basis and FI security. **Depends on:** none. **Design:** [decisions](../design/analysis.md).

**Deliver:** a signed architecture decision record, minimal nonproduction service/job spike and release inventory (S/4HANA, ABAP, Gateway, UI5, chosen binding, upload and launchpad deployment options). Reserve package, namespace and transport ownership.

1. In the actual target release, upload harmless binary bytes and read them back server-side without a GUI; expose a paged entity and bound action. Record extension and CSRF mechanisms available.
2. Schedule a harmless job from a restricted user. Record effective identity and prove an allowed and a denied company/area outcome without updating FI. A name stored on the run is not proof of effective authorization.
3. Confirm local FI adapter support, SAP lock/commit behavior and approved read scope with FI/Basis. Record browser vs logical-file policy, job scheduler, storage and unresolved gates.

**Accept:** independent reviewer repeats the smoke test in QA; identity, service binding and failure behavior are documented. If authority cannot be preserved, approve Plan Only at most and explicitly block Test/Live. Do not work around the gate with broader batch permissions.
