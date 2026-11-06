#!/usr/bin/env bash
# Mutation run for v5.4.2-30: each mutation breaks one guard of the patch and
# must be caught where it names:
#   a battery label (L18, Q3 …)  the mutated patch applies; battery-30 fails there
#   APPLY:<fragment>             the mutated patch itself refuses, naming it
#   PRE:<case>                   preconditions-30.sh, run on the mutated patch,
#                                fails that case (the guards that fire only on a
#                                database holding data `tally` does not)
# A catch elsewhere fails the run. EXTRA: a JSON list of further [old, new]
# edits, each matching exactly once.
#   tests/v5.4.2-30/mutations-30.sh [patch]    (uses m30 and m30p; one run at a time)
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
P=${1:-$ROOT/sql/v5.4.2-30-tax-levies-and-taxability.sql}
B=$ROOT/tests/v5.4.2-30/battery-30.sql
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; docker exec tally-pg psql -U tally -d postgres -qc "DROP DATABASE IF EXISTS m30" >/dev/null 2>&1' EXIT
docker cp "$B" tally-pg:/tmp/b30m.sql >/dev/null
fail=0; n=0; caught=0

mut() {  # $1 label, $2 expected, $3 old text (exactly once), $4 new text
  n=$((n + 1)); local exp=$2 got=""
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
  case $exp in
    PRE:*) got="PRE:$(tests/v5.4.2-30/preconditions-30.sh "$TMP/m.sql" 2>&1 | grep -m1 -o '^FAIL C[0-9]*' | cut -d' ' -f2)" ;;
    *)
      docker exec tally-pg psql -U tally -d postgres -qc "DROP DATABASE IF EXISTS m30" -qc "CREATE DATABASE m30 TEMPLATE tally" >/dev/null 2>&1
      docker exec tally-pg psql -U tally -d m30 -qc "REVOKE TEMP ON DATABASE m30 FROM PUBLIC" -qc "REVOKE TEMP ON DATABASE m30 FROM tally_app" -qc "REVOKE TEMP ON DATABASE m30 FROM tally_core" >/dev/null
      docker cp "$TMP/m.sql" tally-pg:/tmp/m30.sql >/dev/null
      aout=$(docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d m30 -v ON_ERROR_STOP=1 -q -o /dev/null -f /tmp/m30.sql 2>&1); ast=$?
      if [ $ast -ne 0 ]; then
        if [ "${exp#APPLY:}" != "$exp" ] && echo "$aout" | grep -q -- "${exp#APPLY:}"; then got=$exp
        else got="APPLY ($(echo "$aout" | grep -m1 ERROR | cut -c1-160))"; fi
      else
        bout=$(docker exec tally-pg psql -U tally -d m30 -v ON_ERROR_STOP=1 -q -o /dev/null -f /tmp/b30m.sql 2>&1); bst=$?
        got=$(echo "$bout" | grep -m1 -o "FAIL [A-Za-z0-9]*" | cut -d' ' -f2)
        [ -z "$got" ] && [ $bst -ne 0 ] && got="UNLABELLED ($(echo "$bout" | grep -m1 ERROR | cut -c1-160))"
      fi ;;
  esac
  if [ "$got" = "$exp" ]; then echo "caught $1 at $got"; caught=$((caught + 1))
  elif [ -z "$got" ] || [ "$got" = "PRE:" ]; then echo "MISSED $1 (named $exp)"; fail=1
  else echo "WRONG CHECK $1: caught at $got, named $exp"; fail=1; fi
}

# --- preconditions (a real database's data)
mut "N1 existing rate item versions not refused" PRE:C1 \
  "        IF v > 0 THEN
            RAISE EXCEPTION 'v5.4.2-30 precondition: % rate item version(s)" "        IF false THEN
            RAISE EXCEPTION 'v5.4.2-30 precondition: % rate item version(s)"
mut "N2 an exemption naming no service not refused" PRE:C2 \
  "    IF v > 0 THEN
        RAISE EXCEPTION 'v5.4.2-30 precondition: % exemption(s)" "    IF false THEN
        RAISE EXCEPTION 'v5.4.2-30 precondition: % exemption(s)"
mut "N3 a state agency with no basis not refused" PRE:C3 \
  "        IF v > 0 THEN
            RAISE EXCEPTION 'v5.4.2-30 precondition: % state agenc(ies)" "        IF false THEN
            RAISE EXCEPTION 'v5.4.2-30 precondition: % state agenc(ies)"
mut "N4 the fact-kind repair run over existing fraction facts" PRE:C4 \
  "    IF EXISTS (SELECT 1 FROM public.place_facts WHERE fact_code = 'sales_tax_rate') THEN" "    IF false THEN"
mut "N5 the vocabulary guard left firing on origin only after the repair" F1b \
  "ALTER TABLE public.place_fact_kinds ENABLE ALWAYS TRIGGER a_enforce_place_vocabulary_immutable;" \
  "ALTER TABLE public.place_fact_kinds ENABLE TRIGGER a_enforce_place_vocabulary_immutable;"

# --- the levy's insert check: its six refusals
mut "N6 another utility's levy not refused" L18 \
  "    IF NOT public.is_platform_admin() AND (p_row ->> 'tenant_id')::uuid" "    IF false AND (p_row ->> 'tenant_id')::uuid"
mut "N7 a kind of place that levies no sales tax admitted" L3 \
  "    IF NOT coalesce(p_row ->> 'place_kind' = ANY (v_kinds), false) THEN" "    IF false THEN"
mut "N8 a place code with no place admitted" L4 \
  "    IF v_cover IS NULL OR NOT v_cover @> v_range THEN" "    IF false THEN"
mut "N9 a levy dated outside its place's dates admitted" L5 \
  "    IF v_cover IS NULL OR NOT v_cover @> v_range THEN" "    IF v_cover IS NULL THEN"
mut "N10 a rate of five decimals admitted" L6 \
  "    IF v_rate IS DISTINCT FROM round(v_rate, 4) THEN" "    IF false THEN"
mut "N11 tax on tax naming an unknown kind admitted" L9 \
  "        IF NOT EXISTS (SELECT 1 FROM public.tax_kinds t WHERE t.tax_kind = v_on) THEN" "        IF false THEN"
mut "N12 tax on tax naming the levy itself admitted" L10 \
  "        IF v_on = p_row ->> 'tax_kind' THEN" "        IF false THEN"

# --- reading as known at an instant
mut "N13 a row's end read as known from the start" Q3 \
  "SELECT CASE WHEN p_closed_at IS NOT NULL AND p_closed_at > p_at THEN NULL ELSE p_end END" "SELECT p_end"
# N14: read a day ago, the successor (recorded now) is seen beside the first
# rate, so Q3's read raises "2 rows" before Q4 is reached.
mut "N14 a levy recorded after the instant read" Q3 \
  "       AND t.created_at <= p_recorded_at
       AND daterange(t.effective_from" "       AND daterange(t.effective_from"
mut "N15 a membership recorded after the instant read" M2 \
  "       AND m.created_at <= p_recorded_at AND (m.voided_at IS NULL OR m.voided_at > p_recorded_at)" \
  "       AND (m.voided_at IS NULL OR m.voided_at > p_recorded_at)"
mut "N16 a membership voided after the instant dropped" M2 \
  "       AND m.created_at <= p_recorded_at AND (m.voided_at IS NULL OR m.voided_at > p_recorded_at)" \
  "       AND m.created_at <= p_recorded_at AND m.voided_at IS NULL"
mut "N17 a membership's end read as known from the start" M2 \
  "       AND daterange(m.valid_from, public.end_as_known(m.valid_to, m.closed_at, p_recorded_at), '[)') @> p_on" \
  "       AND daterange(m.valid_from, m.valid_to, '[)') @> p_on"
mut "N18 a premise's places read without a recorded instant" M5 \
  "    IF p_recorded_at IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = 'premise_places_as_of" "    IF false THEN
        RAISE EXCEPTION USING
            MESSAGE = 'premise_places_as_of"
mut "N19 a levy read without a recorded instant" Q6 \
  "       OR p_service_type IS NULL OR p_system_kind IS NULL OR p_on IS NULL OR p_recorded_at IS NULL THEN" \
  "       OR p_service_type IS NULL OR p_system_kind IS NULL OR p_on IS NULL THEN"

# --- rate item versions: required answers and the late-penalty base
mut "N20 a default left on taxability" T1 \
  "ALTER TABLE public.rate_item_versions ALTER COLUMN is_taxable_default DROP DEFAULT;" ""
mut "N21 the customer-type list unchecked against known types" T6 \
  "           AND (applies_to_customer_types <@ ARRAY[" "           AND (applies_to_customer_types IS NOT NULL OR applies_to_customer_types <@ ARRAY["
mut "N22 a tax admitted to the penalty base" P1 \
  "    IF NEW.is_a_tax THEN" "    IF false THEN"
mut "N23 the penalty-base guard not fired on insert" P1 \
  "CREATE TRIGGER b_enforce_late_penalty_base BEFORE INSERT OR UPDATE OF" "CREATE TRIGGER b_enforce_late_penalty_base BEFORE UPDATE OF"
mut "N24 a fee excluded from tax bases admitted to the penalty base" P4 \
  "    IF FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('rate_item_versions: rate item %s is a %s surcharge" "    IF false THEN
        RAISE EXCEPTION USING
            MESSAGE = format('rate_item_versions: rate item %s is a %s surcharge"
mut "N25 the other order: an exclusion admitted over a version in the penalty base" P6 \
  "    IF v > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('regulatory_surcharge_rules" "    IF false THEN
        RAISE EXCEPTION USING
            MESSAGE = format('regulatory_surcharge_rules"

# --- exemptions per service type
mut "N26 an exemption with no service types admitted" E1 \
  "    CHECK ((service_types IS NOT NULL) AND (cardinality(service_types) > 0)" "    CHECK ((cardinality(service_types) > 0)"
mut "N27 an empty service list admitted" E2 \
  " AND (cardinality(service_types) > 0) AND (array_position(service_types, NULL) IS NULL));" " AND (array_position(service_types, NULL) IS NULL));"
mut "N28 a NULL among the service types admitted" E2b \
  " AND (cardinality(service_types) > 0) AND (array_position(service_types, NULL) IS NULL));" " AND (cardinality(service_types) > 0));"
mut "N29 an exemption read as covering every service" E5 \
  "        WHERE p_service_type = ANY (cte.service_types)" "        WHERE true"
mut "N30 a line with no service type not refused" E6 \
  "    IF p_service_type IS NULL THEN" "    IF false THEN"

# --- a state agency's basis
mut "N31 a state agency with no basis admitted" A1 \
  "CHECK ((NOT is_state_agency) OR ((state_agency_basis IS NOT NULL) AND (state_agency_basis ~ '[[:alnum:]]'::text)));" \
  "CHECK ((NOT is_state_agency) OR (state_agency_basis ~ '[[:alnum:]]'::text));"
mut "N32 a basis of only a tab admitted" A2 \
  "CHECK ((NOT is_state_agency) OR ((state_agency_basis IS NOT NULL) AND (state_agency_basis ~ '[[:alnum:]]'::text)));" \
  "CHECK ((NOT is_state_agency) OR (state_agency_basis IS NOT NULL));"
mut "N33 a change of basis not logged" A5 \
  "    IF OLD.state_agency_basis IS DISTINCT FROM NEW.state_agency_basis THEN" "    IF false THEN"

echo "mutations-30: $caught of $n caught"
[ $fail -eq 0 ] && [ $caught -eq $n ]
