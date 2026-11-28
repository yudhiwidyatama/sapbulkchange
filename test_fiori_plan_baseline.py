"""Synthetic T02 characterization; imports the existing report simulator."""
import unittest

from test_abap_xlsx_logic import abap_resolve_line


class FirstPlan(unittest.TestCase):
    def test_same_account_different_items(self):
        row = dict(doc="0000000001", year="2025", item="002", blart="SA",
                   budat="20250101", gl="4000", target="NEW")
        first = dict(item="001", blart="SA", budat="20250101",
                     racct="00004000", assignment="NEW")
        second = dict(first, item="002", assignment="OLD")
        items = [first, second]
        for key, old, status in [("002", "OLD", "PLANNED"),
                                 ("001", "NEW", "SKIPPED_ALREADY_SET")]:
            with self.subTest(key=key):
                matched, actual, _ = abap_resolve_line(dict(row, item=key), items)
                self.assertEqual((matched["item"], matched["assignment"], actual),
                                 (key, old, status))
        self.assertEqual(second["assignment"], "OLD")
