# T04 · Implement and verify the locked FI adapter

**Owner:** FI ABAP developer. **Depends on:** T01. **Contract:** [worker decisions](../design/execution.md). **Deliver:** callable document changer shared with or wrapping extracted report logic, injectable lock/BSEG/auth/change/transaction interfaces and ABAP Unit tests. Input is one company's document/year, mode, approved actor context and unique planned items; output is document outcome plus item diagnostics.

1. Require company `F_BKPF_BUK` activity `02` for Test/Live. Enqueue, read BSEG once and perform the complete target preflight before any write. Match BUZEI, skip only the GSBER check for an existing blank item, check `F_BKPF_GSB` activity `02` once per distinct nonblank targeted area. Reset cache per document. No matched entry → fail, never treat as blank.
2. Test releases lock without calling FI. Live rechecks confirmed values; use only `FI_DOCUMENT_CHANGE` for `ZUONR`, BEBAN before VENDOR, rollback on failure, commit-and-wait on success. Distinguish definite failure from uncertain commit. Always close the lock lifecycle appropriately.
3. Propagate first failing item/area diagnostic to all planned siblings, not previously skipped rows. Denial is not a warning. Keep post-commit verification independently callable for T06.

**Accept:** cover Q3/Q4 in [assurance](../design/assurance.md), including zero change calls when the *last* target is denied, zero area checks for all blanks, one check for a repeated permitted area, and no denial for an untargeted area. Provide call-order assertions and actual QA rollback/lock evidence before Live.
