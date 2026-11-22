#!/usr/bin/env python3
"""
Fetch ACDOCA lines (ZFDR_ACDOCA_V2_CDS) for the documents listed in the
"change Assignment" Excel file, and compare current ZUONR with KODE PROJECT.

Same endpoint/credentials/parsing as fetch_sap_data_v2.py; filters on
rbukrs + gjahr + belnr (+ rldnr 0L). p_sdate/p_edate are mandatory view
parameters, so they are set to span the posting dates in the file.

Usage: python3 fetch_acdoca_docs.py [--excel FILE] [--company 1000]
"""
import argparse
import csv
import os
import sys
import xml.etree.ElementTree as ET
from datetime import datetime
from urllib.parse import quote

import requests
from requests.packages.urllib3.exceptions import InsecureRequestWarning

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from change_assignment import BASE_DIR, DEFAULT_EXCEL, read_excel  # noqa: E402

requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

BASE = "https://10.60.177.131:44350/sap/opu/odata/sap/ZFDR_ACDOCA_V2_CDS/ZFDR_ACDOCA_V2"
USERNAME = os.environ.get("SAP_USER", "790126")
PASSWORD = os.environ.get("SAP_PASS", "Telkom2025")
ATOM = "{http://www.w3.org/2005/Atom}"
META = "{http://schemas.microsoft.com/ado/2007/08/dataservices/metadata}"


def fetch(company, docs, sdate, edate, chunk=10):
    records = []
    docs = list(docs)
    for i in range(0, len(docs), chunk):
        part = docs[i:i + chunk]
        flt = " or ".join(f"(belnr eq '{d}' and gjahr eq '{y}')" for d, y in part)
        flt = f"rbukrs eq '{company}' and rldnr eq '0L' and ({flt})"
        url = f"{BASE}(p_sdate='{sdate}',p_edate='{edate}')/Set?$filter={quote(flt, safe='')}"
        r = requests.get(url, auth=(USERNAME, PASSWORD), verify=False, timeout=120)
        if r.status_code != 200:
            sys.exit(f"HTTP {r.status_code}: {r.text[:500]}")
        for entry in ET.fromstring(r.content).iter(f"{ATOM}entry"):
            props = entry.find(f"{ATOM}content").find(f"{META}properties")
            records.append({c.tag.split('}')[1]: (c.text or "") for c in props})
        print(f"  chunk {i // chunk + 1}: {len(part)} docs -> {len(records)} lines so far")
    return records


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--excel", default=DEFAULT_EXCEL)
    ap.add_argument("--company", default="1000")
    ap.add_argument("--sdate", default="20160101")
    ap.add_argument("--edate", default="20201231")
    args = ap.parse_args()

    rows, errors = read_excel(args.excel)
    docs = list(dict.fromkeys((r["doc"], r["year"]) for r in rows))
    print(f"{len(docs)} documents from Excel, company {args.company}")
    recs = fetch(args.company, docs, args.sdate, args.edate)

    out = os.path.join(BASE_DIR, f"acdoca_lines_{datetime.now():%Y%m%d_%H%M%S}.csv")
    cols = ["rbukrs", "gjahr", "belnr", "docln", "racct", "prctr", "rbusa", "blart",
            "poper", "budat", "xblnr", "zuonr", "hsl", "sgtxt"]
    with open(out, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(sorted(recs, key=lambda x: (x["belnr"], x["gjahr"], x["docln"])))
    print(f"Saved {len(recs)} ACDOCA lines -> {out}")

    # Compare with Excel
    by_doc = {}
    for x in recs:
        by_doc.setdefault((x["belnr"].lstrip("0"), x["gjahr"]), []).append(x)
    found = sum(1 for d, y in docs if (d.lstrip("0"), y) in by_doc)
    print(f"Documents found in ACDOCA: {found}/{len(docs)}")
    status = {}
    for r in rows:
        lines = [x for x in by_doc.get((r["doc"].lstrip("0"), r["year"]), [])
                 if x["racct"].lstrip("0") == r["gl"].lstrip("0")]
        if not lines:
            st = "NO_LINE_WITH_THIS_RACCT"
        elif len(lines) > 1:
            st = "AMBIGUOUS_MULTIPLE_LINES"
        elif lines[0]["zuonr"] == r["target"]:
            st = "ALREADY_EQUAL"
        else:
            st = "NEEDS_CHANGE"
        status[st] = status.get(st, 0) + 1
    print("Excel row vs ACDOCA:", status)


if __name__ == "__main__":
    main()
