# T08 · Export parity CSV and protect result history

**Executor:** implementation agent. **Depends on:** T03, T05; integrate into T07. **Read:** [service and data](../design/service-data.md). **Produce:** full-run CSV stream, golden-byte tests, history scope checks, audit and retention hooks.

1. Read one consistent snapshot in worksheet order irrespective of UI filters or pagination. Export `doc,year,item,source,old,target,status,message` in UTF-8 RFC-4180; preserve zero padding, quotes, delimiters and embedded newlines. Reuse report serializer where possible. No additional audit columns.
2. Recheck owner/delegation and company display authority for each request. No public file URL. Document safe spreadsheet import as text; keep any alternate sanitized output explicitly separate from parity CSV.
3. Indicate when a result snapshot is available. If finalized-only, state that explicitly rather than returning an incomplete CSV as final.

**Accept:** compare bytes with report output including commas, CR/LF and quotes; second-page filtered display exports every authorized row once. Confirm forbidden actor/expired payload cannot disclose data. **Handoff:** link byte diff, fixture and access tests in [session state](../SESSION.md); use only synthetic data.
