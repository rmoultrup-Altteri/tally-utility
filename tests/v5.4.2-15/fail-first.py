#!/usr/bin/env python3
"""Run each `-- rN:begin NAME` block of battery-15r.sql alone against a database
(the battery's own setup, every other rN block removed, then ROLLBACK), to show
a block FAILS on the previous build and PASSES on the new one. Every check
prints a PASS line when it passes (a setup that died before the block shows as
failures, never as passes).

A block that reads what another block wrote says so with `-- rN:needs rM[,rK]`
on a line of its own inside it; the runner keeps those blocks as well.

    python3 tests/v5.4.2-15/fail-first.py <db> [name ...]
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
src = (HERE / "battery-15r.sql").read_text()
pat = re.compile(r"-- r(\d+):begin (\S+)\n(.*?)-- r\1:end \2\n", re.S)
blocks = {m.group(2): (m.group(1), m.group(3)) for m in pat.finditer(src)}
names = list(blocks)
needs_pat = re.compile(r"^-- r\d+:needs (r\d+(?:,r\d+)*)$", re.M)


def sh(cmd: list[str], inp: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, input=inp, capture_output=True, text=True)


def needed_numbers(name: str) -> set[str]:
    nums = {blocks[name][0]}
    for m in needs_pat.finditer(blocks[name][1]):
        nums |= {n[1:] for n in m.group(1).split(",")}
    return nums


def main() -> int:
    db = sys.argv[1]
    only = set(sys.argv[2:]) or set(names)
    bad = 0
    for n in names:
        if n not in only:
            continue
        keep_nums = needed_numbers(n)
        body = pat.sub(lambda m: m.group(0) if m.group(1) in keep_nums else "", src)
        rnd, block = blocks[n]
        end_marker = f"-- r{rnd}:end {n}\n"
        end = body.index(end_marker) + len(end_marker)
        body = body[:end] + "\nROLLBACK;\n"
        begin = f"-- r{rnd}:begin {n}\n"
        body = body.replace(begin, begin + "\\set ON_ERROR_STOP 0\n\\set ON_ERROR_ROLLBACK on\n", 1)
        sh(["docker", "exec", "-i", "tally-pg", "sh", "-c", "cat > /tmp/fail-first-one.sql"], body)
        r = sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", db, "-v", "ON_ERROR_STOP=1", "-q", "-f", "/tmp/fail-first-one.sql"])
        text = r.stdout + r.stderr
        labels = re.findall(r"pg_temp\.(?:refuses|does|ok|does_as)\('(\w+):", block)
        print(f"{n}:")
        if os.environ.get("FF_SHOW"):
            for line in [l for l in text.splitlines() if "ERROR" in l][:3]:
                print("     !", line[:230])
        for lab in labels:
            if re.search(rf"PASS {lab}:", text):
                print(f"   {lab}: passes")
            else:
                mm = re.search(rf"FAIL {lab}:[^\n]*", text)
                print(f"   {lab}: FAILS  {(mm.group(0)[:170] if mm else '(no result line)')}")
                bad += 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
