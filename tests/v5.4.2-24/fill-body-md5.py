#!/usr/bin/env python3
"""Fill the md5 of each function body listed in assert_suspense_pledge_guard_invariants' c_bodies.

PostgreSQL stores a function's prosrc exactly as written between its dollar
quotes, so the md5 is computed from the patch text. Run after any edit to a
listed function:  python3 tests/v5.4.2-24/fill-body-md5.py
"""
import hashlib, re, sys
from pathlib import Path
P = Path(__file__).resolve().parents[2] / "sql/v5.4.2-24-unmatched-cash-and-pledges.sql"
s = P.read_text()
def body(name: str) -> str:
    m = re.search(r"CREATE OR REPLACE FUNCTION public\." + re.escape(name) + r"\(.*?\bAS (\$[a-z]*\$)(.*?)\1", s, re.S)
    if not m:
        sys.exit(f"function not found: {name}")
    return m.group(2)
def fill(m: re.Match) -> str:
    sig, old = m.group(1), m.group(2)
    return f"'{sig} @{hashlib.md5(body(sig.split('(')[0]).encode()).hexdigest()}'"
new = re.sub(r"'([a-z_]+\([^']*\)) @([0-9a-f]{32})'", fill, s)
P.write_text(new)
print("filled", len(re.findall(r"'[a-z_]+\([^']*\) @[0-9a-f]{32}'", new)), "bodies")
