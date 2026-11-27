# T05 · Expose secured upload, Prepare and read operations

**Executor:** implementation agent. **Depends on:** T02, T03. **Read:** [service and data](../design/service-data.md). **Produce:** service definition/binding, metadata, projections, stream and Prepare handlers, value help, message mapping, tests and sanitized requests/responses usable by T07. Submit execution belongs to T06.

1. Derive owner from authentication. Enforce approved company display scope plus owner/delegation on list, counts, keys, children and streams. Client-supplied user/GSBER cannot grant access. Apply CSRF and configured input limits.
2. Accept exact XLSX bytes, verify format and compressed/expanded limits, reject encrypted/unsupported content. Permit a server-side source only under approved logical names. Store digest and exact length, never expose physical paths.
3. Prepare one immutable version with shared planner, enforce ETags and publish row/document counts and all diagnostics. Page/sort deterministically. No FI side effects.

**Accept:** exercise invalid ZIP, missing headers, stale plan, cross-user keys/counts and valid upload. Query a second page without lost rows; compare total with persistence. **Handoff:** publish contract examples and test transcript, link from [session state](../SESSION.md). Ask for guidance only if display/delegation policy is unresolved; deny by default.
