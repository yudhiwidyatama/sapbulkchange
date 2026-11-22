#!/usr/bin/env python3
"""
Mass-change the Assignment (ZUONR) of FI document line items using the
standard SOAP service JournalEntryBulkChangeRequest_In (asynchronous).

Input : Excel file (e.g. "Contoh Data SAP for change Assignment.xlsx")
        - "Doc Number + Year"  -> document number + fiscal year (e.g. 1000041372019)
        - "Source Data"        -> BEBAN (G/L line) or VENDOR (vendor line)
        - "G/L Account"/"Account" -> used to find the line item number
        - "KODE PROJECT"       -> the new Assignment value
Flow  : 1. read Excel            2. look up line item numbers (ZFDR_ACDOCA_V2_CDS)
        3. build + send request  4. wait, re-read items, verify
        5. write result CSV

Credentials: env SAP_USER / SAP_PASSWORD, else config.json SAP_SOAP, else prompted.

Typical usage
    python3 change_assignment.py --fetch-wsdl
    python3 change_assignment.py --dry-run                 # plan only, nothing sent
    python3 change_assignment.py --limit 1                 # real run, first document only
    python3 change_assignment.py                           # real run, all documents
"""
import argparse
import csv
import getpass
import logging
import os
import sys
import time
import uuid
from collections import OrderedDict
from datetime import datetime, timezone

import openpyxl
import requests
from requests.auth import HTTPBasicAuth

DEFAULT_HOST = "http://rarqasapp.telkom.co.id:8001"
DEFAULT_CLIENT = "100"
DEFAULT_COMPANY = "1000"
BASE_DIR = os.path.dirname(os.path.abspath(__file__))   # all paths are relative to this folder
DEFAULT_EXCEL = os.path.join(BASE_DIR, "Contoh Data SAP for change Assignment.xlsx")
DEFAULT_WSDL = os.path.join(BASE_DIR, "wsdl_je_change", "journalentrybulkchangerequest.wsdl")
WSDL_PATH = ("/sap/bc/srt/wsdl/flv_10002A111AD1/bndg_url/sap/bc/srt/xip/sap/"
             "journalentrybulkchangerequest_/100/journalentrybulkchangerequest/"
             "journalentrybulkchangerequest")
ASSIGNMENT_MAX_LEN = 18
LOG_DIR = os.path.join(BASE_DIR, "logs")
log = logging.getLogger("change_assignment")


def find_config():
    """config.json: this folder first, then the parent folder (shared with the PR/PO scripts)."""
    for d in (BASE_DIR, os.path.dirname(BASE_DIR), os.getcwd()):
        path = os.path.join(d, "config.json")
        if os.path.exists(path):
            return path
    return None


def setup_logging(ts, dry_run):
    """Console + file logging. File: logs/change_assignment_<ts>[_dryrun].log
    (credentials are never logged; HTTP debug logging stays off)."""
    os.makedirs(LOG_DIR, exist_ok=True)
    path = os.path.join(LOG_DIR, f"change_assignment_{ts}{'_dryrun' if dry_run else ''}.log")
    fmt = logging.Formatter("%(asctime)s %(levelname)-7s %(message)s", "%Y-%m-%d %H:%M:%S")
    log.setLevel(logging.INFO)
    log.handlers.clear()
    for h in (logging.FileHandler(path, encoding="utf-8"), logging.StreamHandler()):
        h.setFormatter(fmt)
        log.addHandler(h)
    return path


# --------------------------------------------------------------------------- #
# Excel
# --------------------------------------------------------------------------- #
def read_excel(path):
    """Return (rows, errors). One row per Excel line that needs a change."""
    wb = openpyxl.load_workbook(path, data_only=True)
    ws = wb.worksheets[0]
    header = [str(c.value).strip() if c.value is not None else "" for c in ws[1]]
    col = {name: i for i, name in enumerate(header)}
    need = ["Doc Number + Year", "Source Data", "G/L Account", "Account", "KODE PROJECT"]
    missing = [n for n in need if n not in col]
    if missing:
        sys.exit(f"Excel is missing columns: {missing}")

    rows, errors = [], []
    for xl_row, r in enumerate(ws.iter_rows(min_row=2, values_only=True), start=2):
        key = str(r[col["Doc Number + Year"]] or "").strip()
        if not key:
            continue
        if len(key) < 5:
            errors.append((xl_row, f"bad 'Doc Number + Year': {key!r}"))
            continue
        doc, year = key[:-4], key[-4:]
        source = str(r[col["Source Data"]] or "").strip().upper()
        target = str(r[col["KODE PROJECT"]] or "").strip()
        if source not in ("BEBAN", "VENDOR"):
            errors.append((xl_row, f"unknown Source Data {source!r}"))
            continue
        if not target:
            errors.append((xl_row, "KODE PROJECT is empty"))
            continue
        if len(target) > ASSIGNMENT_MAX_LEN:
            errors.append((xl_row, f"KODE PROJECT longer than {ASSIGNMENT_MAX_LEN}: {target!r}"))
            continue
        rows.append(dict(
            xl_row=xl_row, doc=doc.zfill(10), year=year, source=source,
            gl=str(r[col["G/L Account"]] or "").strip(),
            account=str(r[col["Account"]] or "").strip(),
            target=target))
    return rows, errors


# --------------------------------------------------------------------------- #
# Line item lookup (ZFDR_ACDOCA_V2_CDS via fetch_acdoca_docs.fetch)
# --------------------------------------------------------------------------- #
def _strip0(s):
    return str(s or "").strip().lstrip("0")


def fetch_items(company, doc_keys, sdate, edate):
    """Return {(doc_no_without_leading_zeros, year): [ {item, racct, assignment} ]}.
    The CDS has no supplier/account type, so lines are matched by racct (G/L or
    reconciliation account); docln (6 digits) -> item ID (last 3 digits)."""
    from fetch_acdoca_docs import fetch as fetch_acdoca   # lazy: avoids circular import
    out = {}
    for x in fetch_acdoca(company, doc_keys, sdate, edate):
        out.setdefault((_strip0(x["belnr"]), x["gjahr"]), []).append(
            dict(item=x["docln"][-3:], racct=x["racct"], assignment=x.get("zuonr", "")))
    return out


def resolve(row, items):
    """Match an Excel row to exactly one SAP line item. Returns (item|None, status)."""
    hits = [i for i in items if _strip0(i["racct"]) == _strip0(row["gl"])]
    if len(hits) == 1:
        return hits[0], "OK"
    return None, ("NO_MATCH" if not hits else "AMBIGUOUS")


# --------------------------------------------------------------------------- #
# Payload
# --------------------------------------------------------------------------- #
def build_payload(changes, root_id, now_iso):
    """changes: list of dicts with doc, year, company, item, type(S/K), target.
    G/L items first, then vendor items (the service drops lines silently otherwise)."""
    def item(c):
        return {
            "MessageHeader": {"ID": f"A{c['doc']}{c['year']}{c['item']}", "CreationDateTime": now_iso},
            "ItemKey": {"AccountingDocument": c["doc"], "CompanyCode": c["company"],
                        "FiscalYear": c["year"], "AccountingDocumentItemID": c["item"]},
            "AssignmentReferenceChange": {"AssignmentReference": c["target"],
                                          "FieldValueChangeIsRequested": True},
        }
    gl = [item(c) for c in changes if c["type"] == "S"]
    dc = [item(c) for c in changes if c["type"] == "K"]
    payload = {"MessageHeader": {"ID": root_id, "CreationDateTime": now_iso}}
    if gl:
        payload["JournalEntryGLItem"] = gl
    if dc:
        payload["JournalEntryDebtorCreditorItem"] = dc
    return payload


def make_zeep_client(wsdl, session):
    from zeep import Client, Settings
    from zeep.plugins import HistoryPlugin
    from zeep.transports import Transport
    history = HistoryPlugin()
    client = Client(wsdl=wsdl, transport=Transport(session=session, timeout=120),
                    settings=Settings(strict=False, xml_huge_tree=True), plugins=[history])
    return client, history


def service_with_message_id(client, msg_id):
    """The endpoint uses (Plain SOAP) reliable messaging: every call needs a unique
    Message ID, passed as ?MessageId=<UUID> (SAP Note 2237014). Re-sending the same
    ID is safe: SAP detects the duplicate and returns the earlier result."""
    binding_name = next(iter(client.wsdl.bindings))
    address = client.service._binding_options["address"]
    sep = "&" if "?" in address else "?"
    return client.create_service(binding_name, f"{address}{sep}MessageId={msg_id}")


def load_xsd(wsdl_path):
    """XMLSchema built from the (single, import-free) schema embedded in the WSDL."""
    from lxml import etree
    ns = {"xsd": "http://www.w3.org/2001/XMLSchema", "wsdl": "http://schemas.xmlsoap.org/wsdl/"}
    sch = etree.parse(wsdl_path).find(".//wsdl:types/xsd:schema", ns)
    return etree.XMLSchema(etree.fromstring(etree.tostring(sch)))


def validate_message(schema, envelope):
    """Validate the SOAP body payload against the WSDL's XSD. Returns (ok, errors)."""
    body = envelope.find("{http://schemas.xmlsoap.org/soap/envelope/}Body")
    ok = schema.validate(body[0])
    return ok, [f"line {e.line}: {e.message}" for e in schema.error_log][:20]


def save_xml(envelope, name):
    from lxml import etree
    path = os.path.join(LOG_DIR, name)
    with open(path, "wb") as f:
        f.write(etree.tostring(envelope, pretty_print=True))
    return path


def pick_operation(client, forced=None):
    if forced:
        return forced
    ops = list(client.service._binding._operations.keys())
    if len(ops) != 1:
        sys.exit(f"WSDL has operations {ops}; choose one with --operation")
    return ops[0]


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--excel", default=DEFAULT_EXCEL)
    ap.add_argument("--host", default=DEFAULT_HOST)
    ap.add_argument("--sap-client", default=DEFAULT_CLIENT)
    ap.add_argument("--company", default=DEFAULT_COMPANY, help="company code (default 1000)")
    ap.add_argument("--wsdl", default=DEFAULT_WSDL, help="local WSDL file")
    ap.add_argument("--operation", help="SOAP operation name (auto-detected if the WSDL has one)")
    ap.add_argument("--sdate", default="20160101", help="CDS p_sdate (posting date range start)")
    ap.add_argument("--edate", default="20201231", help="CDS p_edate (posting date range end)")
    ap.add_argument("--fetch-wsdl", action="store_true", help="download the WSDL and exit")
    ap.add_argument("--dry-run", action="store_true", help="resolve lines, write plan + XML, send nothing")
    ap.add_argument("--limit", type=int, help="only process the first N documents")
    ap.add_argument("--wait", type=int, default=30, help="seconds to wait before verifying (async service)")
    ap.add_argument("--batch-docs", type=int, default=50, help="documents per SOAP request")
    args = ap.parse_args()
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_path = setup_logging(ts, args.dry_run)
    log.info("Start %s | host=%s sap-client=%s company=%s | dry_run=%s limit=%s wait=%s",
             os.path.basename(__file__), args.host, args.sap_client, args.company,
             args.dry_run, args.limit, args.wait)

    user, pwd = os.environ.get("SAP_USER"), os.environ.get("SAP_PASSWORD")
    cfg_path = find_config()
    if not (user and pwd) and cfg_path:                        # same system as SAP_SOAP.ENDPOINT
        import json
        with open(cfg_path) as f:
            soap = json.load(f).get("SAP_SOAP", {})
        user, pwd = user or soap.get("USERNAME"), pwd or soap.get("PASSWORD")
    user = user or input("SAP user: ")
    pwd = pwd or getpass.getpass("SAP password: ")
    session = requests.Session()
    session.auth = HTTPBasicAuth(user, pwd)
    log.info("SAP user: %s (password not logged)", user)
    session.hooks["response"].append(
        lambda r, *a, **k: log.info("HTTP %s %s -> %s %s", r.request.method,
                                    r.url.split("?")[0], r.status_code, r.reason))

    # -- WSDL download ------------------------------------------------------
    if args.fetch_wsdl:
        r = session.get(f"{args.host}{WSDL_PATH}", params={"sap-client": args.sap_client}, timeout=60)
        r.raise_for_status()
        os.makedirs(os.path.dirname(args.wsdl), exist_ok=True)
        with open(args.wsdl, "wb") as f:
            f.write(r.content)
        log.info(f"WSDL saved to {args.wsdl} ({len(r.content)} bytes)")
        return

    # -- read Excel ---------------------------------------------------------
    rows, errors = read_excel(args.excel)
    for xl_row, msg in errors:
        log.warning(f"Excel row {xl_row}: {msg}")
    docs = OrderedDict()
    for r in rows:
        docs.setdefault((r["doc"], r["year"]), []).append(r)
    if args.limit:
        docs = OrderedDict(list(docs.items())[:args.limit])
    log.info(f"{sum(len(v) for v in docs.values())} lines in {len(docs)} documents "
          f"(company {args.company})")

    # -- resolve line items (one CDS call set for all documents) ------------
    log.info(f"Lookup: ZFDR_ACDOCA_V2_CDS @ 10.60.177.131 | change: {args.host}")
    all_items = fetch_items(args.company, list(docs.keys()), args.sdate, args.edate)
    plan, changes = [], []
    for (doc, year), drows in docs.items():
        items = all_items.get((_strip0(doc), year), [])
        if not items:
            for r in drows:
                plan.append(dict(doc=doc, year=year, item="", source=r["source"], old="",
                                 target=r["target"], status="DOC_NOT_FOUND", message=""))
            continue
        for r in drows:
            it, st = resolve(r, items)
            if not it:
                plan.append(dict(doc=doc, year=year, item="", source=r["source"], old="",
                                 target=r["target"], status=st, message=""))
            elif it["assignment"] == r["target"]:
                plan.append(dict(doc=doc, year=year, item=it["item"], source=r["source"],
                                 old=it["assignment"], target=r["target"],
                                 status="SKIPPED_ALREADY_SET", message=""))
            else:
                plan.append(dict(doc=doc, year=year, item=it["item"], source=r["source"],
                                 old=it["assignment"], target=r["target"],
                                 status="PLANNED", message=""))
                changes.append(dict(doc=doc, year=year, company=args.company, item=it["item"],
                                    type="S" if r["source"] == "BEBAN" else "K",
                                    target=r["target"]))

    result_file = os.path.join(BASE_DIR, f"assignment_change_{'plan' if args.dry_run else 'results'}_{ts}.csv")

    def write_results():
        with open(result_file, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=["doc", "year", "item", "source", "old",
                                              "target", "status", "message"])
            w.writeheader()
            w.writerows(plan)
        for p in plan:
            log.info("LINE doc=%s year=%s item=%s %s: %r -> %r [%s] %s", p["doc"], p["year"],
                     p["item"], p["source"], p["old"], p["target"], p["status"], p["message"])
        counts = {}
        for p in plan:
            counts[p["status"]] = counts.get(p["status"], 0) + 1
        log.info(f"Results -> {result_file}   {counts}")

    if not changes:
        write_results()
        log.info("Nothing to change.")
        return

    # -- build, validate against the WSDL's XSD, (optionally) send ----------
    if not os.path.exists(args.wsdl):
        write_results()
        log.error("WSDL not found at %s; run with --fetch-wsdl first", args.wsdl)
        sys.exit(1)
    client, history = make_zeep_client(args.wsdl, session)
    schema = load_xsd(args.wsdl)
    op = pick_operation(client, args.operation)
    log.info("SOAP operation: %s", op)
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f0Z")
    planned = {(p["doc"], p["year"], p["item"]): p for p in plan if p["status"] == "PLANNED"}

    doc_keys = list(OrderedDict.fromkeys((c["doc"], c["year"]) for c in changes))
    batches = [doc_keys[i:i + args.batch_docs] for i in range(0, len(doc_keys), args.batch_docs)]
    for n, batch in enumerate(batches, 1):
        bset = set(batch)
        bch = [c for c in changes if (c["doc"], c["year"]) in bset]
        payload = build_payload(bch, f"ZUONR{ts}_{n:03d}", now_iso)
        env = client.create_message(client.service, op, **payload)
        req_file = save_xml(env, f"request_{ts}_{n:03d}.xml")
        ok, errs = validate_message(schema, env)
        log.info("Batch %d/%d: %d lines (docs: %s), request -> %s, XSD validation: %s",
                 n, len(batches), len(bch), ", ".join(d.lstrip("0") for d, _ in batch),
                 req_file, "VALID" if ok else "INVALID")
        if not ok:
            for e in errs:
                log.error("  XSD: %s", e)
            for c in bch:
                planned[(c["doc"], c["year"], c["item"])].update(
                    status="XSD_INVALID", message=errs[0][:200] if errs else "")
            continue
        if args.dry_run:
            continue
        msg_id = str(uuid.uuid4()).upper()
        log.info("Batch %d/%d: sending with MessageId=%s", n, len(batches), msg_id)
        try:
            service_with_message_id(client, msg_id)[op](**payload)
            log.info("Batch %d/%d sent. Check /AIF/ERR (namespace /FINAC, interface JECHANGEIN) "
                     "for processing errors.", n, len(batches))
        except Exception as e:                       # noqa: BLE001 - keep going, report per line
            log.exception("SOAP call failed for batch %d/%d", n, len(batches))
            for c in bch:
                planned[(c["doc"], c["year"], c["item"])].update(
                    status="SEND_ERROR", message=str(e)[:200])
        finally:
            for kind, rec in (("sent", history.last_sent), ("response", history.last_received)):
                if rec and rec.get("envelope") is not None:
                    path = save_xml(rec["envelope"], f"{kind}_{ts}_{n:03d}.xml")
                    log.info("  %s envelope -> %s", kind, path)

    if args.dry_run:
        write_results()
        log.info("Dry run finished. Log: %s", log_path)
        return
    if not any(p["status"] == "PLANNED" for p in plan):
        write_results()
        log.error("Nothing was sent successfully; see log: %s", log_path)
        return

    # -- verify (service is asynchronous) ----------------------------------
    log.info(f"Waiting {args.wait}s, then re-reading documents ...")
    time.sleep(args.wait)
    by_key = {(p["doc"], p["year"], p["item"]): p for p in plan if p["status"] == "PLANNED"}
    doc_keys = list(OrderedDict.fromkeys((d, y) for d, y, _ in by_key))
    try:
        now_items = fetch_items(args.company, doc_keys, args.sdate, args.edate)
    except Exception as e:                           # noqa: BLE001
        for p in by_key.values():
            p["status"], p["message"] = "VERIFY_ERROR", str(e)[:200]
    else:
        for (doc, year, item), p in by_key.items():
            cur = next((i["assignment"] for i in now_items.get((_strip0(doc), year), [])
                        if i["item"] == item), None)
            if cur == p["target"]:
                p["status"] = "CHANGED"
            else:
                p["status"] = "NOT_CHANGED"
                p["message"] = f"current value {cur!r}; check /AIF/ERR (e.g. FINS_ACDOC_POST089) or wait longer"
    write_results()
    log.info("Finished. Log: %s", log_path)


if __name__ == "__main__":
    main()
