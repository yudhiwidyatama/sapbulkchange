# VS Code agent runbook: put Astra2 into an S/4HANA 2022 DEV transport

**Goal:** Record the delivered UI5 application and ABAP staging objects in an **open, modifiable Workbench request** in DEV. Leave the request and its developer task **unreleased**. A Git commit is the source snapshot; it is not an SAP transport. Recording the files in CTS is not the same as publishing an OData service or enabling FI writes.

## 1. Operator: give the VS Code agent this instruction

Open the `sapbulkchange` workspace on branch `fiori-astra2`, select Agent mode, and enable the approved ADT MCP server's tools. In the Command Palette, **MCP: List Servers** lets you inspect/start the configured server. Authenticate through its normal secure prompt, not through chat. The exact ADT MCP extension, tool names and supported object types depend on your installation; do not assume Eclipse commands are MCP tools. [VS Code: MCP server management](https://code.visualstudio.com/docs/agents/run/manage-mcp-servers)

> Follow `fiori-astra2/docs/dev/VS_CODE_ADT_MCP_TRANSPORT.md`. Start read-only. Source: branch `fiori-astra2`, commit `<approved SHA>`. Target: S/4HANA 2022 **DEV** connection `<VS Code connection>`, SID `<SID>`, client `<client>`. Backend package `<transportable package>`, UI package `<package>`, UI5 repository `<approved Z/Y name>`, parent Workbench request `<request>`, my modifiable task `<task>`. Gateway topology `<embedded or hub>`. Show the object list, differences and proposed transport assignment, then wait for my confirmation before writing. Leave all requests open. Do not enable Apply, publish to QAS/PRD, or release anything.

If an input is unknown, ask the operator or Basis. Do not infer the SID/client from old screenshots, choose the first request offered, or use `$TMP`. Do not put credentials, tokens, internal connection profiles or real FI data into Git or the handoff.

## 2. Agent: preflight and confirmation (no writes)

1. Verify the checked-out branch, exact commit and clean deployable sources (`git status --short --branch`, `git rev-parse HEAD`). Stop on unexpected local changes. Read the [delivery status](../../README.md), [design](../../../FIORI_APP_SPEC.md) and [authorization contract](../../../FIORI_AUTHORIZATION.md).
2. Discover the installed MCP tools and inspect their input schemas. Map capabilities for system identity, package/object lookup, transport/task lookup, lock, create/update, source includes, activate, ABAP Unit and read-back. Separately look for a **UI5 ABAP repository upload** capability. A generic ABAP source update cannot deploy a UI5 app. Record missing capabilities and use the explicit human handoffs below; never invent a tool call or bypass a server permission.
3. Read back the connected SID, client and current ABAP user. Verify DEV, package transport layer and correct target route, parent request type/status, and an open task for this user. If a request is missing, ask the operator to create a **Workbench request** and assigned developer task in DEV Transport Organizer (`SE09`/`SE10`), or obtain explicit permission to create them with an available tool. Re-read the returned IDs. Use the parent or task according to the particular tool's documented field, and verify the resulting task afterwards.
4. Determine where the UI5 repository lives. **Embedded:** backend and UI may share the same request if in the same DEV system and route. **Separate front-end hub:** stop and obtain the front-end DEV connection, package and its own request/task. Do not reuse a backend request number on a different SAP system. Check the installed SAPUI5 against the application manifest before claiming it can run.
5. Search each target object and UI repository name. If an existing version is identical, skip rewriting and report whether it is already recorded. If different, show a diff and preserve a recoverable baseline. Stop on foreign locks, another request, namespace/package mismatch, or unrelated existing BSP content. **Ask for approval of the exact change list and destination before the first write.**

## 3. Record the backend objects with ADT MCP

Work from `fiori-astra2/backend/`. Use the same approved package and transport for each operation. For existing objects, lock and update through the advertised ADT operation; release only your own **object edit lock**, not the CTS task. Re-read activation results after each step.

| Order | Create/update in DEV | Repository source and handling |
|---|---|---|
| 1 | Database table `ZFI_ASTRA_RUN` | `adt/zfi_astra_run.ddls` contains **define table** source. Create as an ABAP database table, not a CDS view or generic text file. Activate. Never expose the private staging table as a public service. |
| 2 | Global class `ZCL_FI_UPLOAD_GUARD` | Main source `zcl_fi_upload_guard.clas.abap`; put `zcl_fi_upload_guard.clas.testclasses.abap` in the same class's **local test classes** include. Use `.clas.xml` only as serialization metadata. Activate and run its ABAP Unit tests. |
| 3 | Global class `ZCL_FI_RUN_STORE` | Main source `zcl_fi_run_store.clas.abap`; `.clas.xml` is metadata, not ABAP code. Activate after the table and guard. Verify dependencies resolve on the actual 2022 stack. |

If the MCP cannot create a table, write a test include, assign CTS, or activate, hand that **specific operation** to an authorized ABAP developer in ADT. Resume only after read-back. Do not import the whole repository: the classic report, RFC wrapper, Avalonia app, test server, logs and sample workbooks are outside this transport. Stop if activating an existing table would require a destructive database adjustment.

## 4. Record the UI5 app in the DEV front-end repository

**Payload:** the **contents** of `fiori-astra2/webapp/`, with `manifest.json` and `Component.js` at the deployed app root (not under an extra `webapp/` folder). Include `index.html`, `start.js`, `controller/`, `view/`, `model/` and `i18n/`. Preserve component ID `astra.fi.assign` and its same-origin service URI. Do not upload `test/`, Python, `metadata.xml`, backend code, docs, CI, sample business data or credentials. Verify the produced archive/file list before deployment.

Choose **one** supported route:

- **A — ADT MCP with explicit UI5 deployment support:** supply the approved DEV front-end connection/client, UI repository name, UI package, transport, and payload. Review the proposed file changes, particularly deletions. Deploy only after confirming the target. If transport assignment cannot be specified or verified, stop; use B or C.
- **B — VS Code SAP Fiori tools:** use a reviewed UI5 project wrapper around the existing `webapp/`. The inspected branch does **not** ship `package.json`, `ui5.yaml` or `ui5-deploy.yaml` in `fiori-astra2/`; do not assume `npm run deploy` already exists. If scaffolding is needed, prepare/review it separately without regenerating the app. In the Command Palette select **Fiori: Add Deployment Configuration** → **ABAP** → saved DEV system and client → UI5 repository, description and UI package → **Choose from existing / Enter manually** for the approved transport. Review generated `ui5-deploy.yaml`, build/deploy scripts and output. Run the generated `npm run deploy` only after confirming the upload summary. SAP lists `SAP_UI` **7.53 or higher**, an accessible SAPUI5 repository deployment service and appropriate `S_DEVELOP` authorization for this tooling. Fix certificate trust through Basis; never disable TLS verification. [SAP Fiori tools: Generate Deployment Configuration ABAP](https://github.com/SAP-docs/btp-fiori-tools/blob/main/docs/Deploying-an-Application/generate-deployment-configuration-abap-c06b9cb.md)
- **C — Manual fallback for the current unscaffolded tree:** ask the authorized UI developer to log on to **DEV front end** in SAP GUI, run report `/UI5/UI5_REPOSITORY_LOAD` via `SE38`, enter the approved UI5 repository name and select **Upload** (never Delete). Select the local `webapp` directory, inspect the proposed updates, then supply/verify the package and transport when prompted. The report does not merge conflicting code. If there is no way to confirm CTS recording, cancel rather than proceeding locally. [SAP: UI5 repository upload report](https://help.sap.com/saphelp_snc700_ehp04/helpdata/de/a5/60bd6ed4654fd1b338df065d331872/content.htm)

The **deployment service** copies UI assets. It is not the app's **FI business service**. A successful UI upload does not create `ZFI_ASSIGN_UPLOAD`, authorize FI documents, schedule jobs or create a launchpad tile.

## 5. Verify the transport, not just the deployment message

1. Reopen the parent request in the MCP transport reader or `SE09`/`SE10`. Expand the developer task(s). Record object type, name and package for the table, both classes and the UI5/BSP repository entry (and its generated subobjects as shown). If already-present objects were skipped but this must be a self-contained transport, ask the transport owner how to include them or identify a prerequisite transport; never report them as captured without evidence.
2. Re-read the **active** table definition and class sources, including the guard's test include; compare to the pinned source. Record syntax/activation and ABAP Unit results. Verify the deployed UI `manifest.json`, `Component.js` and `view/Upload.view.xml` from the actual DEV repository or authenticated DEV URL. Confirm the application ID, resource paths, and no demo service. If a required object is missing from the task or another owner's work would be overwritten, stop and report the exact discrepancy.
3. Separate **transport captured** from **app functional**. At the inspected baseline the actual FI OData V4 provider/binding, validation worker, full FI checks, audit and writer are not wired. `test/metadata.xml` is a fixture, not a deployable service. Report **runtime blocked — provider not delivered** rather than creating a dummy service, exposing staging, or contacting the async writer. If a later pinned revision really supplies the provider, identify its actual objects, obtain approval to include them, then verify the DEV service root and `$metadata` with read-only requests. No FI document changes in this run. [SAP: Service Binding](https://help.sap.com/docs/abap-cloud/abap-rap/service-binding)
4. Verify request **and tasks remain modifiable**. Do not release, import, change roles/ICF/client settings, or deploy a launchpad catalog. If an operation failed midway, report exactly what was saved/activated/recorded. Do not delete pre-existing objects, undo unrelated work, or create a second request to hide the failure. Later QAS handoff: [illustrated QAS runbook](../qas/README.md).

### Required handoff (return privately to the operator)

| Evidence | Actual result — never guess |
|---|---|
| Git source | Branch, SHA, clean/diff reviewed |
| SAP destination | Verified backend/front-end DEV SID, client, package(s), effective developer |
| CTS | Parent request(s), developer task(s), status; actual object-list read-back |
| Backend | Per object: created/updated/unchanged/blocked; active version; ABAP Unit result |
| UI | Repository name, upload route, manifest ID, deployed file verification |
| Runtime and blockers | UI assets verified vs. FI provider verified vs. not delivered; any manual step and owner |
| Boundary | No release, no QAS/PRD import, no FI write |
