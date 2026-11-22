#!/usr/bin/env python3
"""
Change Assignment (ZUONR) of posted FI documents via the custom RFC
ZRFC_FI_CHANGE_ASSIGN, called over SOAP (/sap/bc/soap/rfc) with Zeep,
same pattern as create_pr_bapi.py. Replaces the JournalEntryBulkChangeRequest
route that is blocked by the SRT runtime setup.

Reuses Excel reading, ACDOCA lookup (ZFDR_ACDOCA_V2_CDS) and matching from
change_assignment.py. The RFC is synchronous: the RETURN table tells the
result immediately; a CDS re-read then confirms the value.

  PY=~/Documents/SourceCode/browser-use-test/cdspy/venv/bin/python
  $PY change_assignment_rfc.py --fetch-wsdl     # once, after the FM is activated
  $PY change_assignment_rfc.py --dry-run        # plan only, nothing sent
  $PY change_assignment_rfc.py --testrun        # RFC validates, changes nothing
  $PY change_assignment_rfc.py --limit 1        # real run, first document
  $PY change_assignment_rfc.py                  # real run, all documents

Credentials: config.json SAP_SOAP (USERNAME/PASSWORD/ENDPOINT), same as the PR scripts.
"""
import argparse
import csv
import json
import logging
import os
import sys
from collections import OrderedDict
from datetime import datetime

import requests
from requests.auth import HTTPBasicAuth

from change_assignment import (BASE_DIR, DEFAULT_COMPANY, DEFAULT_EXCEL, fetch_items,
                               find_config, read_excel, resolve, _strip0)

FM_NAME = "ZRFC_FI_CHANGE_ASSIGN"
WSDL_FILE = os.path.join(BASE_DIR, "wsdl", "zrfc_fi_change_assign.wsdl")
LOG_DIR = os.path.join(BASE_DIR, "logs")
log = logging.getLogger("change_assignment_rfc")


def setup_logging(ts, tag):
    os.makedirs(LOG_DIR, exist_ok=True)
    path = os.path.join(LOG_DIR, f"change_assignment_rfc_{ts}{tag}.log")
    fmt = logging.Formatter("%(asctime)s %(levelname)-7s %(message)s", "%Y-%m-%d %H:%M:%S")
    log.setLevel(logging.INFO)
    log.handlers.clear()
    for h in (logging.FileHandler(path, encoding="utf-8"), logging.StreamHandler()):
        h.setFormatter(fmt)
        log.addHandler(h)
    return path


def load_config():
    with open(find_config() or "config.json") as f:
        return json.load(f)["SAP_SOAP"]


def fetch_wsdl(cfg):
    os.makedirs(os.path.dirname(WSDL_FILE), exist_ok=True)
    url = f"{cfg['ENDPOINT']}&services={FM_NAME}"
    r = requests.get(url, auth=HTTPBasicAuth(cfg["USERNAME"], cfg["PASSWORD"]), timeout=60)
    if r.status_code != 200:
        sys.exit(f"WSDL download failed: HTTP {r.status_code}\n{r.text[:300]}\n"
                 f"(is {FM_NAME} created, remote-enabled and active?)")
    with open(WSDL_FILE, "w", encoding="utf-8") as f:
        f.write(r.text)
    log.info("WSDL saved: %s", WSDL_FILE)


def make_client(cfg):
    from zeep import Client, Settings
    from zeep.transports import Transport
    session = requests.Session()
    session.auth = HTTPBasicAuth(cfg["USERNAME"], cfg["PASSWORD"])
    client = Client(wsdl=WSDL_FILE, transport=Transport(session=session, timeout=120),
                    settings=Settings(strict=False, xml_huge_tree=True))
    # WSDL location may be a hostname that is not reachable from here: force config endpoint
    client.service._binding_options["address"] = cfg["ENDPOINT"]
    return client


def call_rfc(client, company, doc, year, lines, testrun):
    """lines: [{item, target, old}]. Returns (ok, [messages])."""
    params = {
        "IV_BUKRS": company,
        "IV_BELNR": doc,
        "IV_GJAHR": year,
        "IT_ITEMS": {"item": [{"BUZEI": l["item"], "ZUONR": l["target"], "OLDVAL": l["old"]}
                              for l in lines]},
        "RETURN": {"item": []},
    }
    if testrun:
        params["IV_TESTRUN"] = "X"
    resp = client.service[FM_NAME](**params)
    msgs, ok = [], True
    ret = getattr(resp, "RETURN", None)
    for m in (getattr(ret, "item", None) or []):
        msgs.append(f"[{m.TYPE}] {m.MESSAGE} {m.MESSAGE_V1 or ''} {m.MESSAGE_V2 or ''}".strip())
        if m.TYPE in ("E", "A"):
            ok = False
    return ok, msgs


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--excel", default=DEFAULT_EXCEL)
    ap.add_argument("--company", default=DEFAULT_COMPANY)
    ap.add_argument("--sdate", default="20160101")
    ap.add_argument("--edate", default="20201231")
    ap.add_argument("--limit", type=int, help="only the first N documents")
    ap.add_argument("--dry-run", action="store_true", help="plan only, no SAP change call")
    ap.add_argument("--testrun", action="store_true", help="RFC validates only (IV_TESTRUN=X)")
    ap.add_argument("--fetch-wsdl", action="store_true")
    args = ap.parse_args()

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    tag = "_dryrun" if args.dry_run else "_testrun" if args.testrun else ""
    log_path = setup_logging(ts, tag)
    cfg = load_config()

    if args.fetch_wsdl:
        fetch_wsdl(cfg)
        return

    rows, errors = read_excel(args.excel)
    for xl_row, msg in errors:
        log.warning("Excel row %s skipped: %s", xl_row, msg)
    docs = OrderedDict()
    for r in rows:
        docs.setdefault((r["doc"], r["year"]), []).append(r)
    if args.limit:
        docs = OrderedDict(list(docs.items())[:args.limit])
    log.info("%d lines in %d documents (company %s)", sum(map(len, docs.values())), len(docs), args.company)

    all_items = fetch_items(args.company, list(docs.keys()), args.sdate, args.edate)

    # ---- plan -------------------------------------------------------------
    plan = []      # one dict per line
    for (doc, year), drows in docs.items():
        items = all_items.get((_strip0(doc), year), [])
        for r in drows:
            base = dict(doc=doc, year=year, source=r["source"], target=r["target"], item="", old="")
            if not items:
                plan.append({**base, "status": "DOC_NOT_FOUND", "message": ""})
                continue
            it, st = resolve(r, items)
            if not it:
                plan.append({**base, "status": st, "message": ""})
            elif it["assignment"] == r["target"]:
                plan.append({**base, "item": it["item"], "old": it["assignment"],
                             "status": "SKIPPED_ALREADY_SET", "message": ""})
            else:
                plan.append({**base, "item": it["item"], "old": it["assignment"],
                             "status": "PLANNED", "message": ""})

    out_csv = os.path.join(BASE_DIR, f"assignment_change_rfc_{ts}{tag}.csv")

    def write_csv():
        with open(out_csv, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=["doc", "year", "item", "source", "old", "target",
                                              "status", "message"])
            w.writeheader()
            w.writerows(plan)
        log.info("Results: %s", out_csv)

    n_plan = sum(p["status"] == "PLANNED" for p in plan)
    log.info("Planned changes: %d; not actionable: %d", n_plan, len(plan) - n_plan)
    if args.dry_run or n_plan == 0:
        write_csv()
        return

    # ---- send: one RFC call per document (all-or-nothing per document) ----
    if not os.path.exists(WSDL_FILE):
        sys.exit(f"{WSDL_FILE} missing; run with --fetch-wsdl first")
    client = make_client(cfg)
    by_doc = OrderedDict()
    for p in plan:
        if p["status"] == "PLANNED":
            by_doc.setdefault((p["doc"], p["year"]), []).append(p)

    for (doc, year), lines in by_doc.items():
        try:
            ok, msgs = call_rfc(client, args.company, doc, year, lines, args.testrun)
        except Exception as e:                                    # noqa: BLE001
            log.exception("RFC call failed for %s/%s", doc, year)
            for p in lines:
                p["status"], p["message"] = "SEND_ERROR", str(e)[:200]
            continue
        status = ("TESTRUN_OK" if args.testrun else "SENT") if ok else "REJECTED"
        for p in lines:
            p["status"], p["message"] = status, " | ".join(msgs)[:500]
        log.info("%s/%s: %s  %s", doc, year, status, " | ".join(msgs))

    # ---- verify by re-reading the CDS ------------------------------------
    if not args.testrun:
        sent = [p for p in plan if p["status"] == "SENT"]
        keys = list(OrderedDict.fromkeys((p["doc"], p["year"]) for p in sent))
        if keys:
            now = fetch_items(args.company, keys, args.sdate, args.edate)
            for p in sent:
                cur = next((i["assignment"] for i in now.get((_strip0(p["doc"]), p["year"]), [])
                            if i["item"] == p["item"]), None)
                p["status"] = "CHANGED" if cur == p["target"] else "NOT_CHANGED"
                if p["status"] == "NOT_CHANGED":
                    p["message"] += f" | current value {cur!r}"
    write_csv()
    log.info("Finished. Log: %s", log_path)


if __name__ == "__main__":
    main()
