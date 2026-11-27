# Worker, security and recovery design

**Trust boundary.** The browser owns presentation. The service owns input, ownership checks and confirmation. The worker owns each FI logical unit of work. Do not call a committing FI adapter inside an HTTP change set or RAP save sequence. Do not substitute a privileged technical user's authority for the initiating user's current effective authority. If the target platform cannot prove that identity at execution time, disable Test and Live.

1. Claim the durable execution. Check company `F_BKPF_BUK`, `BUKRS = run.company`, `ACTVT = '02'` for Test/Live. Plan never uses a change authority result as a read entitlement.
2. Group only planned, deduplicated targets by company/document/year. Acquire `ENQUEUE_EFBKPF`. On conflict return `SEND_ERROR` for planned rows of that document and continue. Never wait for browser input while locked.
3. While locked, read entry-view `BSEG` once by `BUKRS/BELNR/GJAHR`, match **each target** by `BUZEI`. Missing row → `No BSEG item {item}; business area cannot be verified`. Existing row, initial `GSBER` → skip only the area check; keep target. For each distinct nonblank area in this document require `F_BKPF_GSB`, `GSBER = BSEG-GSBER`, `ACTVT = '02'`. Denied → `No authorization (F_BKPF_GSB ACTVT 02) for business area {area}`. Ignore untargeted areas. Cache nothing across documents. First failure: unlock, no FI change or commit, `SEND_ERROR` on all planned siblings. Other documents proceed.
4. Test: unlock and return `TESTRUN_OK`. Live: recheck the reviewed key, validations, old assignment and clearing state. Stale input rejects the whole pending group. Process BEBAN before VENDOR; call `FI_DOCUMENT_CHANGE` only for `ZUONR`. On any line failure roll back the document, unlock and persist its diagnostic for all planned siblings. On success use `BAPI_TRANSACTION_COMMIT` with `WAIT='X'`, check outcome and release lock. No direct writes to FI tables.
5. Independently re-read ACDOCA in selected ledger `BYPASSING BUFFER`. Known commit plus matching target → `CHANGED`; completed read with mismatch/missing item → `NOT_CHANGED`. Read unavailable is not a mismatch. Preserve diagnostic and retry read only. The local authorization contract does not cover document type, customer, vendor, account type, G/L account or segment authorization.

### Durable checkpoints

| Last durable evidence after interruption | Safe next action | Prohibited shortcut |
|---|---|---|
| Queued, never claimed | One worker may claim by compare-and-set. | Dispatching a second execution for the same version. |
| Claimed; no entry into FI attempt proved | Recover the claim only after proving prior worker inactive and pre-FI boundary intact. | Using an elapsed timeout alone as proof. |
| About to enter FI attempt; completion not journaled | Mark Reconciliation required. Independent reads and FI change evidence may assist support, but outcome remains uncertain until reviewed. | Reapply, or claim this job caused a matching value. |
| Commit known, verification outstanding | Resume ledger read-back only; record observed value and time. | Calling changer again. |
| Final outcomes recorded | Rebuild counters from persisted rows; release claim. | Rewriting FI to reproduce a result. |

Persist an intent checkpoint **before** entering the FI LUW; keep an uncertainty window rather than pretending FI and job storage commit atomically. No checkpoint commits between acquiring the FI lock and finishing its LUW. Once outcome is known, persist after FI completion. FI support and operator review produce an auditable disposition, never an implicit retry; any later change starts with a new plan and confirmation.
