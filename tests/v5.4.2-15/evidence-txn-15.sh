#!/usr/bin/env bash
# v5.4.2-15 (R-D2): a return-due row's evidence is written only in the due
# row's own transaction. Needs two committed transactions, so it cannot live
# in the one-transaction battery. Runs against a THROWAWAY clone (it commits
# rows that append-only tables will not let it remove).
#   usage: evidence-txn-15.sh <db>      (default: s15)
set -euo pipefail
DB="${1:-s15}"
PSQL=(docker exec -i tally-pg psql -U tally -d "$DB" -v ON_ERROR_STOP=1 -q -At)

T=00000000-0000-4000-8000-0000000015a7
U=00000000-0000-4000-8000-0000000015b7
C=00000000-0000-4000-8000-0000000015c7
L=00000000-0000-4000-8000-0000000015d7
R=00000000-0000-4000-8000-0000000015f7
I1=00000000-0000-4000-8000-0000000015e7
I2=00000000-0000-4000-8000-0000000015e6
DUE=00000000-0000-4000-8000-0000000015dd

# Fixture (owner), committed: a tenant, customer, two bills.
"${PSQL[@]}" <<SQL
INSERT INTO public.tenants (id, name, slug) VALUES ('$T', 'TXN Gasco', 'txn15-$RANDOM$RANDOM');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES ('$U', '$T', 'OpT', 'opt$RANDOM@txn15.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES ('$C', '$T', 'TXN-C', 'residential');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip)
  VALUES ('$L', '$T', '$C', 'L', '1 Main', 'Austin', 'TX', '78701');
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end)
  VALUES ('$R', '$T', 'R-TXN', '2026-03', DATE '2026-03-01', DATE '2026-04-30');
INSERT INTO public.invoices (id, tenant_id, invoice_number, billing_run_id, customer_id, location_id, invoice_type,
       invoice_date, billing_period, period_start, period_end, due_date, amount_due) VALUES
  ('$I1', '$T', 'TXN-1', '$R', '$C', '$L', 'regular', DATE '2026-04-01', '2026-03', DATE '2026-03-01', DATE '2026-03-31', DATE '2026-04-21', 50),
  ('$I2', '$T', 'TXN-2', '$R', '$C', '$L', 'regular', DATE '2026-05-01', '2026-04', DATE '2026-04-01', DATE '2026-04-30', DATE '2026-05-21', 50);
SQL

# Transaction 1, as tally_app: a deposit, a due row and one evidence row — committed.
"${PSQL[@]}" <<SQL
BEGIN;
SET LOCAL app.user_id = '$U';
SET ROLE tally_app;
WITH r AS (SELECT id FROM public.deposit_rules WHERE state_code = 'TX' AND service_type = 'gas'
             AND customer_class = 'residential' AND basis = 'credit_evaluation' AND effective_to IS NULL),
     d AS (INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type,
                                        customer_class, rule_id, cap_amount, cap_basis_kind, cap_basis_amount, cap_source, decided_by)
           SELECT '$T', '$C', 'credit_evaluation', 'cash', 100, DATE '2026-02-01', 'TX', 'gas', 'residential', r.id,
                  100, 'fraction_of_annual_billing', 600, 'statute', 'core-test' FROM r RETURNING id, rule_id)
INSERT INTO public.deposit_return_due (id, tenant_id, deposit_id, rule_id, due_on, inputs, inputs_fingerprint, calculated_by)
SELECT '$DUE', '$T', d.id, d.rule_id, DATE '2026-05-02', '{}', 'fp', 'core-test' FROM d;
INSERT INTO public.deposit_return_due_evidence (tenant_id, due_id, reason_code, invoice_id, classification)
VALUES ('$T', '$DUE', 'clean_bill_history', '$I1', 'clean');
COMMIT;
SQL

# Transaction 2: more evidence for the committed due row must be refused.
OUT=$("${PSQL[@]}" 2>&1 <<SQL || true
BEGIN;
SET LOCAL app.user_id = '$U';
SET ROLE tally_app;
INSERT INTO public.deposit_return_due_evidence (tenant_id, due_id, reason_code, invoice_id, classification)
VALUES ('$T', '$DUE', 'clean_bill_history', '$I2', 'clean');
COMMIT;
SQL
)
if grep -q "was recorded in an earlier transaction" <<<"$OUT"; then
  echo "PASS X1: evidence for a due row committed earlier is refused (its evidence is complete)"
else
  echo "FAIL X1: later evidence was not refused: $OUT"
  exit 1
fi
