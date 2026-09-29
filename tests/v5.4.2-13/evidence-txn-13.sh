#!/usr/bin/env bash
# v5.4.2-13 (parity): an evaluation's evidence is written only in the
# evaluation's own transaction. Needs two committed transactions, so it cannot
# live in the one-transaction battery. Runs against a THROWAWAY clone (it
# commits rows that append-only tables will not let it remove).
#   usage: evidence-txn-13.sh <db>      (default: a2p)
set -euo pipefail
DB="${1:-a2p}"
PSQL=(docker exec -i tally-pg psql -U tally -d "$DB" -v ON_ERROR_STOP=1 -q -At)

T=00000000-0000-4000-8000-0000000013a7
U=00000000-0000-4000-8000-0000000013b7
C=00000000-0000-4000-8000-0000000013c7
L=00000000-0000-4000-8000-0000000013d7
M=00000000-0000-4000-8000-0000000013e7

# Transaction 1: fixture, a case and an evaluation — committed.
EV=$("${PSQL[@]}" <<SQL
INSERT INTO public.tenants (id, name, slug) VALUES ('$T', 'TXN Gasco', 'txn13-$RANDOM$RANDOM');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES ('$U', '$T', 'OpT', 'opt$RANDOM@txn13.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES ('$C', '$T', 'TXN-C', 'residential');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip)
  VALUES ('$L', '$T', '$C', 'L', '1 Main', 'Austin', 'TX', '78701');
INSERT INTO public.meters (id, tenant_id, meter_number, location_id, service_type, start_date, status)
  VALUES ('$M', '$T', 'M-TXN', '$L', 'gas', DATE '2024-01-01', 'active');
BEGIN;
SET LOCAL app.user_id = '$U';
SET ROLE tally_app;
WITH c AS (
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, anchor_date, anchor_basis, claimed_from)
  VALUES ('$T', '$M', 'crossed_meters', DATE '2026-05-01', 'discovery_date', DATE '2026-01-01') RETURNING id)
INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, cause, anchor_date, anchor_basis, claimed_from,
       rule_id, approval_required, inputs, inputs_fingerprint, calculated_by)
SELECT '$T', c.id, 'crossed_meters', DATE '2026-05-01', 'discovery_date', DATE '2026-01-01',
       (SELECT id FROM public.backbilling_rules WHERE state_code = 'TX' AND service_type = 'gas'
          AND customer_class = 'protected' AND cause = 'crossed_meters' AND effective_to IS NULL),
       false, '{}', 'fp', 'core-0.0.0'
  FROM c RETURNING id;
COMMIT;
SQL
)
EV=$(echo "$EV" | grep -E '^[0-9a-f-]{36}$' | tail -1)

# A bill on the meter to cite.
INV=$("${PSQL[@]}" <<SQL
INSERT INTO public.billing_runs (tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at)
  VALUES ('$T', 'R-TXN', '2026-04', '2026-04-01', '2026-04-30', 'regular', 'in_progress', now()) RETURNING id \gset
INSERT INTO public.invoices (tenant_id, invoice_number, billing_run_id, customer_id, location_id, invoice_type,
       invoice_date, billing_period, period_start, period_end, due_date, amount_due)
  VALUES ('$T', 'TXN-1', :'id', '$C', '$L', 'regular', DATE '2026-05-01', '2026-04', DATE '2026-04-01', DATE '2026-04-30',
          DATE '2026-05-21', 50) RETURNING id;
SQL
)
INV=$(echo "$INV" | grep -E '^[0-9a-f-]{36}$' | tail -1)

# Transaction 2: evidence for the committed evaluation must be refused.
OUT=$("${PSQL[@]}" 2>&1 <<SQL || true
BEGIN;
SET LOCAL app.user_id = '$U';
SET ROLE tally_app;
INSERT INTO public.meter_correction_period_evidence (tenant_id, evaluation_id, invoice_id, customer_id,
       period_start, period_end, customer_class, rule_id, direction, correction_amount, disposition, days_in_window)
SELECT '$T', '$EV', '$INV', '$C', DATE '2026-04-01', DATE '2026-04-30', 'protected', v.rule_id,
       'customer_owes', 5.00, 'included', 30
  FROM public.meter_correction_evaluations v WHERE v.id = '$EV';
COMMIT;
SQL
)
if echo "$OUT" | grep -q "was recorded in an earlier transaction"; then
  echo "PASS X1: evidence cannot be added to an evaluation after its own transaction committed"
else
  echo "FAIL X1: $OUT"; exit 1
fi
