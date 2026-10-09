#!/usr/bin/env python3
"""Run each `-- rN:begin NAME` block of battery-17.sql alone against a database
(the battery's own setup, every other rN block removed, then ROLLBACK), to show
a block FAILS on the previous patch and PASSES on the new one. Cases that are
`does` checks print nothing when they pass.

    python3 tests/v5.4.2-17/fail-first.py <db> [name ...]
"""
import re, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
src = (HERE / "battery-17.sql").read_text()
pat = re.compile(r"-- r(\d+):begin (\S+)\n(.*?)-- r\1:end \2\n", re.S)
names = [m.group(2) for m in pat.finditer(src)]
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
    def keep(m):
        return m.group(0) if m.group(2) == n else ""
    body = pat.sub(keep, src)
    m = pat.search(body)
    rnd = m.group(1)
    begin = f"-- r{rnd}:begin {n}\n"
    end_marker = f"-- r{rnd}:end {n}\n"
    end = body.index(end_marker) + len(end_marker)
    block = m.group(3)
    body = body[:end] + "\nROLLBACK;\n"
    body = body.replace(begin, begin + "\\set ON_ERROR_STOP 0\n\\set ON_ERROR_ROLLBACK on\n", 1)
    sh(["docker", "exec", "-i", "tally-pg", "sh", "-c", "cat > /tmp/fail-first-one.sql"], body)
    r = sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", db, "-v", "ON_ERROR_STOP=1", "-q", "-f", "/tmp/fail-first-one.sql"])
    text = r.stdout + r.stderr
    labels = re.findall(r"pg_temp\.(?:refuses|does|ok|ok_sql)\('(\w+):", block)
    does = set(re.findall(r"pg_temp\.does\('(\w+):", block))
    print(f"{n}:")
    for lab in labels:
        if re.search(rf"PASS {lab}:", text) or (lab in does and not re.search(rf"FAIL {lab}:", text)):
            print(f"   {lab}: passes")
        else:
            mm = re.search(rf"FAIL {lab}:[^\n]*", text)
            print(f"   {lab}: FAILS  {(mm.group(0)[:170] if mm else '(no result line)')}")
            bad += 1
sys.exit(1 if bad else 0)
