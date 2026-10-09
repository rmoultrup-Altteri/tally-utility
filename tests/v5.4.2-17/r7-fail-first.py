#!/usr/bin/env python3
"""Run each `-- r7:begin NAME` block of battery-17.sql alone against a database
(the battery's own setup, every other r7 block removed, then ROLLBACK), to show
the block FAILS on the previous patch and PASSES on the new one.

    python3 tests/v5.4.2-17/r7-fail-first.py <db> [name ...]
"""
import re, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
src = (HERE / "battery-17.sql").read_text()
pat = re.compile(r"-- r7:begin (\S+)\n(.*?)-- r7:end \1\n", re.S)
names = [m.group(1) for m in pat.finditer(src)]
db = sys.argv[1]
only = set(sys.argv[2:]) or set(names)

def sh(cmd, inp=None):
    return subprocess.run(cmd, input=inp, capture_output=True, text=True)

sh(["docker", "exec", "tally-pg", "rm", "-rf", "/tmp/law"])
sh(["docker", "cp", str(ROOT / "law"), "tally-pg:/tmp/law"])
bad = 0
for n in names:
    if n not in only:
        continue
    # keep block n, drop the others; stop after block n
    def keep(m):
        return m.group(0) if m.group(1) == n else ""
    body = pat.sub(keep, src)
    end = body.index(f"-- r7:end {n}\n") + len(f"-- r7:end {n}\n")
    body = body[:end] + "\nROLLBACK;\n"
    body = body.replace(f"-- r7:begin {n}\n", f"-- r7:begin {n}\n\\set ON_ERROR_STOP 0\n\\set ON_ERROR_ROLLBACK on\n", 1)
    sh(["docker", "exec", "-i", "tally-pg", "sh", "-c", "cat > /tmp/r7-one.sql"], body)
    r = sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", db, "-v", "ON_ERROR_STOP=1", "-q", "-f", "/tmp/r7-one.sql"])
    text = r.stdout + r.stderr
    block = pat.search(body).group(2) if pat.search(body) else ""
    labels = re.findall(r"pg_temp\.(?:refuses|does|ok|ok_sql)\('(\w+):", block)
    does = set(re.findall(r"pg_temp\.does\('(\w+):", block))  # prints nothing when it passes
    print(f"{n}:")
    for lab in labels:
        if re.search(rf"PASS {lab}:", text) or (lab in does and not re.search(rf"FAIL {lab}:", text)):
            print(f"   {lab}: passes")
        else:
            m = re.search(rf"FAIL {lab}:[^\n]*", text)
            print(f"   {lab}: FAILS  {(m.group(0)[:170] if m else '(no result line)')}")
            bad += 1
sys.exit(1 if bad else 0)
