#!/usr/bin/env bash
# v5.4.2-15 (R-D2): the "one live due row per deposit" and "no due row on a
# returned deposit" guards are counts, so they race. Both serialise on the
# deposit row (FOR UPDATE), the lock every deposit event takes. Two sessions:
#   R1  A writes a due row and holds; B's due row for the same deposit waits,
#       then is refused (unique_violation) when A commits.
#   R2  A writes the refund and holds; B's due row waits, then is refused
#       (the deposit is refunded) when A commits.
# Runs against a THROWAWAY clone (it commits rows).
#   usage: due-mutex-15.sh <db>      (default: s15)
set -uo pipefail
DB="${1:-s15}"
PSQL=(docker exec -i tally-pg psql -U tally -d "$DB" -v ON_ERROR_STOP=1 -q -At)

T=00000000-0000-4000-8000-0000000015a8
U=00000000-0000-4000-8000-0000000015b8
C=00000000-0000-4000-8000-0000000015c8
L=00000000-0000-4000-8000-0000000015d8
R=00000000-0000-4000-8000-0000000015f8
I=00000000-0000-4000-8000-0000000015e9
D1=00000000-0000-4000-8000-000000001501
D2=00000000-0000-4000-8000-000000001502

"${PSQL[@]}" <<SQL >/dev/null
INSERT INTO public.tenants (id, name, slug) VALUES ('$T', 'Race Gasco', 'race15-$RANDOM$RANDOM');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES ('$U', '$T', 'OpR', 'opr$RANDOM@race15.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES ('$C', '$T', 'RACE-C', 'residential');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip)
  VALUES ('$L', '$T', '$C', 'L', '1 Main', 'Austin', 'TX', '78701');
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end)
  VALUES ('$R', '$T', 'R-RACE', '2026-03', DATE '2026-03-01', DATE '2026-03-31');
INSERT INTO public.invoices (id, tenant_id, invoice_number, billing_run_id, customer_id, location_id, invoice_type,
       invoice_date, billing_period, period_start, period_end, due_date, amount_due)
  VALUES ('$I', '$T', 'RACE-1', '$R', '$C', '$L', 'regular', DATE '2026-04-01', '2026-03', DATE '2026-03-01', DATE '2026-03-31', DATE '2026-04-21', 50);
INSERT INTO public.deposits (id, tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type,
                             customer_class, rule_id, cap_amount, cap_basis_kind, cap_basis_amount, decided_by)
SELECT d.id, '$T', '$C', 'credit_evaluation', 'cash', 100, DATE '2026-02-01', 'TX', 'gas', 'residential', r.id,
       100, 'fraction_of_annual_billing', 600, 'core-test'
  FROM (VALUES ('$D1'::uuid), ('$D2'::uuid)) AS d(id),
       (SELECT id FROM public.deposit_rules WHERE state_code = 'TX' AND service_type = 'gas' AND customer_class = 'residential'
           AND basis = 'credit_evaluation' AND effective_to IS NULL) r;
SQL

due_sql() {  # $1 due id, $2 deposit id, $3 seconds to hold before commit
cat <<SQL
BEGIN;
SET LOCAL app.user_id = '$U';
SET ROLE tally_app;
INSERT INTO public.deposit_return_due (id, tenant_id, deposit_id, rule_id, due_on, inputs, inputs_fingerprint, calculated_by)
SELECT '$1', '$T', d.id, d.rule_id, DATE '2026-04-02', '{}', 'fp', 'core-test' FROM public.deposits d WHERE d.id = '$2';
INSERT INTO public.deposit_return_due_evidence (tenant_id, due_id, reason_code, invoice_id, classification)
VALUES ('$T', '$1', 'clean_bill_history', '$I', 'clean');
SELECT pg_sleep($3);
COMMIT;
SQL
}

fail=0
A_OUT=$(mktemp); B_OUT=$(mktemp); trap 'rm -f "$A_OUT" "$B_OUT"' EXIT
# R1: two due rows for D1.
due_sql 00000000-0000-4000-8000-0000000015a1 "$D1" 3 | "${PSQL[@]}" >"$A_OUT" 2>&1 &
sleep 1
OUT=$(due_sql 00000000-0000-4000-8000-0000000015a2 "$D1" 0 | "${PSQL[@]}" 2>&1)
wait
N=$(echo "SELECT count(*) FROM public.deposit_return_due WHERE deposit_id = '$D1'" | "${PSQL[@]}")
if grep -q "already has a live due row" <<<"$OUT" && [ "$N" = "1" ]; then
  echo "PASS R1: a second session's due row waits on the deposit row and is refused once the first commits (1 live row)"
else
  echo "FAIL R1: rows=$N; B said: $OUT"; fail=1
fi

# R2: a refund in flight against a new due row for D2.
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL &
BEGIN;
SET LOCAL app.user_id = '$U';
SET ROLE tally_app;
INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on)
VALUES ('$T', '$D2', 'refunded', 100, DATE '2026-04-01');
SELECT pg_sleep(3);
COMMIT;
SQL
sleep 1
OUT=$(due_sql 00000000-0000-4000-8000-0000000015a3 "$D2" 0 | "${PSQL[@]}" 2>&1)
wait
if grep -q "is already refunded" <<<"$OUT"; then
  echo "PASS R2: a due row racing a refund waits, then sees the deposit refunded and is refused"
else
  echo "FAIL R2: B said: $OUT (A: $(cat "$B_OUT"))"; fail=1
fi
exit $fail
