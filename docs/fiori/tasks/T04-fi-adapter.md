# T04 · Implement the locked FI adapter

**Executor:** implementation agent. **Depends on:** T01 identity contract. **Read:** [worker decisions](../design/execution.md). **Produce:** shared or extracted document changer, injectable lock/BSEG/auth/change/transaction interfaces, independently callable verification and ABAP Unit tests.

1. Require company `F_BKPF_BUK`, `ACTVT='02'` for Test/Live. Enqueue, read BSEG once for the locked document and match each target by BUZEI before any FI write. Missing row fails; existing blank GSBER skips only the area check. Require `F_BKPF_GSB`, `ACTVT='02'` once per distinct nonblank targeted area per document. Ignore untargeted areas.
2. Test unlocks without FI change. Live rechecks confirmed values; use only `FI_DOCUMENT_CHANGE` for `ZUONR`, BEBAN before VENDOR, rollback on failure, commit-and-wait on success. Distinguish definite failure from uncertain commit. Always close lock lifecycle appropriately.
3. Propagate first failed target diagnostic to every planned sibling; keep previously skipped rows unchanged and continue to other documents. Denial is not an overridable warning.

**Accept:** automate Q3/Q4 in [assurance](../design/assurance.md): last target denied → zero change calls; all blank → zero area checks; repeated permitted area → one check; untargeted denied area does not block. Assert lock/check/write order. **Human QA:** provide a restricted-user QA procedure and controlled rollback/lock evidence request. Do not self-authorize FI changes or mark target cases passed from doubles. Record results in [session state](../SESSION.md).
