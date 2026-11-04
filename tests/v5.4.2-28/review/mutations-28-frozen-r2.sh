#!/usr/bin/env bash
# Mutation run for v5.4.2-28: each mutation breaks one rule of the patch; the
# battery must fail at the named check. A catch at another check fails the
# run unless the mutation names that check as an accepted alternate, with
# its reason (r2, Codex S1). A mutation that needs more than one edit lists
# the others in EXTRA (a JSON list of [old, new] pairs, each exactly once).
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

mut() {  # $1 label, $2 expected first FAIL, $3 old text (exactly once), $4 new text,
         # [$5 accepted alternate FAIL, $6 why it is acceptable]; EXTRA: more edits
  n=$((n + 1))
  if ! python3 -c 'import sys, os, json
s = open(sys.argv[1]).read()
edits = [(sys.argv[2], sys.argv[3])] + [tuple(e) for e in json.loads(os.environ.get("EXTRA") or "[]")]
for o, w in edits:
    k = s.count(o)
    if k != 1: sys.exit("anchor matched %d times" % k)
    s = s.replace(o, w)
open(sys.argv[4], "w").write(s)' "$P" "$3" "$4" "$TMP/m.sql"; then
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
  elif [ -n "${5:-}" ] && [ "$got" = "$5" ]; then echo "caught $1 at $got (accepted alternate to $2: $6)"; caught=$((caught + 1))
  else echo "WRONG CHECK $1: caught at $got, named $2"; fail=1; fi
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
mut "N7 the cycle walk counts every closed row" D7d \
  "           AND (d.recorded_until IS NULL OR d.recorded_until > NEW.recorded_at)
           AND d.id <> NEW.id" "           AND d.id <> NEW.id"
mut "N8 the open-row exclusion's bracket half-open" D4a \
  "daterange(effective_date, expiry_date, '[]') WITH &&" "daterange(effective_date, expiry_date, '[)') WITH &&"
# Section 3: four-decimal rates (CI-109)
mut "N9 the rate check at five decimals" R1b \
  "rate_unit IS NOT DISTINCT FROM 'decimal' OR rate_value IS NULL OR (rate_value <> 'NaN' AND rate_value = round(rate_value, 4))" "rate_unit IS NOT DISTINCT FROM 'decimal' OR rate_value IS NULL OR (rate_value <> 'NaN' AND rate_value = round(rate_value, 5))"
mut "N10 the tier check at five decimals" R2b \
  '|| @ * 10000 % 1 != 0)' '|| @ * 100000 % 1 != 0)'
mut "N11 a tier rate's type not checked" R2c \
  '@.type() != "number" || ' ''

# Round 2 (2026-11-04)
mut "N12 the override check at five decimals (Opus N7)" R3a \
  "rate_override = round(rate_override, 4)" "rate_override = round(rate_override, 5)"
mut "N13 changed_by not stamped (Opus N7)" D2e \
  "    NEW.changed_by := NULLIF(pg_catalog.current_setting('app.user_id', true), '')::uuid;
" ""
mut "N14 a consolidated child that names a premise read as a leaf (Opus N7; Codex B3)" Z5h2 \
  "FILTER (WHERE c.is_consolidated OR c.location_id IS NULL)" "FILTER (WHERE c.location_id IS NULL)"
EXTRA='[["ALTER TABLE public.rate_item_dependencies ENABLE ALWAYS TRIGGER a_enforce_rate_item_dependency;", "ALTER TABLE public.rate_item_dependencies ENABLE ALWAYS TRIGGER _enforce_rate_item_dependency;"],
        ["    PERFORM public.assert_wave1_guard_invariants();\n    PERFORM public.assert_no_hard_delete_invariants();", "    PERFORM public.assert_no_hard_delete_invariants();"]]' \
mut "N15 the dependency guard renamed to sort before the row guard (Opus N7; the patch-tail check removed, so the battery must catch it)" D11 \
  "
CREATE TRIGGER a_enforce_rate_item_dependency BEFORE" "
CREATE TRIGGER _enforce_rate_item_dependency BEFORE"
mut "N16 the branch read from the premise again (Codex B3)" Z5m \
  "    IF NOT v_inv.is_consolidated THEN" "    IF v_inv.location_id IS NOT NULL THEN"
mut "N17 a parent's own premise left out of the agreement (r2)" Z5n \
  "            UNION ALL
            SELECT public.premise_time_zone_as_of(v_inv.location_id, p_on)
             WHERE v_inv.location_id IS NOT NULL) z;" ") z;"
mut "N18 a close with a NULL reason (Codex B1)" D7a2 \
  "(closed_reason IS NOT NULL) AND (closed_reason ~ '[[:alnum:]]')" "(closed_reason ~ '[[:alnum:]]')"
mut "N19 NaN in a rate (Fable S2)" R1e \
  "rate_value IS NULL OR (rate_value <> 'NaN' AND rate_value = round(rate_value, 4)));
ALTER TABLE public.rate_item_versions DROP CONSTRAINT IF EXISTS rate_item_versions_fraction" "rate_value IS NULL OR rate_value = round(rate_value, 4));
ALTER TABLE public.rate_item_versions DROP CONSTRAINT IF EXISTS rate_item_versions_fraction"
mut "N20 NaN in an override (Fable S2)" R3c \
  "(rate_override <> 'NaN' AND rate_override = round(rate_override, 4))" "rate_override = round(rate_override, 4)"
mut "N21 the close's header bump removed (Fable S1)" D7c \
  "            UPDATE public.rate_schedules s SET updated_at = now() WHERE s.id = NEW.rate_schedule_id;
        END IF;" "        END IF;"
mut "N22 a fraction-unit rate passes the general check (AC-45)" R5b \
  "    CHECK (rate_unit IS DISTINCT FROM 'decimal' OR rate_value IS NULL" "    CHECK (true OR rate_value IS NULL"
mut "N23 the tier check back in the form a dump cannot restore (Opus B1)" R6 \
  '|| @ * 10000 % 1 != 0)' '|| @ * 10000 != (@ * 10000).floor())'

# Not here: the cycle walk's long-transaction rule (r2, Opus S1) needs two
# committed sessions; races/past-cycle-28.sh is its test, and is run against
# the r1 walk to show it catches it.
echo "mutations-28: $caught of $n caught"
[ "$fail" -eq 0 ] && [ "$caught" -eq "$n" ]
