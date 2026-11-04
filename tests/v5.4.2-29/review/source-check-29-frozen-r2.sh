#!/usr/bin/env bash
# v5.4.2-29: the patch's county list is exactly the Census file (no database).
#   S1  the stored Census file is the one the patch cites (md5)
#   S2  the patch lists every county of the file, code and name, once, and
#       nothing else
#   S3  the zones: Mountain exactly at 48141 and 48229 (49 CFR 71.7(e)),
#       Central everywhere else
#   usage: source-check-29.sh [patch]
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
P=${1:-$ROOT/sql/v5.4.2-29-texas-counties.sql}
F=$ROOT/application/places-sources/census-st48_tx_cou2020.txt
python3 - "$P" "$F" <<'PY'
import hashlib, re, sys
p, f = sys.argv[1], sys.argv[2]
fail = 0
def check(label, cond, why=''):
    global fail
    print(('PASS ' if cond else 'FAIL ') + label + ('' if cond else ': ' + why))
    fail |= not cond
raw = open(f, 'rb').read()
check('S1 the Census file is the one cited', hashlib.md5(raw).hexdigest() == 'e1ea7280eb41b680feb924b3bef2c411', hashlib.md5(raw).hexdigest())
rows = [l.split('|') for l in raw.decode().splitlines()[1:]]
census = {r[1] + r[2]: r[4] for r in rows if r[0] == 'TX' and r[5] == 'H1' and r[6] == 'A'}
check('S1b the file has 254 active Texas counties, every row one of them', len(census) == 254 == len(rows), str(len(census)))
listed = re.findall(r"^    \('(48\d{3})', '((?:[^']|'')*)', '([A-Za-z_/]+)'\)[,;]?$", open(p).read(), re.M)
codes = [c for c, _, _ in listed]
check('S2 the patch lists 254 rows, each code once', len(listed) == 254 and len(set(codes)) == 254, str(len(listed)))
pl = {c: n.replace("''", "'") for c, n, _ in listed}
check('S2b codes and names are exactly the file\'s', pl == census,
      'differs at ' + ', '.join('|'.join(x) for x in sorted(set(pl.items()) ^ set(census.items())))[:300] if pl != census else '')
mtn = sorted(c for c, _, z in listed if z == 'America/Denver')
other = {z for _, _, z in listed if z != 'America/Denver'}
check('S3 Mountain exactly at 48141 and 48229, Central elsewhere', mtn == ['48141', '48229'] and other == {'America/Chicago'}, f'{mtn} {other}')
sys.exit(1 if fail else 0)
PY
