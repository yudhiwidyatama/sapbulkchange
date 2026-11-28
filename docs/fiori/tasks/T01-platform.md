# T01 · Establish the Assignment Runs implementation contract

**Executor:** implementation agent. **Depends on:** none. **Read:** [application contract](../../../FIORI_APP_SPEC.md), [business decisions](../design/analysis.md), [service and data](../design/service-data.md), [execution and recovery](../design/execution.md). This task has two distinct results. Record each separately in [SESSION](../SESSION.md).

## A. Design ready to implement (not evidence of an installed stack)

Produce the [handoff to T02–T10](../design/t01-handoff.md), concrete binding/operation map, persistence and dispatch decision, supported upload/review extension, proposed package and ordered transport list. Record target release/SP for S/4HANA, ABAP, Gateway and SAP_UI, actual browser UI5 version, binding, media support, job API, launchpad mapping and FI adapter constraints. Mark each candidate, verified or blocked; do not infer availability from report activation. Unknown approved upload/decompression limits, retention or display roles are not unlimited defaults. Browser input only; server paths disabled unless explicitly approved.

First useful milestone: a restricted accountant opens **Assignment Runs**, uploads a synthetic `.xlsx`, prepares a Plan, pages its rows and reopens it. Compare normalized keys, order, old/target and statuses with the callable report; explain approved differences. Confirm exact upload bytes by digest and length, CSRF on mutations, ownership/company scope on every read. Prepare and Plan Only make zero FI locks, changes, commits or background FI jobs. This is a staged milestone across T02/T03/T05/T07, not a demand to complete those tasks inside T01.

## B. Target proof (the same path T06 will use)

Implement a thin nonproduction slice: Assignment Runs Review → authenticated Submit → durable submission/outbox → selected scheduler adapter → worker → persisted outcome → same run details. Share the eventual Submit handler, dispatch adapter, worker bootstrap and correlation keys with T06; only substitute a harmless permission probe for the FI operation. No new end-user mode, permission override, or client-selected worker identity. Subsequent changes to service binding, dispatch mechanism or runtime identity invalidate affected evidence. Neither manual SM36 nor Schedule in Fiori Application Jobs is this route. Keep those probes as optional engineering diagnostics only.

**QA run card, after the slice exists:**

1. In an approved nonproduction client, pre-record restricted actor, independent allowed/denied company and area fixtures for change activity `02`, synthetic workbook digest, expected rows and scope. No actual FI change adapter may be enabled in the diagnostic build.
2. In Assignment Runs create a Plan Only run, upload the fixture, Prepare, compare all rows including a second page, submit Plan and reopen by run ID. Expect the reviewed version and counts, no dispatch, and zero FI calls. Try reading another user's run: no details, bytes or counts disclosed.
3. Create a separate QA probe run through the same review/Submit control with the no-write adapter selected **on the server**. Repeat the identical submission (also simulate losing its HTTP reply). Expect one durable execution for `(client,runId,version)`, the same execution ID in both responses and one worker claim. Editing before submission invalidates the old version. No scheduling or FI side effect on stale confirmation.
4. Observe the actual worker identity, SID/client, template/adapter and job reference against the independent fixture. Expect allowed company `0`, denied company `4`, allowed area `0`, denied area `4`. Reopen the same run in Assignment Runs and check those outcomes. Job owner, a saved username, a completed job or matching positive checks alone do not pass. Exercise a negative fixture; unexpected allow, missing evidence or identity mismatch blocks the gate. Never widen roles to pass.
5. Save only sanitized run/version/execution/job correlation, fixture digest, observed decisions, no-write evidence, software levels, date and witnessed disposition. Record lock/update-task/OB32 support separately; this probe does not qualify rollback, read-back or Live. T04/T09 own those tests. If any target component is missing, record NOT RUN or blocked, keep Test/Live disabled and continue offline.

**Acceptance:** A can unblock the named engineering work. T01 is Accepted only with B and the target binding smoke results. T09 qualification and T10 release authorization are separate. No human is asked to implement or debug the slice.
