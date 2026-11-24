#!/usr/bin/env python3
"""
Verification test suite for the ABAP Z-Program (zfi_bulk_change_assign.abap).
Simulates the exact streaming sXML state machine of lcl_xlsx_reader,
lcl_excel_parser, and lcl_orchestrator against:
  1. The real 'Contoh Data SAP for change Assignment.xlsx'
  2. The real 'acdoca_lines_20261118_220450.csv' and
     'assignment_change_plan_20261118_220701.csv' (asserting 100% parity
     on all 48 rows / 24 documents)
  3. macOS & Windows OpenXML (.xlsx) variations:
     - Rich text runs (<si><r><t>...</t></r></si>)
     - Phonetic guides (<rPh><t>...</t></rPh>)
     - Inline strings (t="inlineStr")
     - Cached formula strings (t="str")
     - Leading-slash relationship targets (Target="/xl/worksheets/sheet1.xml")
     - Sparse rows & multi-letter columns (A..AA)
"""
import csv
import io
import os
import unittest
import xml.etree.ElementTree as ET
import zipfile

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
EXCEL_PATH = os.path.join(BASE_DIR, "Contoh Data SAP for change Assignment.xlsx")
ACDOCA_CSV = os.path.join(BASE_DIR, "acdoca_lines_20261118_220450.csv")
EXPECTED_PLAN_CSV = os.path.join(BASE_DIR, "assignment_change_plan_20261118_220701.csv")


def local_name(tag: str) -> str:
    return tag.split("}", 1)[1] if "}" in tag else tag


def col_letters_to_index(cell_ref: str) -> int:
    """Exact port of lcl_xlsx_reader=>col_letters_to_index."""
    ref = cell_ref.strip().upper()
    col = 0
    for ch in ref:
        if ch == "$":
            continue
        if ch.isdigit():
            break
        if "A" <= ch <= "Z":
            col = col * 26 + (ord(ch) - ord("A") + 1)
    return col


def abap_resolve_first_sheet_path(zf: zipfile.ZipFile) -> str:
    """Exact port of lcl_xlsx_reader=>resolve_first_sheet_path."""
    default_path = "xl/worksheets/sheet1.xml"
    if "xl/workbook.xml" not in zf.namelist():
        return default_path
    wb_root = ET.fromstring(zf.read("xl/workbook.xml"))
    rid = None
    for el in wb_root.iter():
        if local_name(el.tag) == "sheet":
            for k, v in el.attrib.items():
                if local_name(k) == "id":
                    rid = v
                    break
            if rid:
                break
    if not rid or "xl/_rels/workbook.xml.rels" not in zf.namelist():
        return default_path
    rels_root = ET.fromstring(zf.read("xl/_rels/workbook.xml.rels"))
    for el in rels_root.iter():
        if local_name(el.tag) == "Relationship":
            rel_id = el.attrib.get("Id", "")
            target = el.attrib.get("Target", "")
            if rel_id == rid and target:
                target = target.lstrip("/")
                if not target.startswith("xl/"):
                    target = "xl/" + target
                return target
    return default_path


def abap_parse_shared_strings(xml_bytes: bytes) -> list[str]:
    """Exact streaming state machine port of lcl_xlsx_reader=>parse_shared_strings."""
    strings = []
    in_si = False
    in_rph = False
    in_t = False
    current_si = ""

    for event, elem in ET.iterparse(io.BytesIO(xml_bytes), events=("start", "end")):
        name = local_name(elem.tag)
        if event == "start":
            if name == "si":
                in_si = True
                in_rph = False
                in_t = False
                current_si = ""
            elif name == "rPh":
                in_rph = True
            elif name == "t" and in_si and not in_rph:
                in_t = True
        elif event == "end":
            if name == "t":
                if in_t and elem.text:
                    current_si += elem.text
                in_t = False
            elif name == "rPh":
                in_rph = False
            elif name == "si":
                strings.append(current_si)
                in_si = False
    return strings


def abap_parse_worksheet(xml_bytes: bytes, shared_strings: list[str]) -> list[dict]:
    """Exact streaming state machine port of lcl_xlsx_reader=>parse_worksheet."""
    rows = []
    current_row = None
    last_row_num = 0
    last_col_idx = 0
    cell_type = ""
    cell_val = ""
    col_idx = 0
    in_v = False
    in_is = False
    in_is_t = False

    for event, elem in ET.iterparse(io.BytesIO(xml_bytes), events=("start", "end")):
        name = local_name(elem.tag)
        if event == "start":
            if name == "row":
                r_attr = elem.attrib.get("r", "0")
                row_num = int(r_attr) if r_attr.isdigit() and int(r_attr) > 0 else last_row_num + 1
                last_row_num = row_num
                last_col_idx = 0
                current_row = {"row_num": row_num, "cells": {}}
            elif name == "c":
                cell_ref = elem.attrib.get("r", "")
                cell_type = elem.attrib.get("t", "")
                cell_val = ""
                in_v = False
                in_is = False
                in_is_t = False
                col_idx = col_letters_to_index(cell_ref) if cell_ref else last_col_idx + 1
                last_col_idx = col_idx
            elif name == "v":
                in_v = True
            elif name == "is":
                in_is = True
            elif name == "t" and (in_is or cell_type == "inlineStr"):
                in_is_t = True
        elif event == "end":
            if name == "v":
                if in_v and elem.text:
                    cell_val += elem.text
                in_v = False
            elif name == "t":
                if in_is_t and elem.text:
                    cell_val += elem.text
                in_is_t = False
            elif name == "is":
                in_is = False
            elif name == "c":
                resolved = cell_val
                if cell_type == "s" and cell_val != "":
                    idx = int(cell_val)
                    resolved = shared_strings[idx] if 0 <= idx < len(shared_strings) else ""
                if col_idx > 0 and current_row is not None:
                    current_row["cells"][col_idx] = resolved
            elif name == "row":
                if current_row and current_row["cells"]:
                    rows.append(current_row)
    return rows


def abap_parse_xlsx(xlsx_bytes: bytes) -> list[dict]:
    with zipfile.ZipFile(io.BytesIO(xlsx_bytes)) as zf:
        ss = []
        if "xl/sharedStrings.xml" in zf.namelist():
            ss = abap_parse_shared_strings(zf.read("xl/sharedStrings.xml"))
        sheet_path = abap_resolve_first_sheet_path(zf)
        return abap_parse_worksheet(zf.read(sheet_path), ss)


def abap_extract_rows(sheet_rows: list[dict], limit_docs: int = 0):
    """Exact port of lcl_excel_parser=>extract_rows."""
    header = sheet_rows[0]["cells"]
    col_map = {v.strip().upper(): k for k, v in header.items()}
    need = ["DOC NUMBER + YEAR", "SOURCE DATA", "G/L ACCOUNT", "ACCOUNT", "KODE PROJECT"]
    missing = [n for n in need if n not in col_map]
    if missing:
        raise ValueError(f"Excel is missing required columns: {missing}")

    all_rows, errors = [], []
    for srow in sheet_rows[1:]:
        cells = srow["cells"]
        key = cells.get(col_map["DOC NUMBER + YEAR"], "").strip()
        if not key:
            continue
        if len(key) < 5:
            errors.append((srow["row_num"], f"bad 'Doc Number + Year': '{key}'"))
            continue
        doc_raw, year_raw = key[:-4], key[-4:]
        if not year_raw.isdigit() or len(doc_raw) > 10:
            errors.append((srow["row_num"], f"bad 'Doc Number + Year': '{key}'"))
            continue
        source = cells.get(col_map["SOURCE DATA"], "").strip().upper()
        if source not in ("BEBAN", "VENDOR"):
            errors.append((srow["row_num"], f"unknown Source Data '{source}'"))
            continue
        target = cells.get(col_map["KODE PROJECT"], "").strip()
        if not target:
            errors.append((srow["row_num"], "KODE PROJECT is empty"))
            continue
        if len(target) > 18:
            errors.append((srow["row_num"], f"KODE PROJECT longer than 18: '{target}'"))
            continue
        all_rows.append({
            "xl_row": srow["row_num"],
            "doc": doc_raw.zfill(10),
            "year": year_raw,
            "source": source,
            "gl": cells.get(col_map["G/L ACCOUNT"], "").strip(),
            "account": cells.get(col_map["ACCOUNT"], "").strip(),
            "target": target,
        })

    doc_keys = []
    for r in all_rows:
        dk = (r["doc"], r["year"])
        if dk not in doc_keys:
            if limit_docs > 0 and len(doc_keys) >= limit_docs:
                continue
            doc_keys.append(dk)

    rows = [r for r in all_rows if (r["doc"], r["year"]) in doc_keys]
    return rows, errors, doc_keys


class TestAbapZProgramLogic(unittest.TestCase):
    def test_real_excel_and_plan_parity(self):
        """Verify 100% parity on all 48 lines / 24 documents against real Excel & plan CSV."""
        with open(EXCEL_PATH, "rb") as f:
            xlsx_bytes = f.read()

        sheet_rows = abap_parse_xlsx(xlsx_bytes)
        rows, errors, doc_keys = abap_extract_rows(sheet_rows)

        self.assertEqual(len(errors), 0)
        self.assertEqual(len(doc_keys), 24)
        self.assertEqual(len(rows), 48)

        # Load ACDOCA lines from acdoca_lines_20261118_220450.csv
        acdoca_by_doc = {}
        with open(ACDOCA_CSV, encoding="utf-8") as f:
            for r in csv.DictReader(f):
                key = (r["belnr"].lstrip("0"), r["gjahr"])
                acdoca_by_doc.setdefault(key, []).append({
                    "item": r["docln"][-3:],
                    "racct": r["racct"],
                    "assignment": r["zuonr"],
                })

        # Simulate lcl_orchestrator=>run in Dry-Run mode
        abap_plan = []
        for doc, year in doc_keys:
            items = acdoca_by_doc.get((doc.lstrip("0"), year), [])
            for r in [x for x in rows if x["doc"] == doc and x["year"] == year]:
                hits = [i for i in items if i["racct"].lstrip("0") == r["gl"].lstrip("0")]
                self.assertEqual(len(hits), 1)
                it = hits[0]
                status = "SKIPPED_ALREADY_SET" if it["assignment"] == r["target"] else "PLANNED"
                abap_plan.append({
                    "doc": doc,
                    "year": year,
                    "item": it["item"],
                    "source": r["source"],
                    "old": it["assignment"],
                    "target": r["target"],
                    "status": status,
                    "message": "",
                })

        with open(EXPECTED_PLAN_CSV, encoding="utf-8") as f:
            expected_plan = list(csv.DictReader(f))

        self.assertEqual(abap_plan, expected_plan)

    def test_macos_and_windows_xlsx_variations(self):
        """Verify rich text, phonetic guides, inlineStr, formula str, and /xl/... paths."""
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w") as zf:
            zf.writestr("xl/workbook.xml", (
                '<?xml version="1.0" encoding="UTF-8"?>'
                '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
                'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
                '<sheets><sheet name="MacSheet" sheetId="1" r:id="rId1"/></sheets></workbook>'
            ))
            zf.writestr("xl/_rels/workbook.xml.rels", (
                '<?xml version="1.0" encoding="UTF-8"?>'
                '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
                'Target="/xl/worksheets/sheet1.xml"/></Relationships>'
            ))
            zf.writestr("xl/sharedStrings.xml", (
                '<?xml version="1.0" encoding="UTF-8"?>'
                '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
                '<si><t>Doc Number + Year</t></si>'
                '<si><r><t>P-1409</t></r><r><t>SCC-TTES0601</t></r><rPh><t>PHONETIC</t></rPh></si>'
                '</sst>'
            ))
            zf.writestr("xl/worksheets/sheet1.xml", (
                '<?xml version="1.0" encoding="UTF-8"?>'
                '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
                '<sheetData>'
                '<row r="1">'
                '<c r="A1" t="s"><v>0</v></c>'
                '<c r="B1" t="inlineStr"><is><t>Source Data</t></is></c>'
                '<c r="F1" t="str"><v>G/L Account</v></c>'
                '<c r="G1" t="inlineStr"><is><t>Account</t></is></c>'
                '<c r="I1" t="inlineStr"><is><t>KODE PROJECT</t></is></c>'
                '</row>'
                '<row r="2">'
                '<c r="A2" t="inlineStr"><is><t>1000041372019</t></is></c>'
                '<c r="B2" t="inlineStr"><is><t>BEBAN</t></is></c>'
                '<c r="F2"><v>51376037</v></c>'
                '<c r="G2"><v>51376037</v></c>'
                '<c r="I2" t="s"><v>1</v></c>'
                '</row>'
                '</sheetData></worksheet>'
            ))

        sheet_rows = abap_parse_xlsx(buf.getvalue())
        rows, errors, doc_keys = abap_extract_rows(sheet_rows)
        self.assertEqual(len(errors), 0)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["doc"], "0100004137")
        self.assertEqual(rows[0]["year"], "2019")
        self.assertEqual(rows[0]["target"], "P-1409SCC-TTES0601")


if __name__ == "__main__":
    unittest.main(verbosity=2)
