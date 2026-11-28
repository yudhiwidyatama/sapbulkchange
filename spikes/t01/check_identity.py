"""Compare T01 probe lists locally; never send spool contents to a service."""
import argparse
from pathlib import Path


def records(text):
    rows = {}
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("T01|"):
            continue
        fields = [part.strip() for part in line.split("|")]
        if len(fields) != 4 or fields[1] in rows or not all(fields):
            raise ValueError("Malformed or duplicate probe record")
        rows[fields[1]] = tuple(fields[2:])
    return rows


def verify(dialog, job, system, client, actor, ca, cd, aa, ad):
    if ca == cd or aa == ad:
        raise ValueError("Allowed and denied fixture values must differ")
    expected = {"system": (system, client), "company+": (ca, "0"),
                "company-": (cd, "4"), "area+": (aa, "0"), "area-": (ad, "4")}
    for text, mode in [(dialog, "DIALOG"), (job, "BATCH")]:
        if records(text) != {**expected, "actor": (actor, mode)}:
            raise ValueError(f"{mode}: identity, context or decision matrix mismatch")


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    for name in ("dialog", "job"):
        p.add_argument(name, type=Path)
    for name in ("system", "client", "actor", "ca", "cd", "aa", "ad"):
        p.add_argument(name)
    a = p.parse_args()
    try:
        verify(a.dialog.read_text(encoding="utf-8"), a.job.read_text(encoding="utf-8"),
               a.system, a.client, a.actor, a.ca, a.cd, a.aa, a.ad)
    except (OSError, ValueError) as exc:
        p.exit(1, f"NOT VERIFIED: {exc}\n")
    print("Probe records match. Confirm job provenance separately; not a release gate pass.")
