#!/usr/bin/env bash
# The preconditions of v5.4.2-30, on a real database's data. The battery runs
# on `tally`, which holds none of these rows, so it cannot see them: each case
# plants one row the patch must refuse to run over (as the owner, with
# triggers and foreign keys off, and the one ALWAYS guard in the way lifted
# and set back: the row's shape is all that matters), then
# strict-applies the patch and requires the refusal naming it.
#   C0  nothing planted: the patch applies
#   C1  a rate item version exists (its late-penalty base would be defaulted)
#   C2  an exemption names no service type
#   C3  a state agency exists with no basis
#   C4  a published sales_tax_rate fact exists (its value is a fraction; the
#       kind cannot move to percent in place)
# Prints "PASS Cn" or "FAIL Cn [admitted]" / "FAIL Cn [refused otherwise] …".
#   tests/v5.4.2-30/preconditions-30.sh [patch]    (uses m30p; one run at a time)
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
P=${1:-$ROOT/sql/v5.4.2-30-tax-levies-and-taxability.sql}
DB=m30p
trap 'docker exec tally-pg psql -U tally -d postgres -qc "DROP DATABASE IF EXISTS $DB" >/dev/null 2>&1' EXIT
docker cp "$P" tally-pg:/tmp/p30pre.sql >/dev/null
fail=0

T=00000000-0000-4000-8000-0000000030aa
C=00000000-0000-4000-8000-0000000030ca
REPLICA="SET session_replication_role = replica;"

# $1 case, $2 planted SQL (empty: none), $3 expected message fragment (empty: must apply)
case_() {
  docker exec tally-pg psql -U tally -d postgres -qc "DROP DATABASE IF EXISTS $DB" -qc "CREATE DATABASE $DB TEMPLATE tally" >/dev/null 2>&1 \
    || { echo "SETUP $1: clone"; fail=1; return; }
  docker exec tally-pg psql -U tally -d $DB -qc "REVOKE TEMP ON DATABASE $DB FROM PUBLIC" -qc "REVOKE TEMP ON DATABASE $DB FROM tally_app" -qc "REVOKE TEMP ON DATABASE $DB FROM tally_core" >/dev/null
  if [ -n "$2" ]; then
    pout=$(docker exec tally-pg psql -U tally -d $DB -v ON_ERROR_STOP=1 -q -c "BEGIN; $REPLICA $2 COMMIT;" 2>&1) \
      || { echo "SETUP $1: plant failed: $(echo "$pout" | grep -m1 ERROR)"; fail=1; return; }
  fi
  aout=$(docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg \
         psql -U tally -d $DB -v ON_ERROR_STOP=1 -q -o /dev/null -f /tmp/p30pre.sql 2>&1); ast=$?
  if [ -z "$3" ]; then
    if [ $ast -eq 0 ]; then echo "PASS $1"; else echo "FAIL $1 [refused] $(echo "$aout" | grep -m1 ERROR | cut -c1-160)"; fail=1; fi
  elif [ $ast -eq 0 ]; then echo "FAIL $1 [admitted]"; fail=1
  elif echo "$aout" | grep -q -- "$3"; then echo "PASS $1"
  else echo "FAIL $1 [refused otherwise] $(echo "$aout" | grep -m1 ERROR | cut -c1-160)"; fail=1; fi
}

TENANT="INSERT INTO public.tenants (id, name, slug) VALUES ('$T', 'Pre30', 'pre30');"
CUSTOMER="INSERT INTO public.customers (id, tenant_id, customer_number) VALUES ('$C', '$T', 'PRE30-C');"

case_ C0 "" ""
case_ C1 "$TENANT
  ALTER TABLE public.rate_item_versions DISABLE TRIGGER a0_enforce_reference_version_receipt;
  INSERT INTO public.rate_item_versions (tenant_id, rate_item_id, item_name, service_type, calculation_type, regulatory_class, effective_date, change_type)
  VALUES ('$T', public.uuid_generate_v4(), 'Customer charge', 'gas', 'fixed_monthly', 'regulated', DATE '2026-01-01', 'initial');
  ALTER TABLE public.rate_item_versions ENABLE ALWAYS TRIGGER a0_enforce_reference_version_receipt;" \
  "rate item version(s) exist"
case_ C2 "$TENANT $CUSTOMER
  INSERT INTO public.customer_tax_exemptions (tenant_id, customer_id, exemption_type, effective_start)
  VALUES ('$T', '$C', 'religious', DATE '2026-01-01');" \
  "exemption(s) name no service type"
case_ C3 "$TENANT
  INSERT INTO public.customers (id, tenant_id, customer_number, customer_type, is_state_agency) VALUES ('$C', '$T', 'PRE30-C', 'government', true);" \
  "have no documented basis"
case_ C4 "INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note)
  SELECT id, 'sales_tax_rate', to_jsonb(0.0625), DATE '2026-01-01', 'pre30 plant' FROM public.places
   WHERE kind_code = 'state' AND place_code = 'TX' AND effective_to IS NULL;" \
  "sales_tax_rate facts exist"

[ $fail -eq 0 ] && echo "preconditions-30: all pass"
exit $fail
