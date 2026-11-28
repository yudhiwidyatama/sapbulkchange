import unittest

from check_identity import verify


DIALOG = """T01|system|QAS|010
T01|actor|FIXTURE|DIALOG
T01|company+|C001|0
T01|company-|C002|4
T01|area+|A001|0
T01|area-|A002|4"""
JOB = DIALOG.replace("DIALOG", "BATCH")
ARGS = ("QAS", "010", "FIXTURE", "C001", "C002", "A001", "A002")


class CompareLists(unittest.TestCase):
    def test_expected_pair(self):
        verify(DIALOG, JOB, *ARGS)

    def test_reject_unusable_evidence(self):
        for bad in (DIALOG, JOB.replace("FIXTURE", "OTHER"), JOB.replace("010", "100"),
                    JOB.replace("A002|4", "A002|0"), JOB.replace("C002|4", "C002|12"),
                    JOB.replace("C001|0", "C001|4"), JOB.replace("A001", "A003"),
                    JOB.rsplit("\n", 1)[0], JOB + "\nT01|company+|C001|0", ""):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                verify(DIALOG, bad, *ARGS)
