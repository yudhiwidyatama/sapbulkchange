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


def normalize_buzei(val: str) -> str:
    """Exact port of lcl_types=>normalize_buzei."""
    s = val.strip()
    if not s:
        return ""
    if "." in s:
        dot_pos = s.index(".")
        if dot_pos > 0:
            s = s[:dot_pos]
    s = s.lstrip("0")
    if not s or not s.isdigit() or len(s) > 3:
        return ""
    return s.zfill(3)


def parse_excel_date(raw: str) -> str:
    """Exact port of lcl_types=>parse_excel_date."""
    import datetime

    s = raw.strip()
    if not s:
        return ""
    num_part = s
    if "." in num_part:
        dot_off = num_part.index(".")
        if dot_off > 0:
            frac = num_part[dot_off + 1 :]
            if frac and all(c == "0" for c in frac):
                num_part = num_part[:dot_off]
    if num_part.isdigit() and 4 <= len(num_part) <= 6:
        serial = int(num_part)
        if 1 <= serial <= 2958465:
            dt = datetime.date(1899, 12, 30) + datetime.timedelta(days=serial)
            return dt.strftime("%Y%m%d")
    if len(s) == 8 and s.isdigit():
        return s
    parts = []
    if "-" in s:
        parts = s.split("-")
    elif "." in s:
        parts = s.split(".")
    elif "/" in s:
        parts = s.split("/")
    if len(parts) == 3:
        p1 = parts[0].strip()
        p2 = parts[1].strip()
        p3 = parts[2].strip().split(" ")[0]
        if p1.isdigit() and p2.isdigit() and p3.isdigit():
            if len(p1) == 4:
                p2 = p2.zfill(2)
                p3 = p3.zfill(2)
                if len(p2) == 2 and len(p3) == 2:
                    return f"{p1}{p2}{p3}"
            elif len(p3) == 4:
                p1 = p1.zfill(2)
                p2 = p2.zfill(2)
                if len(p1) == 2 and len(p2) == 2:
                    return f"{p3}{p2}{p1}"
    return ""


def abap_extract_rows(sheet_rows: list[dict], limit_docs: int = 0):
    """Exact port of lcl_excel_parser=>extract_rows."""
    header = sheet_rows[0]["cells"]
    col_doc_year = 0
    col_doc_no = 0
    col_year = 0
    col_buzei = 0
    col_source = 0
    col_gl = 0
    col_blart = 0
    col_budat = 0
    col_account = 0
    col_target = 0

    for col, val in sorted(header.items()):
        hname = " ".join(val.strip().upper().split())
        if hname == "DOC NUMBER + YEAR" and col_doc_year == 0:
            col_doc_year = col
        elif hname in ("DOCUMENT NUMBER", "DOC NUMBER", "DOC. NO.", "DOCUMENT NO", "BELNR") and col_doc_no == 0:
            col_doc_no = col
        elif hname in ("FISCAL YEAR", "YEAR", "GJAHR") and col_year == 0:
            col_year = col
        elif hname in ("BUZEI", "LINE ITEM", "ITEM", "ITM", "LINE ITEM NO", "DOC. ITEM") and col_buzei == 0:
            col_buzei = col
        elif hname == "SOURCE DATA" and col_source == 0:
            col_source = col
        elif hname in ("G/L ACCOUNT", "G/L", "GL ACCOUNT", "HKONT", "RACCT") and col_gl == 0:
            col_gl = col
        elif hname in ("DOCUMENT TYPE", "DOC. TYPE", "DOC TYPE", "TYPE", "BLART") and col_blart == 0:
            col_blart = col
        elif hname in ("POSTING DATE", "POST. DATE", "PSTNG DATE", "BUDAT") and col_budat == 0:
            col_budat = col
        elif hname == "ACCOUNT" and col_account == 0:
            col_account = col
        elif hname == "KODE PROJECT" and col_target == 0:
            col_target = col

    missing = []
    if col_doc_year == 0 and col_doc_no == 0:
        missing.append("'Doc Number + Year' (or 'Document Number')")
    if col_buzei == 0:
        missing.append("'Buzei' / 'Line Item'")
    if col_blart == 0:
        missing.append("'Document Type'")
    if col_budat == 0:
        missing.append("'Posting Date'")
    if col_gl == 0:
        missing.append("'G/L Account'")
    if col_target == 0:
        missing.append("'KODE PROJECT'")
    if missing:
        raise ValueError(f"Excel is missing required columns: [{', '.join(missing)}]")

    all_rows, errors = [], []
    for srow in sheet_rows[1:]:
        cells = srow["cells"]
        key = cells.get(col_doc_year, "").strip() if col_doc_year else ""
        doc_cell = cells.get(col_doc_no, "").strip() if col_doc_no else ""
        yr_cell = cells.get(col_year, "").strip() if col_year else ""
        if not key and not doc_cell:
            continue

        budat_raw = cells.get(col_budat, "").strip()
        budat = parse_excel_date(budat_raw)

        doc_raw, year_raw = "", ""
        if key:
            if len(key) < 5:
                errors.append((srow["row_num"], f"bad 'Doc Number + Year': '{key}'"))
                continue
            doc_raw, year_raw = key[:-4], key[-4:]
        else:
            doc_raw = doc_cell
            if yr_cell:
                year_raw = yr_cell
            elif budat:
                year_raw = budat[:4]

        if not doc_raw or len(doc_raw) > 10 or len(year_raw) != 4 or not year_raw.isdigit():
            err_key = key if key else f"{doc_cell}/{yr_cell}"
            errors.append((srow["row_num"], f"bad Document Number / Year: '{err_key}'"))
            continue

        buzei_raw = cells.get(col_buzei, "").strip()
        buzei = normalize_buzei(buzei_raw)
        if not buzei:
            errors.append((srow["row_num"], f"bad or empty Buzei / Line Item: '{buzei_raw}'"))
            continue

        source = cells.get(col_source, "").strip().upper() if col_source else ""
        if col_source and source:
            if source not in ("BEBAN", "VENDOR"):
                errors.append((srow["row_num"], f"unknown Source Data '{source}'"))
                continue
        elif not source:
            source = "BEBAN"

        blart_raw = cells.get(col_blart, "").strip().upper()
        if not blart_raw:
            errors.append((srow["row_num"], "Document Type is empty"))
            continue

        if not budat:
            errors.append((srow["row_num"], f"bad or empty Posting Date: '{budat_raw}'"))
            continue

        gl_raw = cells.get(col_gl, "").strip()
        if not gl_raw:
            errors.append((srow["row_num"], "G/L Account is empty"))
            continue

        target = cells.get(col_target, "").strip()
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
            "item": buzei,
            "source": source,
            "gl": gl_raw,
            "blart": blart_raw,
            "budat": budat,
            "account": cells.get(col_account, "").strip() if col_account else "",
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


def abap_resolve_line(row: dict, doc_items: list[dict]):
    """Exact port of lcl_orchestrator=>resolve_line."""
    if not doc_items:
        return None, "DOC_NOT_FOUND", "Document not found in ACDOCA"

    hits = [i for i in doc_items if i["item"] == row["item"]]
    if not hits:
        return (
            None,
            "ITEM_NOT_FOUND",
            f"Line item (BUZEI) {row['item']} not found in document {row['doc']}/{row['year']}",
        )

    item = hits[0]
    mismatches = []
    exp_blart = row["blart"].strip().upper()
    act_blart = item["blart"].strip().upper()
    if exp_blart != act_blart:
        mismatches.append(f"Document Type mismatch (Excel='{exp_blart}', SAP='{act_blart}')")

    if row["budat"] != item["budat"]:
        mismatches.append(f"Posting Date mismatch (Excel='{row['budat']}', SAP='{item['budat']}')")

    exp_gl = row["gl"].strip().lstrip("0")
    act_gl = item["racct"].strip().lstrip("0")
    if exp_gl != act_gl:
        mismatches.append(f"G/L Account mismatch (Excel='{row['gl']}', SAP='{act_gl}')")

    if mismatches:
        return item, "VALIDATION_FAILED", "; ".join(mismatches)

    if item["assignment"] == row["target"]:
        return item, "SKIPPED_ALREADY_SET", "Assignment already equals target value"

    return item, "PLANNED", ""


class TestAbapZProgramLogic(unittest.TestCase):
    def test_real_excel_with_fbl3n_buzei_and_plan_parity(self):
        """Verify 100% parity on all 48 lines / 24 documents when Buzei column is added to the real Excel."""
        with open(EXCEL_PATH, "rb") as f:
            xlsx_bytes = f.read()

        sheet_rows = abap_parse_xlsx(xlsx_bytes)

        # Load ACDOCA lines from acdoca_lines_20261118_220450.csv
        acdoca_by_doc = {}
        with open(ACDOCA_CSV, encoding="utf-8") as f:
            for r in csv.DictReader(f):
                key = (r["belnr"].lstrip("0"), r["gjahr"])
                acdoca_by_doc.setdefault(key, []).append({
                    "item": r["docln"][-3:],
                    "racct": r["racct"],
                    "blart": r["blart"],
                    "budat": r["budat"],
                    "assignment": r["zuonr"],
                })

        # Add FBL3N 'Buzei' column (col 28) to the parsed sheet rows
        sheet_rows[0]["cells"][28] = "Buzei"
        for srow in sheet_rows[1:]:
            c = srow["cells"]
            key = c.get(1, "").strip()
            if not key:
                continue
            doc_no0, yr = key[:-4].lstrip("0"), key[-4:]
            gl_no0 = c.get(6, "").strip().lstrip("0")
            for item in acdoca_by_doc.get((doc_no0, yr), []):
                if item["racct"].lstrip("0") == gl_no0:
                    c[28] = str(int(item["item"]))  # e.g. '1' or '2' as exported by FBL3N
                    break

        rows, errors, doc_keys = abap_extract_rows(sheet_rows)

        self.assertEqual(len(errors), 0)
        self.assertEqual(len(doc_keys), 24)
        self.assertEqual(len(rows), 48)

        # Simulate lcl_orchestrator=>run in Dry-Run mode
        abap_plan = []
        for doc, year in doc_keys:
            items = acdoca_by_doc.get((doc.lstrip("0"), year), [])
            for r in [x for x in rows if x["doc"] == doc and x["year"] == year]:
                it, status, msg = abap_resolve_line(r, items)
                self.assertIn(status, ("PLANNED", "SKIPPED_ALREADY_SET"))
                abap_plan.append({
                    "doc": doc,
                    "year": year,
                    "item": r["item"],
                    "source": r["source"],
                    "old": it["assignment"],
                    "target": r["target"],
                    "status": status,
                    "message": "" if status in ("PLANNED", "SKIPPED_ALREADY_SET") else msg,
                })

        with open(EXPECTED_PLAN_CSV, encoding="utf-8") as f:
            expected_plan = list(csv.DictReader(f))

        self.assertEqual(abap_plan, expected_plan)

    def test_validation_fields_mismatch_fails_row(self):
        """Verify that mismatch on Document Type, Posting Date, or G/L Account fails the row."""
        doc_items = [
            {
                "item": "001",
                "racct": "0051376037",
                "blart": "SA",
                "budat": "20190131",
                "assignment": "OLD_ASSIGN",
            }
        ]

        # 1. Document Type mismatch
        _, st1, msg1 = abap_resolve_line(
            {"doc": "0100004137", "year": "2019", "item": "001", "blart": "KR", "budat": "20190131", "gl": "51376037", "target": "NEW"},
            doc_items,
        )
        self.assertEqual(st1, "VALIDATION_FAILED")
        self.assertIn("Document Type mismatch", msg1)

        # 2. Posting Date mismatch
        _, st2, msg2 = abap_resolve_line(
            {"doc": "0100004137", "year": "2019", "item": "001", "blart": "SA", "budat": "20190228", "gl": "51376037", "target": "NEW"},
            doc_items,
        )
        self.assertEqual(st2, "VALIDATION_FAILED")
        self.assertIn("Posting Date mismatch", msg2)

        # 3. G/L Account mismatch
        _, st3, msg3 = abap_resolve_line(
            {"doc": "0100004137", "year": "2019", "item": "001", "blart": "SA", "budat": "20190131", "gl": "20101002", "target": "NEW"},
            doc_items,
        )
        self.assertEqual(st3, "VALIDATION_FAILED")
        self.assertIn("G/L Account mismatch", msg3)

    def test_macos_and_windows_xlsx_variations(self):
        """Verify rich text, phonetic guides, inlineStr, formula str, and /xl/... paths with Buzei & validation columns."""
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
                '<c r="C1" t="inlineStr"><is><t>Line Item</t></is></c>'
                '<c r="F1" t="str"><v>G/L Account</v></c>'
                '<c r="G1" t="inlineStr"><is><t>Account</t></is></c>'
                '<c r="I1" t="inlineStr"><is><t>KODE PROJECT</t></is></c>'
                '<c r="J1" t="inlineStr"><is><t>Document Type</t></is></c>'
                '<c r="T1" t="inlineStr"><is><t>Posting Date</t></is></c>'
                '</row>'
                '<row r="2">'
                '<c r="A2" t="inlineStr"><is><t>1000041372019</t></is></c>'
                '<c r="B2" t="inlineStr"><is><t>BEBAN</t></is></c>'
                '<c r="C2"><v>1</v></c>'
                '<c r="F2"><v>51376037</v></c>'
                '<c r="G2"><v>51376037</v></c>'
                '<c r="I2" t="s"><v>1</v></c>'
                '<c r="J2" t="inlineStr"><is><t>SA</t></is></c>'
                '<c r="T2"><v>43496</v></c>'
                '</row>'
                '</sheetData></worksheet>'
            ))

        sheet_rows = abap_parse_xlsx(buf.getvalue())
        rows, errors, doc_keys = abap_extract_rows(sheet_rows)
        self.assertEqual(len(errors), 0)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["doc"], "0100004137")
        self.assertEqual(rows[0]["year"], "2019")
        self.assertEqual(rows[0]["item"], "001")
        self.assertEqual(rows[0]["blart"], "SA")
        self.assertEqual(rows[0]["budat"], "20190131")
        self.assertEqual(rows[0]["target"], "P-1409SCC-TTES0601")


if __name__ == "__main__":
    unittest.main(verbosity=2)
