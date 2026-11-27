# T08 · Export parity CSV and protect result history

**Owner:** ABAP service developer with UI integration. **Depends on:** T03, T05. **Integrates with:** T07. **Contract:** [service and data](../design/service-data.md).

**Deliver:** full-run CSV action/stream, golden-byte tests, scoped history access, audit and export retention policy hooks. Reuse report serializer where possible.

1. Read persisted results in worksheet order from one consistent snapshot, independent of filters or UI pagination. Export `doc,year,item,source,old,target,status,message` in UTF-8 RFC-4180; preserve zero padding, quotes, delimiters and embedded newlines. Do not expand parity CSV with audit columns.
2. Recheck owner/delegation and company display authority for every download, including direct resource access. Never expose a public file URL. Document safe spreadsheet import as text; any sanitized spreadsheet-specific export must be explicitly separate from parity CSV.
3. Show export only when the persisted result snapshot is available. If operationally limited to finalized results, report that state explicitly rather than returning an incomplete CSV as final.

**Accept:** compare bytes with report output for synthetic messages containing commas, CR/LF and quotes; second-page filtered display still exports every row once. Forbidden actor and expired payload have no data leakage. Attach byte comparison and negative authorization results.
