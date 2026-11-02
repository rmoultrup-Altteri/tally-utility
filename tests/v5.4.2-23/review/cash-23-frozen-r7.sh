#!/usr/bin/env bash
# v5.4.2-23: what one transaction cannot show — two writers on one source of
# money, one bill line, one ledger tree; a status move against a draw; the
# recorded order; the READ COMMITTED pins.
#   CR1  A applies 60 of a 70 payment and holds; B applies 40 more of it to
#        another line: waits on the source's lock, then is refused (cap).
#   CR2  A applies 40 to a 60 line and holds; B applies 30 more to it from
#        another payment: waits on the line's lock, then is refused (cap).
#   CR3  A applies a payment and holds; B writes the nsf row undoing its
#        posting entry: waits on the source's lock, then is refused (bounced
#        money still paying a bill; r2, Opus B2).
#   CR4  A's transaction begins, B applies to a line and commits, then A
#        applies to the same line: refused for retry (40001); the retry is
#        admitted.
#   CR5  A reverses 60 of a 100 charge and holds; B reverses 50 more: waits
#        on the tree's lock, then is refused (R-02 cap).
#   CR6  A reverses 30 of a bill's charge and holds; B voids the bill: waits
#        on the tree's lock, then reverses the 60 left (X3), not 90.
#   CR7  An application and a reversal under REPEATABLE READ are refused,
#        each by its own pin (the application is an operator's choice: a
#        rule-chosen one meets rule_row_cite's pin first).
#   CR8  A refunds 30 of a 50 payment and holds; B applies 30 of it: waits,
#        then is refused (the payment's money goes three ways, never past it).
# r2 (Codex B2, S4): each race the other way round, and the status moves'
# READ COMMITTED pin.
#   CR9  A writes a payment's nsf row and moves it to nsf, and holds; B
#        applies it: waits on the source's lock, then is refused (ended).
#   CR9b A writes only the nsf row, and holds; B applies the payment: waits,
#        then is refused (r3: nothing of its money stands; the cap).
#   CR10 A reverses a credit's credit_issued entry and voids it, and holds;
#        B applies the credit: waits, then is refused (ended).
#   CR11 A applies 40 of a 60 payment and holds; B refunds 30 of it: waits,
#        then is refused (cap).
#   CR12 A payment's and a credit's status move under REPEATABLE READ are
#        refused (25000).
#   CR13 r3 (refunded is not a status): A cancels a pending refund of a
#        whole payment and holds; B applies the payment: waits on the
#        payment's lock (the cancel takes it), then is admitted.
#   CR13b A's transaction begins, B cancels a pending refund of a whole
#        payment and commits, then A applies the payment: refused for retry
#        (40001: recorded before the refund left it); the retry is admitted.
# r3 (Fable S4; Kyle, K-10 2):
#   CR14 A's transaction begins, B posts a pending payment and commits, then
#        A applies it: refused for retry (40001: recorded before the payment
#        was posted); the retry is admitted.
#   CR15 A records a pending refund of a payment and holds; B writes the nsf
#        row returning the payment: waits on the payment's lock, then is
#        refused (a refund is waiting to go out).
#   CR15b A writes the nsf row and holds; B records a refund of the payment:
#        waits, then is refused (the cap: the money came back).
#   CR16 A posts a pending payment and holds; B applies it: waits on the
#        payment's lock (the move takes it), then is admitted.
#   CR17 A voids an overpayment credit holding a whole payment and holds; B
#        applies the payment: waits on the payment's lock (the void takes it,
#        Codex B7), then is admitted.
# r4 (Opus B3, Fable B1; Opus B2):
#   CR18 A applies an overpayment credit and holds; B writes the nsf row
#        returning the credit's payment: waits (r5: on the payment's lock,
#        which the credit's draw takes first), then is refused (applied).
#   CR18b A writes the nsf row returning a payment held as a credit and
#        holds; B applies the credit: waits, then is refused (the cap: what
#        the credit held went with the payment).
#   CR19 A voids a pending payment and holds; B writes its posting row:
#        waits on the payment's lock, then is refused (not pending).
# r5 (Fable B3):
#   CR20 A begins REPEATABLE READ and reads a pending payment; B voids it and
#        commits; A writes its posting row: refused (25000), and no row is
#        written: the read after the lock would come from A's snapshot.
#   CR20b The same for a credit's credit_issued row (B voids the credit).
# r5 (Opus B2, Fable S1, Codex B1; Opus B1):
#   CR21 A moves a refund whose check came back to nsf and holds; B writes a
#        row paying it out again under the return: waits on the refund's lock,
#        then is refused (a re-sent refund is a new refund).
#   CR22 A applies 40 of a 60 payment that holds a 20 overpayment credit and
#        holds; B applies the credit's 20: waits on the payment's lock (a
#        draw on the credit takes its payment's first), then is admitted.
# r6 (Opus B2, Fable B1; Fable S1):
#   CR23 A's transaction begins, B refunds the overpayment credit of A's
#        payment and commits, then A takes 10 back under the payment's
#        posting entry: refused for retry (40001: recorded before a draw on
#        the credit already counted); the retry is admitted, and the split
#        reads it after the refund (the take-back is the payment's).
#   CR23b The same with B creating the overpayment credit (a draw on the
#        payment).
#   CR24 A returns a refund of an escheated overpayment credit, moves it to
#        nsf, waits, then carries the money into a reissue; B gives money
#        back under the credit's payment: B waits on the payment's lock (the
#        move takes it first), no deadlock, A commits, and B is refused (it
#        would put money back on the escheated credit).
# r7 (Fable S1, Opus S1, Codex S1):
#   CR25 C holds an overpayment credit's lock (as its escheat move does); A
#        voids a reissue of it (whose id sorts first), B gives money back
#        under its payment. A takes the payment's lock first, so B waits on
#        A; C commits, A commits, B is admitted: no deadlock.
# Every two() leg checks that session B ITSELF was SEEN BLOCKED BY SESSION A
# (pg_blocking_pids, polled while A holds). CR4 orders its sessions by
# barriers (application_name, polled with pg_stat_clear_snapshot()).
# Setup failures exit 2. Runs against a THROWAWAY clone (it commits rows).
#   usage: cash-23.sh <db>      (default: r23)
set -uo pipefail
DB="${1:-r23}"
PSQL=(docker exec -i tally-pg psql -U tally -d "$DB" -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -q -At)

T=00000000-0000-4000-8000-0000000023f0
OP=00000000-0000-4000-8000-0000000023f1
C=00000000-0000-4000-8000-0000000023f2
LOC=00000000-0000-4000-8000-0000000023f3
CITY=00000000-0000-4000-8000-0000000023f4
TAR=00000000-0000-4000-8000-0000000023f5
I1=00000000-0000-4000-8000-000000002401
I2=00000000-0000-4000-8000-000000002402
I3=00000000-0000-4000-8000-000000002403
L11=00000000-0000-4000-8000-000000002411
L12=00000000-0000-4000-8000-000000002412
L21=00000000-0000-4000-8000-000000002421
L22=00000000-0000-4000-8000-000000002422
L31=00000000-0000-4000-8000-000000002431
L32=00000000-0000-4000-8000-000000002432
P3=00000000-0000-4000-8000-000000002463
P4=00000000-0000-4000-8000-000000002464
P5=00000000-0000-4000-8000-000000002465
P6=00000000-0000-4000-8000-000000002466
P7=00000000-0000-4000-8000-000000002467
P8=00000000-0000-4000-8000-000000002468
P9=00000000-0000-4000-8000-000000002469
P9B=00000000-0000-4000-8000-00000000246a
P10=00000000-0000-4000-8000-00000000246b
P11=00000000-0000-4000-8000-00000000246c
R11=00000000-0000-4000-8000-00000000246d
P12=00000000-0000-4000-8000-000000002501
P13=00000000-0000-4000-8000-000000002502
P14=00000000-0000-4000-8000-000000002503
E12=00000000-0000-4000-8000-000000002511
E13=00000000-0000-4000-8000-000000002512
E14=00000000-0000-4000-8000-000000002513
P15=00000000-0000-4000-8000-000000002504
E15=00000000-0000-4000-8000-000000002516
R15=00000000-0000-4000-8000-000000002522
P16=00000000-0000-4000-8000-000000002505
E16=00000000-0000-4000-8000-000000002517
P17=00000000-0000-4000-8000-000000002506
E17=00000000-0000-4000-8000-000000002518
AP17=00000000-0000-4000-8000-000000002531
K17=00000000-0000-4000-8000-000000002532
P18=00000000-0000-4000-8000-000000002507
E18=00000000-0000-4000-8000-000000002519
AP18=00000000-0000-4000-8000-000000002533
K18=00000000-0000-4000-8000-000000002534
P18B=00000000-0000-4000-8000-000000002508
E18B=00000000-0000-4000-8000-00000000251a
AP18B=00000000-0000-4000-8000-000000002535
K18B=00000000-0000-4000-8000-000000002536
P19=00000000-0000-4000-8000-000000002509
P20=00000000-0000-4000-8000-000000002540
K20=00000000-0000-4000-8000-000000002541
P21=00000000-0000-4000-8000-000000002542
R21=00000000-0000-4000-8000-000000002543
E21=00000000-0000-4000-8000-000000002544
E21R=00000000-0000-4000-8000-000000002545
E21N=00000000-0000-4000-8000-000000002546
P22=00000000-0000-4000-8000-000000002547
E22=00000000-0000-4000-8000-000000002548
AP22=00000000-0000-4000-8000-000000002549
K22=00000000-0000-4000-8000-00000000254a
P23=00000000-0000-4000-8000-000000002550
E23=00000000-0000-4000-8000-000000002551
AP23=00000000-0000-4000-8000-000000002552
K23=00000000-0000-4000-8000-000000002553
R23=00000000-0000-4000-8000-000000002554
E23R=00000000-0000-4000-8000-000000002555
E23T=00000000-0000-4000-8000-000000002556
P23B=00000000-0000-4000-8000-000000002557
E23B=00000000-0000-4000-8000-000000002558
AP23B=00000000-0000-4000-8000-000000002559
K23B=00000000-0000-4000-8000-00000000255a
P24=00000000-0000-4000-8000-000000002560
E24=00000000-0000-4000-8000-000000002561
AP24=00000000-0000-4000-8000-000000002562
K24=00000000-0000-4000-8000-000000002563
R24=00000000-0000-4000-8000-000000002564
E24R=00000000-0000-4000-8000-000000002565
EV24=00000000-0000-4000-8000-000000002566
E24T=00000000-0000-4000-8000-000000002567
E24N=00000000-0000-4000-8000-000000002568
P25=00000000-0000-4000-8000-000000002570
K25B=00000000-0000-4000-8000-000000002571
AP25=00000000-0000-4000-8000-000000002572
K25=00000000-0000-4000-8000-000000002573
E25=00000000-0000-4000-8000-000000002574
R25=00000000-0000-4000-8000-000000002575
E25R=00000000-0000-4000-8000-000000002576
E25N=00000000-0000-4000-8000-000000002577
E25T=00000000-0000-4000-8000-000000002578
I4=00000000-0000-4000-8000-000000002404
L41=00000000-0000-4000-8000-000000002441
L42=00000000-0000-4000-8000-000000002442
K1=00000000-0000-4000-8000-000000002471
K2=00000000-0000-4000-8000-000000002472
EK1=00000000-0000-4000-8000-000000002491
EK2=00000000-0000-4000-8000-000000002492
E6=00000000-0000-4000-8000-000000002486
E6N=00000000-0000-4000-8000-000000002487
CH=00000000-0000-4000-8000-000000002488
CHI2=00000000-0000-4000-8000-000000002489
A_OUT=$(mktemp); B_OUT=$(mktemp)
trap 'rm -f "$A_OUT" "$B_OUT"' EXIT
fail=0

SNAP_INPUTS="'{\"rate_schedule_id\":null,\"rate_schedule_version_id\":null,\"rate_schedule_code\":null,\"customer_type\":null,\"partial_period_policy\":null,\"items\":[]}', '{\"pga_factor\":null,\"btu_factor\":null,\"pressure_factor\":null,\"temperature_factor\":null,\"meter_multiplier\":null,\"factor_stack_intermediates\":{}}', '{\"applied\":false}', '{\"jurisdictions\":[],\"exemptions\":[],\"franchise_fees\":[]}', '{\"reads\":[]}'"
bill() {  # $1 bill, $2 number, $3 line 1 (gas 60), $4 line 2 (add-on 40)
cat <<SQL
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, amount_due)
VALUES ('$1', '$T', '$2', '$C', '$LOC', DATE '2026-03-01', '2026-02', DATE '2026-02-01', DATE '2026-02-28', DATE '2026-03-20', 100.00);
INSERT INTO public.invoice_line_items (id, tenant_id, invoice_id, line_order, service_type, charge_type, description, amount, rate, regulatory_class) VALUES
  ('$3', '$T', '$1', 0, 'gas', 'base_charge', 'Gas service', 60.00, 60.00, 'regulated'),
  ('$4', '$T', '$1', 1, 'general', 'misc', 'Add-on', 40.00, NULL, 'unregulated');
INSERT INTO public.invoice_calculation_snapshots
  (tenant_id, invoice_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
   rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
VALUES ('$T', '$1', DATE '2026-02-28', now(), 'v1', 'race23', $SNAP_INPUTS,
   jsonb_build_object('customer_id', '$C'::uuid, 'customer_class', null, 'location_id', '$LOC'::uuid, 'premise_zones', '{}'::jsonb),
   jsonb_build_object('period_start', DATE '2026-02-01', 'period_end', DATE '2026-02-28', 'days_in_period', 28, 'proration_policy', null),
   (SELECT jsonb_agg(jsonb_build_object('invoice_line_item_id', l.id, 'charge_type', l.charge_type, 'amount', l.amount)) FROM public.invoice_line_items l WHERE l.invoice_id = '$1'));
UPDATE public.invoices SET status = 'pending' WHERE id = '$1';
SQL
}
pay() {  # $1 id, $2 number, $3 amount
echo "('$1', '$T', '$2', '$C', DATE '2026-03-05', $3, 'check', DATE '2026-03-05', 'postmark')"
}
post() {  # $1 payment, $2 its posting entry, $3 amount (r2: a payment is born pending)
cat <<SQL
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id)
VALUES ('$2', '$T', '$C', DATE '2026-03-05', 'payment', 'posted', -$3, 'payment', '$1');
UPDATE public.payments SET status = 'posted', status_cause_id = '$2' WHERE id = '$1';
SQL
}

"${PSQL[@]}" >/tmp/r23setup.out 2>&1 <<SQL || { echo "SETUP FAIL: fixtures"; cat /tmp/r23setup.out; exit 2; }
BEGIN;
INSERT INTO public.tenants (id, name, slug) VALUES ('$T', 'Race23', 'race23');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES ('$OP', '$T', 'Op', 'op@race23.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES ('$C', '$T', 'R23-C', 'residential');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES ('$LOC', '$T', '$C', 'L', '1 Main', 'Austin', 'TX', '78701');
INSERT INTO public.places (id, kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
SELECT '$CITY', 'municipality', 'TX', 'TX-R23-CITY', 'Race City 23', s.id, DATE '2000-01-01', 'race-23 fixture' FROM public.places s WHERE s.kind_code = 'state' AND s.state_code = 'TX';
INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction, owning_place_id, effective_from, evidence_reference, evidence_date)
VALUES ('$T', 'gas', 'distribution', 'TX', 'municipal', false, '$CITY', DATE '2000-01-01', 'charter', DATE '2000-01-01');
INSERT INTO public.payment_allocation_tariffs (id, tenant_id, state_code, service_type, system_kind, effective_from, tariff_reference, terms_kind, terms_version, terms_source)
VALUES ('$TAR', '$T', 'TX', 'gas', 'distribution', DATE '2026-01-01', 'City tariff', 'payment_allocation_tariff', 1,
        '{"citation": "City tariff", "within_bill": {"strategy": "charge_type_order", "version": 1, "regulated": ["base_charge", "usage_charge", "surcharge", "minimum_bill_adjustment", "tax", "late_fee", "penalty", "deposit", "adjustment", "credit", "consolidated_summary"], "unregulated": ["adhoc", "misc"]}}');
$(bill "$I1" R23-I1 "$L11" "$L12")
$(bill "$I2" R23-I2 "$L21" "$L22")
$(bill "$I3" R23-I3 "$L31" "$L32")
$(bill "$I4" R23-I4 "$L41" "$L42")
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method) VALUES
  $(pay "$P3" R23-P3 70), $(pay "$P4" R23-P4 100), $(pay "$P5" R23-P5 100), $(pay "$P6" R23-P6 50), $(pay "$P7" R23-P7 50), $(pay "$P8" R23-P8 100),
  $(pay "$P9" R23-P9 50), $(pay "$P9B" R23-P9B 50), $(pay "$P10" R23-P10 60), $(pay "$P11" R23-P11 40),
  $(pay "$P12" R23-P12 30), $(pay "$P13" R23-P13 40), $(pay "$P14" R23-P14 40), $(pay "$P15" R23-P15 20),
  $(pay "$P16" R23-P16 25), $(pay "$P17" R23-P17 30), $(pay "$P18" R23-P18 30), $(pay "$P18B" R23-P18B 30), $(pay "$P19" R23-P19 15), $(pay "$P20" R23-P20 40),
  $(pay "$P21" R23-P21 50), $(pay "$P22" R23-P22 60), $(pay "$P23" R23-P23 60), $(pay "$P23B" R23-P23B 60), $(pay "$P24" R23-P24 100);
$(post "$P3" 00000000-0000-4000-8000-000000002483 70)
$(post "$P4" 00000000-0000-4000-8000-000000002484 100)
$(post "$P5" 00000000-0000-4000-8000-000000002485 100)
$(post "$P6" "$E6" 50)
$(post "$P7" 00000000-0000-4000-8000-00000000248a 50)
$(post "$P8" 00000000-0000-4000-8000-00000000248b 100)
$(post "$P9" 00000000-0000-4000-8000-00000000248c 50)
$(post "$P9B" 00000000-0000-4000-8000-00000000248d 50)
$(post "$P10" 00000000-0000-4000-8000-00000000248e 60)
$(post "$P11" 00000000-0000-4000-8000-00000000248f 40)
$(post "$P13" "$E13" 40)
$(post "$P14" "$E14" 40)
$(post "$P15" "$E15" 20)
$(post "$P17" "$E17" 30)
INSERT INTO public.customer_credit_approvals (id, tenant_id, customer_id, payment_id, amount, approved_by) VALUES ('$AP17', '$T', '$C', '$P17', 30, '$OP');
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id, approval_id)
VALUES ('$K17', '$T', '$C', 'overpayment', 30, DATE '2026-03-05', '$P17', '$AP17');
$(post "$P18" "$E18" 30)
$(post "$P18B" "$E18B" 30)
INSERT INTO public.customer_credit_approvals (id, tenant_id, customer_id, payment_id, amount, approved_by) VALUES ('$AP18', '$T', '$C', '$P18', 30, '$OP'), ('$AP18B', '$T', '$C', '$P18B', 30, '$OP');
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id, approval_id) VALUES
  ('$K18', '$T', '$C', 'overpayment', 30, DATE '2026-03-05', '$P18', '$AP18'),
  ('$K18B', '$T', '$C', 'overpayment', 30, DATE '2026-03-05', '$P18B', '$AP18B');
$(post "$P21" "$E21" 50)
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_payment_id)
VALUES ('$R21', '$T', 'R23-R21', '$C', DATE '2026-03-06', -30, 'refund', '$P21');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id)
VALUES ('$E21R', '$T', '$C', DATE '2026-03-06', 'refund', 'refund out', 30, 'payment', '$R21');
UPDATE public.payments SET status = 'posted', status_cause_id = '$E21R', effective_date = DATE '2026-03-06', effective_date_method = 'other' WHERE id = '$R21';
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id)
VALUES ('$E21N', '$T', '$C', DATE '2026-03-07', 'nsf', 'refund check returned', -30, '$E21R');
$(post "$P22" "$E22" 60)
INSERT INTO public.customer_credit_approvals (id, tenant_id, customer_id, payment_id, amount, approved_by) VALUES ('$AP22', '$T', '$C', '$P22', 20, '$OP');
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id, approval_id)
VALUES ('$K22', '$T', '$C', 'overpayment', 20, DATE '2026-03-05', '$P22', '$AP22');
$(post "$P23" "$E23" 60)
INSERT INTO public.customer_credit_approvals (id, tenant_id, customer_id, payment_id, amount, approved_by) VALUES ('$AP23', '$T', '$C', '$P23', 20, '$OP'), ('$AP23B', '$T', '$C', '$P23B', 60, '$OP');
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id, approval_id)
VALUES ('$K23', '$T', '$C', 'overpayment', 20, DATE '2026-03-05', '$P23', '$AP23');
$(post "$P23B" "$E23B" 60)
$(post "$P24" "$E24" 100)
INSERT INTO public.customer_credit_approvals (id, tenant_id, customer_id, payment_id, amount, approved_by) VALUES ('$AP24', '$T', '$C', '$P24', 100, '$OP');
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id, approval_id)
VALUES ('$K24', '$T', '$C', 'overpayment', 100, DATE '2026-03-05', '$P24', '$AP24');
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_customer_credit_id)
VALUES ('$R24', '$T', 'R23-R24', '$C', DATE '2026-03-06', -30, 'refund', '$K24');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id)
VALUES ('$E24R', '$T', '$C', DATE '2026-03-06', 'refund', 'refund out', 30, 'payment', '$R24');
UPDATE public.payments SET status = 'posted', status_cause_id = '$E24R', effective_date = DATE '2026-03-06', effective_date_method = 'other' WHERE id = '$R24';
INSERT INTO public.escheatment_events (id, tenant_id, customer_credit_id, customer_id, event_type, amount_related) VALUES ('$EV24', '$T', '$K24', '$C', 'escheated_to_state', 70);
UPDATE public.customer_credits SET status = 'escheated', status_cause_id = '$EV24' WHERE id = '$K24';
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id)
VALUES ('$E24T', '$T', '$C', DATE '2026-03-07', 'adjustment', 'taken back', 10, '$E24');
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_payment_id)
VALUES ('$R11', '$T', 'R23-R11', '$C', DATE '2026-03-06', -40, 'refund', '$P11'),
       ('$R15', '$T', 'R23-R15', '$C', DATE '2026-03-06', -20, 'refund', '$P15');
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date) VALUES
  ('$K1', '$T', '$C', 'goodwill', 30, DATE '2026-03-05'),
  ('$K2', '$T', '$C', 'goodwill', 20, DATE '2026-03-05'),
  ('$K20', '$T', '$C', 'goodwill', 15, DATE '2026-03-05');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES
  ('$EK1', '$T', '$C', DATE '2026-03-05', 'credit_issued', 'K1', -30, 'customer_credit', '$K1'),
  ('$EK2', '$T', '$C', DATE '2026-03-05', 'credit_issued', 'K2', -20, 'customer_credit', '$K2'),
  ('$CH', '$T', '$C', DATE '2026-03-01', 'charge', 'a charge', 100, NULL, NULL),
  ('$CHI2', '$T', '$C', DATE '2026-03-01', 'charge', 'I2', 90, 'invoice', '$I2');
COMMIT;
SQL

waiting() {
local n i
for i in 1 2 3 4 5 6 7 8 9 10; do
  n=$(docker exec -i tally-pg psql -U tally -d "$DB" -At -c "SELECT count(*) FROM pg_stat_activity b JOIN pg_stat_activity a ON a.datname = b.datname AND a.application_name = 'race23_a' WHERE b.datname = current_database() AND b.application_name = 'race23_b' AND a.pid = ANY (pg_blocking_pids(b.pid))" 2>/dev/null)
  if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ]; then echo 1; return; fi
  sleep 0.15
done
echo 0
}
AS_OP="SET LOCAL app.user_id = '$OP'; SET ROLE tally_app;"
apply() {  # $1 payment, $2 line, $3 bill, $4 amount, $5 date
echo "INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, allocation_tariff_id) VALUES ('$T', '$C', '$3', '$2', '$1', $4, DATE '${5:-2026-03-07}', 'oldest_first', '$TAR');"
}
applyc() {  # $1 credit, $2 line, $3 bill, $4 amount
echo "INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, customer_credit_id, amount, applied_on, basis, allocation_tariff_id) VALUES ('$T', '$C', '$3', '$2', '$1', $4, DATE '2026-03-07', 'oldest_first', '$TAR');"
}
nsf() {  # $1 nsf row, $2 payment, $3 its posting entry, $4 amount
echo "INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id) VALUES ('$1', '$T', '$C', DATE '2026-03-09', 'nsf', 'returned', $4, 'payment', '$2', '$3');"
}
reverse() {  # $1 entry, $2 amount, $3 description
echo "INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES ('$T', '$C', DATE '2026-03-07', 'adjustment', '$3', $2, '$1', 'race');"
}

two() {  # $1 A's statement, $2 B's statement
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
SET application_name = 'race23_a';
BEGIN;
$AS_OP
$1
SELECT pg_sleep(3);
COMMIT;
SQL
APID=$!
sleep 1
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL &
SET application_name = 'race23_b';
BEGIN;
$AS_OP
$2
COMMIT;
SQL
BPID=$!
sleep 1
WAITED=$(waiting)
wait $APID; AST=$?
wait $BPID; BST=$?
OUT=$(cat "$B_OUT")
}
verdict() {  # $1 label, $2 want B to fail (1) or pass (0), $3 expected fragment when it fails
if [ "${AST:-0}" -ne 0 ]; then echo "FAIL $1: session A itself failed: $(cat "$A_OUT")"; fail=1; return; fi
if [ "${WAITED:-0}" -lt 1 ]; then echo "FAIL $1: session B was never seen waiting on a lock"; fail=1; return; fi
if [ "$2" = 1 ]; then
  if [ "$BST" -ne 0 ] && echo "$OUT" | grep -q "$3"; then echo "PASS $1"; else echo "FAIL $1: expected B refused with '$3', got ($BST): $OUT"; fail=1; fi
else
  if [ "$BST" -eq 0 ]; then echo "PASS $1"; else echo "FAIL $1: expected B to pass, got: $OUT"; fail=1; fi
fi
}
expect() {  # $1 label, $2 actual, $3 expected
if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], expected [$3]"; fail=1; fi
}

# CR1
two "$(apply "$P3" "$L11" "$I1" 60)" "$(apply "$P3" "$L12" "$I1" 40)"
verdict "CR1 two draws on one payment: the second waits on the source, then is refused by its cap" 1 "more than its 70"

# CR2
two "$(apply "$P4" "$L21" "$I2" 40)" "$(apply "$P5" "$L21" "$I2" 30)"
verdict "CR2 two applications to one line: the second waits on the line, then is refused by its cap" 1 "more than the line"

# CR3
two "$(apply "$P6" "$L22" "$I2" 10)" "$(nsf "$E6N" "$P6" "$E6" 50)"
verdict "CR3 a payment applied while it bounces: the nsf row waits on the source, then is refused" 1 "while the payment is applied to bills"

# CR4: A's transaction begins before B's application and applies after it.
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
SET application_name = 'race23_a_begun';
BEGIN;
$AS_OP
SELECT now();
DO \$\$ BEGIN
  LOOP
    PERFORM pg_stat_clear_snapshot();
    EXIT WHEN EXISTS (SELECT 1 FROM pg_stat_activity WHERE application_name = 'race23_b_done');
    PERFORM pg_sleep(0.1);
  END LOOP;
END \$\$;
$(apply "$P8" "$L31" "$I3" 10)
COMMIT;
SQL
APID=$!
for _ in $(seq 1 100); do
  [ "$(docker exec -i tally-pg psql -U tally -d "$DB" -At -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'race23_a_begun'")" = "1" ] && break; sleep 0.1
done
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL
BEGIN;
$AS_OP
$(apply "$P5" "$L31" "$I3" 10)
COMMIT;
SET application_name = 'race23_b_done';
SELECT pg_sleep(2);
SQL
wait $APID; AST=$?
if [ "$AST" -ne 0 ] && grep -q "40001" "$A_OUT" && grep -q "retry it" "$A_OUT"; then echo "PASS CR4 a writer that began before an application now on the line is refused for retry"
else echo "FAIL CR4: A ($AST): $(cat "$A_OUT")"; fail=1; fi
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN;
$AS_OP
$(apply "$P8" "$L31" "$I3" 10)
COMMIT;
SQL
)
if [ $? -eq 0 ]; then echo "PASS CR4b the retry is admitted"; else echo "FAIL CR4b: $OUT"; fail=1; fi

# CR5
two "$(reverse "$CH" -60 'R1')" "$(reverse "$CH" -50 'R2')"
verdict "CR5 two reversals of one charge: the second waits on the tree, then is refused by the cap" 1 "R-02 cap"

# CR6
two "$(reverse "$CHI2" -30 'I2 less 30')" "SELECT public.void_invoice('$I2', '$OP', 'wrong_rate', NULL, true);"
verdict "CR6 a void while a reversal of its charge is in flight waits on the tree, then reverses what is left" 0
expect "CR6b the void reversed 60, not 90" \
  "$("${PSQL[@]}" -c "SELECT amount FROM public.account_ledger WHERE reverses_ledger_entry_id = '$CHI2' AND transaction_type = 'void_reversal'")" "-60.00"

# CR7
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN ISOLATION LEVEL REPEATABLE READ;
$AS_OP
INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, applied_by, reason) VALUES ('$T', '$C', '$I3', '$L32', '$P8', 1, DATE '2026-03-07', 'operator_override', '$OP', 'race');
COMMIT;
SQL
)
if echo "$OUT" | grep -q "25000" && echo "$OUT" | grep -q "a row drawing on"; then echo "PASS CR7 an application under REPEATABLE READ is refused"; else echo "FAIL CR7: $OUT"; fail=1; fi
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN ISOLATION LEVEL REPEATABLE READ;
$AS_OP
$(reverse "$CH" -1 'RR')
COMMIT;
SQL
)
if echo "$OUT" | grep -q "25000" && echo "$OUT" | grep -q "is posted at READ COMMITTED"; then echo "PASS CR7b a reversal under REPEATABLE READ is refused"; else echo "FAIL CR7b: $OUT"; fail=1; fi

# CR8
REFUND="INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method, refunds_payment_id) VALUES ('$T', 'R23-REF', '$C', DATE '2026-03-06', -30, 'refund', DATE '2026-03-06', 'other', '$P7');"
two "$REFUND" "$(apply "$P7" "$L32" "$I3" 30)"
verdict "CR8 a refund in flight and an application of the same payment: the application waits, then is refused" 1 "more than its 50"

# CR9
E9=00000000-0000-4000-8000-00000000248c; E9N=00000000-0000-4000-8000-00000000249c
two "$(nsf "$E9N" "$P9" "$E9" 50) UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-09', status_cause_id = '$E9N' WHERE id = '$P9';" "$(apply "$P9" "$L12" "$I1" 5)"
verdict "CR9 a payment bounced while an application of it is in flight: the application waits, then is refused" 1 "money is drawn from a posted payment"

# CR9b
E9B=00000000-0000-4000-8000-00000000248d; E9BN=00000000-0000-4000-8000-00000000249d
two "$(nsf "$E9BN" "$P9B" "$E9B" 50)" "$(apply "$P9B" "$L12" "$I1" 5)"
verdict "CR9b its nsf row alone, in flight: the application waits, then is refused (r3: nothing of its money stands)" 1 "R-06 cap"

# CR10
EK1R=00000000-0000-4000-8000-00000000249e
two "INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES ('$EK1R', '$T', '$C', DATE '2026-03-07', 'adjustment', 'K1 withdrawn', 30, '$EK1', 'race'); UPDATE public.customer_credits SET status = 'voided', status_cause_id = '$EK1R' WHERE id = '$K1';" \
    "$(applyc "$K1" "$L12" "$I1" 5)"
verdict "CR10 a credit voided while an application of it is in flight: the application waits, then is refused" 1 "money is drawn from a posted payment"

# CR11
two "$(apply "$P10" "$L32" "$I3" 40)" "INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method, refunds_payment_id) VALUES ('$T', 'R23-REF10', '$C', DATE '2026-03-08', -30, 'refund', DATE '2026-03-08', 'other', '$P10');"
verdict "CR11 an application in flight and a refund of the same payment: the refund waits, then is refused" 1 "more than its 60"

# CR12
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN ISOLATION LEVEL REPEATABLE READ;
$AS_OP
UPDATE public.payments SET status = 'reversed' WHERE id = '$P8';
COMMIT;
SQL
)
if echo "$OUT" | grep -q "25000" && echo "$OUT" | grep -q "a status move is written at READ COMMITTED"; then echo "PASS CR12 a payment's status move under REPEATABLE READ is refused"; else echo "FAIL CR12: $OUT"; fail=1; fi
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN ISOLATION LEVEL REPEATABLE READ;
$AS_OP
UPDATE public.customer_credits SET status = 'voided' WHERE id = '$K2';
COMMIT;
SQL
)
if echo "$OUT" | grep -q "25000" && echo "$OUT" | grep -q "a status move is written at READ COMMITTED"; then echo "PASS CR12b a credit's status move under REPEATABLE READ is refused"; else echo "FAIL CR12b: $OUT"; fail=1; fi

# CR13
two "UPDATE public.payments SET status = 'voided' WHERE id = '$R11';" "$(apply "$P11" "$L12" "$I1" 10)"
verdict "CR13 a payment applied while its whole refund is being cancelled: the application waits, then is admitted" 0

# CR13b: A's transaction begins before B cancels the refund, and applies after it.
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
SET application_name = 'race23_a_begun13';
BEGIN;
$AS_OP
SELECT now();
DO \$\$ BEGIN
  LOOP
    PERFORM pg_stat_clear_snapshot();
    EXIT WHEN EXISTS (SELECT 1 FROM pg_stat_activity WHERE application_name = 'race23_b_done13');
    PERFORM pg_sleep(0.1);
  END LOOP;
END \$\$;
$(apply "$P15" "$L12" "$I1" 5)
COMMIT;
SQL
APID=$!
for _ in $(seq 1 100); do
  [ "$(docker exec -i tally-pg psql -U tally -d "$DB" -At -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'race23_a_begun13'")" = "1" ] && break; sleep 0.1
done
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL
BEGIN;
$AS_OP
UPDATE public.payments SET status = 'voided' WHERE id = '$R15';
COMMIT;
SET application_name = 'race23_b_done13';
SELECT pg_sleep(2);
SQL
wait $APID; AST=$?
if [ "$AST" -ne 0 ] && grep -q "40001" "$A_OUT" && grep -q "left it" "$A_OUT"; then echo "PASS CR13b an application begun before a refund of its payment was cancelled is refused for retry"
else echo "FAIL CR13b: A ($AST): $(cat "$A_OUT") / B: $(cat "$B_OUT")"; fail=1; fi
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN;
$AS_OP
$(apply "$P15" "$L12" "$I1" 5)
COMMIT;
SQL
)
if [ $? -eq 0 ]; then echo "PASS CR13c the retry is admitted"; else echo "FAIL CR13c: $OUT"; fail=1; fi

# CR14: A's transaction begins before B posts the payment, and applies it after.
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
SET application_name = 'race23_a_begun14';
BEGIN;
$AS_OP
SELECT now();
DO \$\$ BEGIN
  LOOP
    PERFORM pg_stat_clear_snapshot();
    EXIT WHEN EXISTS (SELECT 1 FROM pg_stat_activity WHERE application_name = 'race23_b_done14');
    PERFORM pg_sleep(0.1);
  END LOOP;
END \$\$;
$(apply "$P12" "$L12" "$I1" 5)
COMMIT;
SQL
APID=$!
for _ in $(seq 1 100); do
  [ "$(docker exec -i tally-pg psql -U tally -d "$DB" -At -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'race23_a_begun14'")" = "1" ] && break; sleep 0.1
done
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL
BEGIN;
$AS_OP
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id)
VALUES ('$E12', '$T', '$C', DATE '2026-03-05', 'payment', 'posted', -30, 'payment', '$P12');
UPDATE public.payments SET status = 'posted', status_cause_id = '$E12' WHERE id = '$P12';
COMMIT;
SET application_name = 'race23_b_done14';
SELECT pg_sleep(2);
SQL
wait $APID; AST=$?
if [ "$AST" -ne 0 ] && grep -q "40001" "$A_OUT" && grep -q "before the payment was posted" "$A_OUT"; then echo "PASS CR14 an application begun before its payment was posted is refused for retry (Fable S4)"
else echo "FAIL CR14: A ($AST): $(cat "$A_OUT") / B: $(cat "$B_OUT")"; fail=1; fi
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN;
$AS_OP
$(apply "$P12" "$L12" "$I1" 5)
COMMIT;
SQL
)
if [ $? -eq 0 ]; then echo "PASS CR14b the retry is admitted"; else echo "FAIL CR14b: $OUT"; fail=1; fi

# CR15, CR15b
two "INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_payment_id) VALUES ('$T', 'R23-REF13', '$C', DATE '2026-03-08', -10, 'refund', '$P13');" \
    "$(nsf 00000000-0000-4000-8000-000000002514 "$P13" "$E13" 40)"
verdict "CR15 a refund pending and the payment's bounce in flight: the bounce waits, then is refused (K-10 2)" 1 "waiting to go out"
two "$(nsf 00000000-0000-4000-8000-000000002515 "$P14" "$E14" 40)" \
    "INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_payment_id) VALUES ('$T', 'R23-REF14', '$C', DATE '2026-03-10', -10, 'refund', '$P14');"
verdict "CR15b a bounce in flight and a refund of the same payment: the refund waits, then is refused (the money came back)" 1 "R-06 cap"

# CR16
two "INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES ('$E16', '$T', '$C', DATE '2026-03-05', 'payment', 'posted', -25, 'payment', '$P16'); UPDATE public.payments SET status = 'posted', status_cause_id = '$E16' WHERE id = '$P16';" \
    "$(apply "$P16" "$L12" "$I1" 5)"
verdict "CR16 a payment applied while it is being posted: the application waits, then is admitted" 0

# CR17
two "UPDATE public.customer_credits SET status = 'voided' WHERE id = '$K17';" "$(apply "$P17" "$L12" "$I1" 5)"
verdict "CR17 a payment applied while the overpayment credit holding it is voided: the application waits, then is admitted (Codex B7)" 0

# CR18, CR18b, CR19
two "$(applyc "$K18" "$L12" "$I1" 3)" "$(nsf 00000000-0000-4000-8000-00000000251b "$P18" "$E18" 30)"
verdict "CR18 a payment's bounce while its overpayment credit is being applied: the bounce waits, then is refused" 1 "while the payment is applied to bills"
two "$(nsf 00000000-0000-4000-8000-00000000251c "$P18B" "$E18B" 30)" "$(applyc "$K18B" "$L12" "$I1" 3)"
verdict "CR18b an overpayment credit applied while its payment bounces: the application waits, then is refused (what it held went with the payment)" 1 "R-06 cap"
two "UPDATE public.payments SET status = 'voided' WHERE id = '$P19';" "INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES ('$T', '$C', DATE '2026-03-05', 'payment', 'late', -15, 'payment', '$P19');"
verdict "CR19 a payment's posting row written while the payment is voided: it waits, then is refused (Opus B2)" 1 "still pending"

# CR20, CR20b: A's snapshot is taken before B's void; A writes after it.
rr_arrival() {  # $1 label, $2 A's read, $3 B's void, $4 A's row, $5 the row's count afterwards
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
BEGIN ISOLATION LEVEL REPEATABLE READ;
$AS_OP
$2
SELECT pg_sleep(2);
$4
COMMIT;
SQL
APID=$!
sleep 1
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL
BEGIN;
$AS_OP
$3
COMMIT;
SQL
BST=$?
wait $APID; AST=$?
if [ "$BST" -ne 0 ]; then echo "FAIL $1: B's void failed: $(cat "$B_OUT")"; fail=1; return; fi
if [ "$AST" -ne 0 ] && grep -q "25000" "$A_OUT" && grep -q "is posted at READ COMMITTED" "$A_OUT" \
   && [ "$("${PSQL[@]}" -c "$5")" = 0 ]; then echo "PASS $1"; else echo "FAIL $1: ($AST) $(cat "$A_OUT")"; fail=1; fi
}
rr_arrival "CR20 a posting row at REPEATABLE READ for a payment voided after the snapshot is refused (Fable B3)" \
  "SELECT status FROM public.payments WHERE id = '$P20';" \
  "UPDATE public.payments SET status = 'voided' WHERE id = '$P20';" \
  "INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES ('$T', '$C', DATE '2026-03-05', 'payment', 'late', -40, 'payment', '$P20');" \
  "SELECT count(*) FROM public.account_ledger WHERE reference_id = '$P20'"
rr_arrival "CR20b a credit_issued row at REPEATABLE READ for a credit voided after the snapshot is refused (Fable B3)" \
  "SELECT status FROM public.customer_credits WHERE id = '$K20';" \
  "UPDATE public.customer_credits SET status = 'voided' WHERE id = '$K20';" \
  "INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES ('$T', '$C', DATE '2026-03-05', 'credit_issued', 'late', -15, 'customer_credit', '$K20');" \
  "SELECT count(*) FROM public.account_ledger WHERE reference_id = '$K20'"

# CR21, CR22
two "UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-07', status_cause_id = '$E21N' WHERE id = '$R21';" \
    "INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id) VALUES ('$T', '$C', DATE '2026-03-08', 'adjustment', 're-sent', 30, '$E21N');"
verdict "CR21 a refund paid out again under its return while it moves to nsf: the row waits on the refund, then is refused (Opus B2)" 1 "a re-sent refund is a new refund"
two "$(apply "$P22" "$L41" "$I4" 40)" "$(applyc "$K22" "$L42" "$I4" 20)"
verdict "CR22 an overpayment credit applied while its payment is: the credit's draw waits on the payment, then is admitted (r5)" 0


# CR23, CR23b: A's transaction begins before B's draw on the payment or its
# credit, and A writes a row under the payment's posting entry after it.
begun() {  # $1 tag, $2 A's statement (after its transaction began), $3 B's statements
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
SET application_name = 'race23_a_begun$1';
BEGIN;
$AS_OP
SELECT now();
DO \$\$ BEGIN
  LOOP
    PERFORM pg_stat_clear_snapshot();
    EXIT WHEN EXISTS (SELECT 1 FROM pg_stat_activity WHERE application_name = 'race23_b_done$1');
    PERFORM pg_sleep(0.1);
  END LOOP;
END \$\$;
$2
COMMIT;
SQL
APID=$!
for _ in $(seq 1 100); do
  [ "$(docker exec -i tally-pg psql -U tally -d "$DB" -At -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'race23_a_begun$1'")" = "1" ] && break; sleep 0.1
done
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL
BEGIN;
$AS_OP
$3
COMMIT;
SET application_name = 'race23_b_done$1';
SELECT pg_sleep(2);
SQL
wait $APID; AST=$?
}
TAKE23="INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id) VALUES ('$E23T', '$T', '$C', DATE '2026-03-07', 'adjustment', 'taken back', 10, '$E23');"
begun 23 "$TAKE23" "INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_customer_credit_id) VALUES ('$R23', '$T', 'R23-R23', '$C', DATE '2026-03-06', -20, 'refund', '$K23');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES ('$E23R', '$T', '$C', DATE '2026-03-06', 'refund', 'refund out', 20, 'payment', '$R23');
UPDATE public.payments SET status = 'posted', status_cause_id = '$E23R', effective_date = DATE '2026-03-06', effective_date_method = 'other' WHERE id = '$R23';"
if [ "$AST" -ne 0 ] && grep -q "40001" "$A_OUT" && grep -q "a row under its payment's posting entry" "$A_OUT"; then echo "PASS CR23 a take-back begun before a refund of the payment's credit is refused for retry (Opus B2, Fable B1)"
else echo "FAIL CR23: A ($AST): $(cat "$A_OUT") / B: $(cat "$B_OUT")"; fail=1; fi
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN;
$AS_OP
$TAKE23
COMMIT;
SQL
)
if [ $? -eq 0 ]; then echo "PASS CR23a the retry is admitted"; else echo "FAIL CR23a: $OUT"; fail=1; fi
expect "CR23b the split reads the retry after the refund: the payment 30, the credit 0 (not 40 and -10)" \
  "$("${PSQL[@]}" -c "SELECT (SELECT remaining FROM public.payment_position_as_of('$P23', DATE '2026-12-31', clock_timestamp())) || ' ' || (SELECT remaining FROM public.customer_credit_position_as_of('$K23', DATE '2026-12-31', clock_timestamp()))")" "30.00 0.00"
begun 23c "INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id) VALUES ('$T', '$C', DATE '2026-03-07', 'adjustment', 'taken back', 10, '$E23B');" \
  "INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id, approval_id) VALUES ('$K23B', '$T', '$C', 'overpayment', 60, DATE '2026-03-05', '$P23B', '$AP23B');"
if [ "$AST" -ne 0 ] && grep -q "40001" "$A_OUT" && grep -q "a row under its posting entry" "$A_OUT"; then echo "PASS CR23c a take-back begun before the payment's overpayment credit was created is refused for retry (Fable RR-B)"
else echo "FAIL CR23c: A ($AST): $(cat "$A_OUT") / B: $(cat "$B_OUT")"; fail=1; fi

# CR24 (Fable RR-D): the return, the move and the reissue in one transaction,
# against a give-back under the credit's payment.
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
SET application_name = 'race23_a';
BEGIN;
$AS_OP
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id) VALUES ('$E24N', '$T', '$C', DATE '2026-03-08', 'nsf', 'refund check returned', -30, '$E24R');
UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-08', status_cause_id = '$E24N' WHERE id = '$R24';
SELECT pg_sleep(3);
INSERT INTO public.customer_credits (tenant_id, customer_id, origin_type, original_amount, issued_date, reissues_refund_id) VALUES ('$T', '$C', 'refund_reissue', 20, DATE '2026-03-08', '$R24');
COMMIT;
SQL
APID=$!
sleep 1
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL &
SET application_name = 'race23_b';
BEGIN;
$AS_OP
INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id) VALUES ('$T', '$C', DATE '2026-03-08', 'adjustment', 'cleared after all', -10, '$E24T');
COMMIT;
SQL
BPID=$!
sleep 1
WAITED=$(waiting)
wait $APID; AST=$?
wait $BPID; BST=$?
OUT=$(cat "$B_OUT")
if grep -q "40P01" "$A_OUT" "$B_OUT"; then echo "FAIL CR24: a deadlock: A: $(cat "$A_OUT") / B: $OUT"; fail=1
else verdict "CR24 a give-back while a returned refund of the escheated credit is moved and reissued: it waits on the payment, no deadlock, then is refused (Fable S1)" 1 "nothing comes back to an escheated credit"
fi

# CR25 (Fable RR-E, Opus D): a reissue's void against a give-back under its
# payment. Setup, committed: payment 100, credit K 100, K's refund of 30 out,
# back and reissued as K2 (its id below K's), 10 taken back (K's share).
"${PSQL[@]}" >/dev/null <<SQL || { echo "CR25 setup failed"; exit 2; }
BEGIN;
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method) VALUES $(pay "$P25" R23-P25 100);
$(post "$P25" "$E25" 100)
INSERT INTO public.customer_credit_approvals (id, tenant_id, customer_id, payment_id, amount, approved_by) VALUES ('$AP25', '$T', '$C', '$P25', 100, '$OP');
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id, approval_id)
VALUES ('$K25', '$T', '$C', 'overpayment', 100, DATE '2026-03-05', '$P25', '$AP25');
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_customer_credit_id)
VALUES ('$R25', '$T', 'R23-R25', '$C', DATE '2026-03-06', -30, 'refund', '$K25');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id)
VALUES ('$E25R', '$T', '$C', DATE '2026-03-06', 'refund', 'refund out', 30, 'payment', '$R25');
UPDATE public.payments SET status = 'posted', status_cause_id = '$E25R', effective_date = DATE '2026-03-06', effective_date_method = 'other' WHERE id = '$R25';
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id) VALUES ('$E25N', '$T', '$C', DATE '2026-03-07', 'nsf', 'refund check returned', -30, '$E25R');
UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-07', status_cause_id = '$E25N' WHERE id = '$R25';
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, reissues_refund_id) VALUES ('$K25B', '$T', '$C', 'refund_reissue', 30, DATE '2026-03-07', '$R25');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id)
VALUES ('$E25T', '$T', '$C', DATE '2026-03-08', 'adjustment', 'taken back', 10, '$E25');
COMMIT;
SQL
C_OUT=$(mktemp)
"${PSQL[@]}" >"$C_OUT" 2>&1 <<SQL &
SET application_name = 'race23_c';
BEGIN;
SELECT pg_advisory_xact_lock(public.cash_source_lock_key('credit', '$K25'));
SELECT pg_sleep(3);
COMMIT;
SQL
CPID=$!
sleep 0.5
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
SET application_name = 'race23_a';
BEGIN;
$AS_OP
UPDATE public.customer_credits SET status = 'voided' WHERE id = '$K25B';
COMMIT;
SQL
APID=$!
sleep 0.5
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL &
SET application_name = 'race23_b';
BEGIN;
$AS_OP
INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id) VALUES ('$T', '$C', DATE '2026-03-09', 'adjustment', 'cleared after all', -10, '$E25T');
COMMIT;
SQL
BPID=$!
sleep 1
WAITED=$(waiting)
wait $CPID
wait $APID; AST=$?
wait $BPID; BST=$?
OUT=$(cat "$B_OUT")
rm -f "$C_OUT"
if grep -q "40P01" "$A_OUT" "$B_OUT"; then echo "FAIL CR25: a deadlock: A: $(cat "$A_OUT") / B: $OUT"; fail=1
else verdict "CR25 a reissue's void and a give-back under its payment take their locks in one order: B waits on A, no deadlock, both admitted (Fable S1, Opus S1)" 0
fi

exit $fail
