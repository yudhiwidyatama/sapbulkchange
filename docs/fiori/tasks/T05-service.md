# T05 · Expose secured upload, Prepare and read operations

**Owner:** ABAP service developer. **Depends on:** T02, T03. **Contract:** [service and data](../design/service-data.md).

**Deliver:** service definition/binding, metadata, read projections, stream handler, value help, action handlers, message mapping and service contract tests. Publish sanitized example requests/responses for the UI team. Submit execution is T06.

1. Derive owner from authentication. Enforce approved company display scope plus owner/delegation on list, counts, single-key, navigation and stream access. Client-supplied user or GSBER cannot grant access. Apply CSRF and input limits to mutations.
2. Accept exact `.xlsx` bytes, verify actual format and compressed/expanded limits, reject encrypted/unsupported content. Permit a server-side source only under approved logical names. Store digest and byte length; never expose physical paths.
3. Prepare the version via shared planner. Reject stale ETag; publish status, row and document counts plus complete field-specific diagnostics. Use deterministic paging and sorting. No FI side effects.

**Accept:** service tests for invalid ZIP, missing headers, stale plan, cross-user keys/counts and valid upload. Query a second page without losing rows; compare total counts to the stored plan. Provide metadata and test transcript, without raw company data.
