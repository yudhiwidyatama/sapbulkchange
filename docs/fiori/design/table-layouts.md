# Assignment Runs: data model and table layouts

**Eight proposed physical tables.** The [service contract](service-data.md) names logical entities; they do not each need a table. [Screen behavior](experience.md) and [FI transaction and recovery rules](execution.md) are unchanged. This design does not create DDIC objects, set production limits, or authorize deployment.

## What was combined

| Previous records | New storage | Why this is safe / trade-off |
|---|---|---|
| FILE + BLOB | FILE with private, purgeable bytes | Metadata and bytes share one upload ID. Select metadata explicitly; clearing bytes must not delete digest or metadata. |
| ROW + MSG | ROW with an ordered diagnostic list | Preparation writes and reads the list with its row. No diagnostic-level index; keep row status as a separate filterable column. |
| SUB + QUEUE | SUB with dispatch columns | The accepted submission itself is the durable instruction to dispatch. No separate queue insert to lose. Plan Only is explicitly nondispatchable. |
| TARGET + RESULT | ITEM with separate reviewed and execution columns | One accepted submission per plan version permits at most one result for each reviewed item. Separate writers and guarded column updates preserve the immutable preview. A retry of verification does not create another item or FI attempt. |

Keep RUN separate from immutable PLAN versions, ROW separate from deduplicated ITEM, DOC separate for per-document transaction recovery, and EVENT separate for append-only history. Do not achieve a smaller count by putting searchable rows, permissions or checkpoints inside a run-sized JSON blob.

## Keys and types

All primary keys, unique constraints, indexes and relationships start with `MANDT:CLNT(3)` (implicit below). `R,F,T,X` = opaque run/file/item/execution IDs RAW(16); `V` = positive plan version INT4; `S` = original worksheet row INT4. `D` = company `BUKRS CHAR(4)`, document `BELNR CHAR(10)`, year `GJAHR NUMC(4)`; `I` = `BUZEI NUMC(3)`; `L` = ledger CHAR(2); `DOCLN` = ledger line NUMC(6); `A` = assignment CHAR(18). Use SAP-equivalent elements and preserve leading zeros. `U` = authenticated backend username; `TS` = UTC long timestamp; `N` = nonnegative INT4; `REV` = monotonically increasing INT8; `H` = SHA-256 RAW(32); `CODE` = controlled CHAR(32); `TEXT` = variable Unicode; `BIN` = exact bytes. `?` denotes logical absence, not a known blank or zero: use presence/state flags where needed in DDIC. Validate long-field representations and indexes on target; never truncate diagnostics.

```text
RUN ──< FILE                  a replacement upload is a new F
RUN ──< PLAN >── FILE         each version references its original file in R
PLAN ──< ROW >──0..1 ITEM     multiple eligible rows may link to one ITEM
PLAN ──0..1 SUB ──< DOC       dispatch and checkpoint data only for Test/Live
DOC ──< ITEM (at execution)   join via SUB's plan and exact D, never just BELNR
RUN ──< EVENT                 narrower scope optional
```

## Field dictionary

Fields listed in keys are required. The table name and key state exactly what one record represents. `R,V` always means a plan within this run and client. Only trusted backend components write these tables.

| Table / record | Key after MANDT | Other fields | Writer and constraints |
|---|---|---|---|
| `ZFA_RUN` / run | `R` | `owner:U, created:TS, updated:TS, revision:REV, state:CODE, draft_company:BUKRS, draft_ledger:L, draft_mode:CODE, draft_limit:N, draft_file:F?, current_version:V?`. Limit 0 means all. | Service creates; draft input edits only. Repository changes lifecycle/revision conditionally; revision supplies ETag. Editing Prepared clears current-plan pointer without deleting old versions. Allocate V under concurrency guard; never reuse. |
| `ZFA_FILE` / upload | `R,F` | `filename:TEXT, media_type:TEXT, byte_length:INT8, digest:H, uploaded_by:U, uploaded_at:TS, expires_at:TS?, purged_at:TS?, content:BIN?`. | Insert metadata and exact bytes together; compute digest/length server-side. Only retention process may clear content and set purged_at atomically. Immutable digest and nonnegative original length survive. No public media URL or content column in list projections. |
| `ZFA_PLAN` / successful Prepare | `R,V` | `file:F, file_digest:H, company:BUKRS, ledger:L, mode:CODE, doc_limit:N, prepared_by:U, prepared_at:TS, source_rows:N, eligible_items:N, eligible_docs:N`. | Insert PLAN, ROW and ITEM preview columns and publish current version in one transaction on matching run revision. Fatal preparation creates no partial plan; log run event. Never edit a published version. |
| `ZFA_ROW` / retained worksheet row | `R,V,S` | `input_doc,input_year,input_item,input_type,input_date,input_gl,input_source,input_target:TEXT?` (each optional, approved inputs only); `belnr:BELNR?, gjahr:GJAHR?, buzei:I?, source:CODE?, doc_type:CHAR(2)?, posting_date:DATS?, gl:CHAR(10)?, old:A?, target_value:A?, plan_status:CODE, target_id:T?, diagnostics:TEXT`. | Insert once. Diagnostics is a versioned serialization: `{v:1,entries:[{severity,reason,field?,expected?,actual?,message}]}` in display order; empty list allowed. Preserve blank vs absent and all mismatches. Only planned rows link to ITEM in the same version; an invalid row needs no FI key. |
| `ZFA_ITEM` / unique eligible FI item | `R,V,T` | **Immutable preview:** `D,I,docln:DOCLN,source:CODE,doc_type:CHAR(2),posting_date:DATS,gl:CHAR(10),old:A,target_value:A,clearing_doc:CHAR(10)?`. **Execution only:** `outcome:CODE?,read_state:CODE,observed:A?,observed_at:TS?,diagnostic:TEXT?`. | Unique `(MANDT,R,V,D,I)`; company matches PLAN; ledger from PLAN. At Prepare initialize `read_state=NOT_READ`, other execution fields absent. Only worker/verifier may change execution columns using exact SUB and DOC claim/revision; never replace the whole record. No execution updates for Plan Only. `READ_UNAVAILABLE`, `ITEM_MISSING`, `VALUE_READ` distinguish outage, completed missing read, and observed value. VALUE_READ requires value (possibly blank) and timestamp. |
| `ZFA_SUB` / one accepted submission and its dispatch intent | `R,V` | **Receipt:** `execution:X, token:TEXT, request_digest:H, actor:U, submitted_at:TS, mode:CODE, live_confirmed:CHAR(1), confirmed_at:TS?`. **Dispatch:** `dispatch_state:CODE, revision:REV, updated:TS, attempts:N, dispatch_claim:RAW(16)?, claimed_at:TS?, scheduler_ref:TEXT?, last_error:TEXT?`. | Unique `(MANDT,X)`. Insert receipt with `NOT_REQUIRED` for Plan Only or `PENDING` for Test/Live in the same transaction as the run transition. Only committed PENDING rows are eligible for initial dispatch. Authorized identical replay returns original X; conflicting request cannot create another. Digest covers run/version/token/mode/confirmation, not HTTP headers. Dispatcher conditionally updates only dispatch columns. A lost scheduler reply requires correlation, not blind retry. Never dispatch NOT_REQUIRED. |
| `ZFA_DOC` / execution document | `X,D` | `phase:CODE, revision:REV, attempt:N, claim:RAW(16)?, worker:U?, claimed_at:TS?, checkpoint_at:TS, outcome:CODE?, diagnostic:TEXT?`. | X resolves to SUB and exactly one R,V; D must have an ITEM there. Conditional claims fence competing workers. Record intent before entering FI and outcome afterward; no metadata commit inside FI. SAP document lock still applies across runs. Unknown commit goes to reconciliation, never automatic reapply. |
| `ZFA_EVENT` / audit or run diagnostic | `R,event_no:INT8` | `at:TS,actor:U,kind:CODE,from_state:CODE?,to_state:CODE?,version:V?,execution:X?,company:BUKRS?,belnr:BELNR?,gjahr:GJAHR?,correlation:RAW(16),reason:CODE?,detail:TEXT?`. | Append only; associate with transition in same business transaction where possible. Record authorized reconciliation disposition and evidence reference, not workbook contents or raw traces. |

## Read layouts (views, not tables)

| Screen / grain | Initial column order and sources | Behavior |
|---|---|---|
| Assignment Runs / RUN | Run ID (RUN.R), file (FILE.filename), company/ledger (current PLAN or draft), created by/at (RUN), mode (PLAN or draft), run state (RUN), scoped result counts. | Latest created first, R tie-breaker; filter company, mode, state, created date; default own runs. Narrow: keep run/file and textual state; other fields accessible in details. |
| Review / ROW | Worksheet row S, document/year/item, source, old, target, plan status, ordered diagnostics (ROW); eligible docs/items from PLAN in header. | Worksheet order; preserve S after sorting. Narrow: retain document/item, target and textual status. No edits to SAP facts. |
| Run details / ROW | Same row/key, source, old/target; verified assignment from ITEM execution columns; status/message from item or document outcome for linked rows, otherwise the plan status and diagnostics. | Left join ITEM, SUB and DOC to retain excluded rows. Page/filter by status with S as tie-breaker. Render known blank as “Blank”, no completed read as “Not verified”, missing item as “Item not found”. Narrow as Review. |

Row counts count ROW, eligible items count ITEM, eligible documents count distinct D in ITEM. Review always reads preview fields, even after execution. Final result views fan item/document outcomes out only to linked planned rows. Full authorized CSV uses one consistent snapshot, worksheet order, and `doc,year,item,source,old,target,status,message`, independent of filters or page. Export availability by state is a separate policy.

## Integrity, access paths and lifecycle

- Use repository checks for same-client/run/version links not enforceable in DDIC. Every list, child, count, byte read and CSV requires authorized RUN and company scope. Only server-derived identities may authorize. The workbook payload and raw inputs never enter a general list projection.
- Candidate indexes (all with MANDT first): RUN `(owner,draft_company,created,R)`, `(state,updated,R)`; ROW `(R,V,target_id,S)` plus its ordering PK; ITEM unique FI key above; SUB unique X and `(dispatch_state,updated,X)`; DOC `(phase,checkpoint_at,X)`; FILE `(expires_at,R,F)`. Check target query plans. Search/filter plan status from scalar columns, not by parsing diagnostics.
- Editing a draft or purging a payload never cascades to an older reviewed plan. Do not purge active, unverified or uncertain evidence. Approved client retention policy controls byte purge and eventual dependent record cleanup. No production durations or capacity limits implied.

## Acceptance walkthroughs (design examples, not SAP test results)

1. Rows 2 and 5, same validated key and target: two ROWs reference one ITEM; worker processes the item once under one DOC. Both rows show the same outcome and appear in export. Row 7 with invalid BUZEI has its own diagnostic list, no ITEM link and no invented FI key.
2. Replace file F1 with F2: V1 still references F1; Prepare publishes V2. A new V1 Submit is stale. An identical authorized replay of an already accepted V2 returns its original X and cannot insert a second dispatch instruction.
3. Plan Only creates a NOT_REQUIRED receipt, no DOC and no FI job. Test/Live creates one PENDING receipt; a failed submission transaction leaves neither an accepted receipt nor queued work.
4. Commit known, read unavailable: DOC retains checkpoint; ITEM read state changes but reviewed old/target do not. Retry only the read. Later VALUE_READ of blank differs from ITEM_MISSING. Unknown commit still requires reconciliation regardless of later equality.
5. After approved expiry, clear only FILE.content and record purged_at; filename, original length and digest remain available with the plan. Refuse purge of active or unresolved evidence.
