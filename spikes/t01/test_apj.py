"""Offline packaging checks only; these do not execute SAP or Fiori."""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).parent / "apj"


class FioriJobPackage(unittest.TestCase):
    def test_template_points_to_worker_and_log(self):
        template = json.loads((ROOT / "zfi_t01_check.sajt.json").read_text())
        catalog = template["generalInformation"]["catalogName"].lower()
        entry = json.loads((ROOT / (catalog + ".sajc.json")).read_text())
        worker = entry["generalInformation"]["className"].lower()
        source = (ROOT / (worker + ".clas.abap")).read_text()
        self.assertIn(f"CLASS {worker} DEFINITION", source)
        obj, sub = re.search(r"object = '(\w+)' subobject = '(\w+)'", source).groups()
        log = json.loads((ROOT / (obj.lower() + ".aplo.json")).read_text())
        self.assertIn(sub, [s["name"] for s in log["subobjects"]])
        self.assertIn("assign_to_current_appl_job = abap_true", source)

    def test_inputs_and_checks_match_the_fixture(self):
        source = (ROOT / "zcl_fi_t01_probe.clas.abap").read_text()
        self.assertEqual(re.findall(r"selname = '(\w+)'", source), ["CA", "CD", "AA", "AD"])
        self.assertEqual(re.findall(r"AUTHORITY-CHECK OBJECT '(\w+)' ID 'ACTVT' FIELD '02' ID '(\w+)' FIELD (\w+)\.", source),
                         [("F_BKPF_BUK", "BUKRS", "ca"), ("F_BKPF_BUK", "BUKRS", "cd"),
                          ("F_BKPF_GSB", "GSBER", "aa"), ("F_BKPF_GSB", "GSBER", "ad")])
