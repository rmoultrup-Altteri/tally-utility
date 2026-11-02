#!/usr/bin/env bash
# Mutation run for v5.4.2-28: each mutation breaks one rule of the patch; the
# battery must fail, at the named check (or, where noted, the first check
# after it that depends on the rule).
#
#   tests/v5.4.2-28/mutations-28.sh [patch] [battery]
#
# Uses the database name m28 (fixed; one run at a time). Each mutation runs on
# a fresh clone of `tally` with TEMP revoked. Applies the mutated patch only:
# the battery runs on tally + -28 (it also passes on tally + -23/-25/-26 + -28).
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
P=${1:-$ROOT/sql/v5.4.2-28-rates-small-fixes.sql}
B=${2:-$ROOT/tests/v5.4.2-28/battery-28.sql}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; docker exec tally-pg psql -U tally -d postgres -qc "DROP DATABASE IF EXISTS m28" >/dev/null 2>&1' EXIT
docker cp "$B" tally-pg:/tmp/b28m.sql >/dev/null
fail=0; n=0; caught=0

mut() {  # $1 label, $2 expected first FAIL, $3 old text (exactly once), $4 new text
  n=$((n + 1))
  if ! python3 -c 'import sys
s = open(sys.argv[1]).read(); o, w = sys.argv[2], sys.argv[3]
if s.count(o) != 1: sys.exit("anchor matched %d times" % s.count(o))
open(sys.argv[4], "w").write(s.replace(o, w, 1))' "$P" "$3" "$4" "$TMP/m.sql"; then
    echo "SETUP $1: anchor not found exactly once"; fail=1; return
  fi
  docker exec tally-pg psql -U tally -d postgres -qc "DROP DATABASE IF EXISTS m28" -qc "CREATE DATABASE m28 TEMPLATE tally" >/dev/null 2>&1
  docker exec tally-pg psql -U tally -d m28 -qc "REVOKE TEMP ON DATABASE m28 FROM PUBLIC" -qc "REVOKE TEMP ON DATABASE m28 FROM tally_app" -qc "REVOKE TEMP ON DATABASE m28 FROM tally_core" >/dev/null
  docker cp "$TMP/m.sql" tally-pg:/tmp/m28.sql >/dev/null
  if ! docker exec tally-pg psql -U tally -d m28 -v ON_ERROR_STOP=1 -q -o /dev/null -f /tmp/m28.sql >/dev/null 2>&1; then
    echo "SETUP $1: the mutated patch did not apply"; fail=1; return
  fi
  got=$(docker exec tally-pg psql -U tally -d m28 -v ON_ERROR_STOP=1 -q -o /dev/null -f /tmp/b28m.sql 2>&1 | grep -m1 -o "FAIL [A-Za-z0-9]*" | cut -d' ' -f2)
  if [ -z "$got" ]; then echo "MISSED $1: the battery passed"; fail=1
  elif [ "$got" = "$2" ]; then echo "caught $1 at $got"; caught=$((caught + 1))
  else echo "caught $1 at $got (named $2)"; caught=$((caught + 1)); fi
}

# Section 1: the state-agency check's time zone (CI-010)
mut "N1 the Chicago constant is back" Z1 \
  "AT TIME ZONE p_time_zone))" "AT TIME ZONE 'America/Chicago'))"
mut "N2 void children counted" Z5g \
  "c.tenant_id = v_inv.tenant_id AND c.status <> 'void';
    IF v_children" "c.tenant_id = v_inv.tenant_id;
    IF v_children"
mut "N3 children in two zones not refused" Z5e \
  "IF cardinality(v_zones) > 1 THEN" "IF cardinality(v_zones) > 9 THEN"
mut "N4 the zone read for a 0.00 line too" Z6c \
  "IF v_rule.exempts_state_agencies AND p_line.amount <> 0 THEN" "IF v_rule.exempts_state_agencies THEN"
# Section 2: rider dependencies dated (CI-101)
mut "N5 the cycle walk ignores dates" D6b \
  "           AND daterange(d.effective_date, d.expiry_date, '[]') && daterange(NEW.effective_date, NEW.expiry_date, '[]')
    )" "    )"
mut "N6 the closer not stamped" D7c \
  "            NEW.closed_by := NULLIF(pg_catalog.current_setting('app.user_id', true), '')::uuid;" "            NULL;"
mut "N7 the cycle walk counts closed rows" D7d \
  "           AND d.recorded_until IS NULL
           AND d.id <> NEW.id" "           AND d.id <> NEW.id"
mut "N8 the open-row exclusion's bracket half-open" D4a \
  "daterange(effective_date, expiry_date, '[]') WITH &&" "daterange(effective_date, expiry_date, '[)') WITH &&"
# Section 3: four-decimal rates (CI-109)
mut "N9 the rate check at five decimals" R1b \
  "CHECK (rate_value IS NULL OR rate_value = round(rate_value, 4));" "CHECK (rate_value IS NULL OR rate_value = round(rate_value, 5));"
mut "N10 the tier check at five decimals" R2b \
  '@ * 10000 != (@ * 10000).floor()' '@ * 100000 != (@ * 100000).floor()'
mut "N11 a tier rate's type not checked" R2c \
  '@.type() != "number" || ' ''

echo "mutations-28: $caught of $n caught"
[ "$fail" -eq 0 ] && [ "$caught" -eq "$n" ]
