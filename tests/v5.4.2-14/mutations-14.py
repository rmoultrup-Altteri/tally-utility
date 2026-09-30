#!/usr/bin/env python3
"""v5.4.2-14 — prove battery-14 CATCHES drift, not merely passes.

Each mutation alters a copy of the patch, applies it to a fresh clone of
`tally`, which must be a -13 BASE (tu.sql 25,930 lines, ab3ce7ae…), and runs
the battery. CAUGHT when the named check reports FAIL or errors.

    python3 tests/v5.4.2-14/mutations-14.py
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATCH = ROOT / "sql/v5.4.2-14-governing-test-gate-to-core.sql"
BATTERY = ROOT / "tests/v5.4.2-14/battery-14.sql"
DB = "m14"


def rep(old, new):
    def m(s):
        assert old in s, f"mutation anchor not found: {old[:70]!r}"
        return s.replace(old, new, 1)
    return m


def cut(start, end):
    def m(s):
        i, j = s.index(start), s.index(end)
        return s[:i] + s[j:]
    return m


MUTATIONS = [
    ("M1", "the function is not re-created (the -12 gate stays)", "A1",
     cut("DROP FUNCTION IF EXISTS public.meter_governing_test(uuid, date);", "COMMENT ON FUNCTION public.meter_governing_test")),
    ("M2", "EXECUTE left to PUBLIC", "A3",
     rep("REVOKE ALL ON FUNCTION public.meter_governing_test(uuid, date) FROM PUBLIC;",
         "GRANT EXECUTE ON FUNCTION public.meter_governing_test(uuid, date) TO PUBLIC;")),
    # Deleting the GRANT alone changes nothing: -11's default privileges give
    # tally_app EXECUTE on every new public function. Revoke it outright.
    ("M3", "tally_app loses EXECUTE", "A3",
     rep("GRANT EXECUTE ON FUNCTION public.meter_governing_test(uuid, date) TO tally_app;",
         "REVOKE EXECUTE ON FUNCTION public.meter_governing_test(uuid, date) FROM tally_app;")),
    ("M4", "the old record_basis comment kept", "A5",
     cut("COMMENT ON COLUMN public.meter_tests.record_basis IS", "COMMENT ON TABLE public.meter_test_absence_declarations IS")),
]


def sh(cmd, inp=None):
    return subprocess.run(cmd, input=inp, capture_output=True, text=True)


def psql(db, sql):
    return sh(["docker", "exec", "-i", "tally-pg", "psql", "-U", "tally", "-d", db, "-v", "ON_ERROR_STOP=1", "-q", "-f", "-"], sql)


def main():
    base = PATCH.read_text()
    missed = 0
    for mid, what, check, mut in MUTATIONS:
        for q in (f"DROP DATABASE IF EXISTS {DB}", f"CREATE DATABASE {DB} TEMPLATE tally"):
            sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-qc", q])
        a = psql(DB, "SET search_path = ''; SET check_function_bodies = on;\n" + mut(base))
        if a.returncode:
            print(f"{mid} APPLY-ERROR ({what}): {a.stderr.strip().splitlines()[-1]}")
            missed += 1
            continue
        out = psql(DB, BATTERY.read_text())
        text = out.stdout + out.stderr
        if re.search(rf"FAIL {check}:", text) or ("ERROR" in text and not re.search(rf"PASS {check}:", text)):
            print(f"{mid} caught at {check}: {what}")
        else:
            print(f"{mid} MISSED ({check} still passes): {what}")
            missed += 1
    sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-qc", f"DROP DATABASE IF EXISTS {DB}"])
    print(f"{len(MUTATIONS) - missed}/{len(MUTATIONS)} caught")
    sys.exit(1 if missed else 0)


if __name__ == "__main__":
    main()
