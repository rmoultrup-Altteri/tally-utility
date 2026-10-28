#!/usr/bin/env python3
"""v5.4.2-23 — prove the -23 checks CATCH drift, not merely pass.

Each mutation alters a copy of the patch, applies it (strict: search_path ''
and function-body checking on) to a fresh clone of `tally` with TEMP revoked,
and runs the script that owns the named check:

  battery check (T A M C X LC F I)  battery-23.sql
  b22:<check>                       battery-22.sql (the -22 rows -23 re-reads)
  CR1-CR19                          races/cash-23.sh
  APPLY:<phrase>                    the patch itself must refuse (its tail runs
                                    the invariants), with that phrase

CAUGHT only when the FIRST failure printed is the named check's (the -21
rule). A mutation an EARLIER check catches is reported as missed: its named
check is wrong, or a guard is redundant — fix the name or remove the
duplicate, never loosen the rule.

    python3 tests/v5.4.2-23/mutations-23.py [N01 N12 ...]
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[2]
PATCH = ROOT / "sql/v5.4.2-23-cash-reversals-positions-application.sql"
HERE = ROOT / "tests/v5.4.2-23"
DB = "m23"


def rep(old: str, new: str) -> Callable[[str], str]:
    def m(s: str) -> str:
        assert s.count(old) == 1, f"mutation anchor not unique/found ({s.count(old)}): {old[:90]!r}"
        return s.replace(old, new, 1)
    return m


def tail(sql: str) -> Callable[[str], str]:
    """Append statements just before the patch's own invariant run."""
    return rep("    PERFORM public.assert_cash_guard_invariants();\n    PERFORM public.assert_periods_guard_invariants();",
               "    NULL;\nEND $$;\n" + sql + "\nDO $$ BEGIN\n    PERFORM public.assert_cash_guard_invariants();\n    PERFORM public.assert_periods_guard_invariants();")


# Anchors that occur more than once carry the message line that follows them.
TREE_CHOSEN = "    IF FOUND AND NEW.created_at <> pg_catalog.now() THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('ledger tree %s"
TREE_RETRY = "    IF FOUND THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('ledger tree %s: %s is recorded at %s, before"
LINE_RETRY = "    IF FOUND THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('line %s: application %s is recorded at %s, before"
PAY_CAUSE = ("        IF NEW.status_cause_id IS DISTINCT FROM OLD.status_cause_id\n"
             "           OR (NEW.status_recorded_at IS DISTINCT FROM OLD.status_recorded_at AND NOT v_super) THEN\n"
             "            RAISE EXCEPTION USING\n                MESSAGE = format('payment %s: status_cause_id")
PAY_STAMP = "        NEW.status_recorded_at := pg_catalog.now();\n    END IF;\n    -- Forward only: pending to posted or voided"
APP = "        WHEN 'application' THEN v_status IN ('posted', 'active') AND NOT v_deposit"

MUTATIONS = [
    # ---- X: reversals
    ("N01", "a ledger row may be recorded in the future", "X2g",
     rep("    IF NOT pg_catalog.isfinite(NEW.created_at) OR NEW.created_at > pg_catalog.clock_timestamp() THEN",
         "    IF NOT pg_catalog.isfinite(NEW.created_at) THEN")),
    ("N02", "a recovery may name a charge", "b22:R2",
     rep("    IF NEW.transaction_type = 'write_off_recovery' AND v_parent.transaction_type <> 'write_off' THEN", "    IF false THEN")),
    ("N03", "an adjustment may name a write-off", "b22:R7",
     rep("    IF v_parent.transaction_type = 'write_off' AND NEW.transaction_type <> 'write_off_recovery' THEN", "    IF false THEN")),
    ("N04", "a reversal may have the entry's sign", "X2",
     rep("    IF NOT ((NEW.amount > 0 AND v_parent.amount < 0) OR (NEW.amount < 0 AND v_parent.amount > 0)) THEN",
         "    IF NEW.amount = 0 THEN")),
    ("N05", "a reversal may be dated before its entry", "X2b",
     rep("    IF NEW.transaction_date < v_parent.transaction_date THEN", "    IF false THEN")),
    ("N06", "a reversal at REPEATABLE READ", "CR7b",
     rep("    IF (NEW.reverses_ledger_entry_id IS NOT NULL\n", "    IF (false\n")),
    ("N07", "a reversal takes no tree lock", "CR5",
     rep("    PERFORM pg_catalog.pg_advisory_xact_lock(public.ledger_tree_lock_key(v_root.id));\n", "")),
    ("N08", "a history row with a chosen time is let in before its tree", "X2h",
     rep(TREE_CHOSEN, TREE_CHOSEN.replace("IF FOUND AND NEW.created_at <> pg_catalog.now() THEN", "IF false THEN"))),
    ("N09", "a writer that began earlier posting later is not told to retry", "b22:R12i",
     rep(TREE_RETRY, TREE_RETRY.replace("IF FOUND THEN", "IF false THEN"))),
    ("N10", "the cap holds only at the parent, not at every entry on the path", "X2e",
     rep("     WHERE n.net < least(0, -v_down_amt[n.j]) OR n.net > greatest(0, -v_down_amt[n.j])\n",
         "     WHERE (n.net < least(0, -v_down_amt[n.j]) OR n.net > greatest(0, -v_down_amt[n.j])) AND n.j = cardinality(v_down)\n")),
    ("N11", "the cap nets the whole tree, not at every date", "X2f",
     rep("sum(t.amount) OVER (PARTITION BY j.j ORDER BY t.on_date) AS net", "sum(t.amount) OVER (PARTITION BY j.j) AS net")),
    ("N12", "reversals may total more than the entry", "X2c",
     rep("     WHERE n.net < least(0, -v_down_amt[n.j]) OR n.net > greatest(0, -v_down_amt[n.j])",
         "     WHERE n.net > greatest(0, -v_down_amt[n.j])")),
    ("N13", "the rows under an entry may net past nothing (recoveries past the write-off)", "b22:R6",
     rep("     WHERE n.net < least(0, -v_down_amt[n.j]) OR n.net > greatest(0, -v_down_amt[n.j])",
         "     WHERE n.net < least(0, -v_down_amt[n.j])")),
    ("N14", "the cap's walk loses its plan settings", "APPLY:lost its plan settings",
     rep("CREATE OR REPLACE FUNCTION public.enforce_ledger_reversal() RETURNS trigger\n    LANGUAGE plpgsql\n    SET search_path = public, pg_temp\n    SET enable_seqscan = off\n",
         "CREATE OR REPLACE FUNCTION public.enforce_ledger_reversal() RETURNS trigger\n    LANGUAGE plpgsql\n    SET search_path = public, pg_temp\n")),
    ("N15", "the reversal FK is dropped", "APPLY:a v5.4.2-23 constraint is missing",
     tail("ALTER TABLE public.account_ledger DROP CONSTRAINT account_ledger_reverses_ledger_entry_fkey;")),
    # ---- X3: the void
    ("N16", "the void reverses the amount due, not what is left", "X3",
     rep("        v_reversal_amount := -public.ledger_entry_remaining(v_original_ledger_entry_id);",
         "        v_reversal_amount := -v_invoice.amount_due;")),
    ("N17", "a fully reversed charge voids with a zero row", "X3c",
     rep("        IF v_reversal_amount = 0 THEN\n            v_reversal_amount := NULL;\n        END IF;\n", "")),
    ("N18", "the void takes no tree lock", "CR6",
     rep("        PERFORM pg_catalog.pg_advisory_xact_lock(public.ledger_tree_lock_key(public.ledger_tree_root(v_original_ledger_entry_id)));\n", "")),
    # ---- M: positions
    ("N19", "a position needs no coordinates", "M1e",
     rep("    PERFORM public.cash_coordinates_required('payment_position_as_of', p_on, p_recorded_at);\n", "")),
    ("N20", "a payment position reads applications at any money date", "M1c",
     rep("WHERE a.payment_id = p.id AND a.applied_on <= p_on AND a.created_at <= p_recorded_at", "WHERE a.payment_id = p.id AND a.created_at <= p_recorded_at")),
    ("N21", "a payment position reads applications at any recorded instant", "M1j",
     rep("WHERE a.payment_id = p.id AND a.applied_on <= p_on AND a.created_at <= p_recorded_at", "WHERE a.payment_id = p.id AND a.applied_on <= p_on")),
    ("N22", "a line's open amount counts a credit line", "M1g",
     rep("    SELECT l.amount, x.applied, greatest(l.amount, 0) - x.applied", "    SELECT l.amount, x.applied, l.amount - x.applied")),
    ("N23", "a payment position forgets its credits", "C1j",
     rep("x.received - x.applied - x.credited - x.refunded", "x.received - x.applied - x.refunded")),
    # ---- M2, M3: write-once and status moves
    ("N24", "a payment's amount is not fixed", "M2",
     rep("ARRAY['id', 'tenant_id', 'payment_number', 'customer_id', 'payment_date', 'amount',", "ARRAY['id', 'tenant_id', 'payment_number', 'customer_id', 'payment_date',")),
    ("N25", "a later reference may be rewritten", "M2c",
     rep("        IF v_old -> v_col <> 'null'::jsonb AND v_new -> v_col IS DISTINCT FROM v_old -> v_col THEN", "        IF false THEN")),
    ("N26", "a payment's restriction is not fixed", "M2d",
     rep("        'restricted_to_line_item_id', 'nsf_original_payment_id',", "        'nsf_original_payment_id',")),
    ("N27", "a payment's cause may change without its status", "M3e",
     rep(PAY_CAUSE, PAY_CAUSE.replace("IF NEW.status_cause_id IS DISTINCT FROM OLD.status_cause_id\n", "IF false\n"))),
    ("N28", "a posted payment may return to pending", "M3d",
     rep("            OR (OLD.status = 'posted' AND NEW.status IN ('nsf', 'reversed'))) THEN",
         "            OR (OLD.status = 'posted' AND NEW.status IN ('nsf', 'reversed', 'pending'))) THEN")),
    ("N29", "a move to posted names nothing", "M3",
     rep("        WHEN 'posted' THEN EXISTS (", "        WHEN 'posted' THEN NEW.status_cause_id IS NULL OR EXISTS (")),
    ("N30", "a move to posted may name another payment's entry", "M3b",
     rep("AND l.reference_type = 'payment' AND l.reference_id = NEW.id AND l.amount = -NEW.amount\n",
         "AND l.reference_type = 'payment'\n")),
    ("N31", "bounced money still pays bills", "M3f2",
     rep("    IF NEW.status IN ('nsf', 'reversed', 'voided') THEN", "    IF false THEN")),
    ("N32", "a payment's move takes no source lock", "CR19",
     rep("    PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('payment', OLD.id));\n", "")),
    ("N33", "a refund that leaves takes no lock on its source", "CR13",
     rep("        IF OLD.refunds_payment_id IS NOT NULL THEN\n            PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('payment', OLD.refunds_payment_id));\n",
         "        IF OLD.refunds_payment_id IS NOT NULL THEN\n")),
    ("N34", "a credit is voided while applied", "M3h2",
     rep("    IF NEW.status = 'voided' AND v_left <> 0 THEN", "    IF false THEN")),
    ("N35", "a one-off charge's class is not fixed", "M2g",
     rep("        IF NEW.regulatory_class IS DISTINCT FROM OLD.regulatory_class THEN v_changed := v_changed || ARRAY['regulatory_class']; END IF;\n", "")),
    ("N36", "a line classed against its one-off charge wrongly is issued", "LC1",
     rep("        IF v_class <> p_line.regulatory_class THEN\n            RETURN format('it is %s, its one-off charge", "        IF false THEN\n            RETURN format('it is %s, its one-off charge")),
    # ---- A3: the caps
    ("N37", "a draw at REPEATABLE READ", "CR7",
     rep("    IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('a row drawing",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('a row drawing")),
    ("N38", "a draw takes no source lock", "CR1",
     rep("    PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key(p_kind, p_id));\n", "")),
    ("N39", "a payment pays more than it is", "A3e",
     rep("         WHERE x.used > v_amount\n", "         WHERE x.used > v_amount + 1000000\n")),
    ("N40", "a refund does not draw on its payment", "C1l",
     rep("     WHERE r.status IN ('pending', 'posted')\n       AND ((p_kind = 'payment'", "     WHERE false\n       AND ((p_kind = 'payment'")),
    ("N41", "an overpayment credit does not draw on its payment", "C1l",
     rep("     WHERE p_kind = 'payment' AND c.source_payment_id = p_id AND c.status <> 'voided'\n    UNION ALL",
         "     WHERE false\n    UNION ALL")),
    ("N42", "an application takes no line lock", "CR2",
     rep("    PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('line', NEW.invoice_line_item_id));\n", "")),
    ("N43", "an application recorded before one on its line is not told to retry", "CR4",
     rep(LINE_RETRY, LINE_RETRY.replace("IF FOUND THEN", "IF false THEN"))),
    ("N44", "a line takes more than it is", "A3",
     rep("     WHERE x.net > greatest(v_line.amount, 0)\n", "     WHERE x.net > greatest(v_line.amount, 0) + 1000000\n")),
    ("N45", "an undo takes back more than the application", "A2d",
     rep("        IF v_net < 0 THEN", "        IF false THEN")),
    ("N46", "an undo may be of another payment", "A2i",
     rep("           OR v_undone.payment_id IS DISTINCT FROM NEW.payment_id\n", "")),
    ("N47", "an undo may be dated before what it undoes", "A2e",
     rep("        IF NEW.applied_on < v_undone.applied_on THEN", "        IF false THEN")),
    ("N48", "a draft bill takes money", "A3h",
     rep("        IF NOT public.is_invoice_issued(v_inv.status) OR v_inv.status = 'void' THEN", "        IF v_inv.status = 'void' THEN")),
    ("N49", "a void bill takes money", "X3d",
     rep("        IF NOT public.is_invoice_issued(v_inv.status) OR v_inv.status = 'void' THEN", "        IF NOT public.is_invoice_issued(v_inv.status) THEN")),
    ("N50", "a credit line takes money", "A3c",
     rep("        IF v_line.amount <= 0 THEN", "        IF false THEN")),
    ("N51", "a pending payment pays", "A3f",
     rep(APP, APP.replace("('posted', 'active')", "('posted', 'active', 'pending')"))),
    ("N52", "a deposit pays a bill", "A3g",
     rep(APP, APP.replace(" AND NOT v_deposit", ""))),
    ("N53", "a voided credit pays", "A3k",
     rep(APP, APP.replace("('posted', 'active')", "('posted', 'active', 'voided')"))),
    ("N54", "money is applied before it arrived", "A3i",
     rep("    IF p_purpose <> 'undo' AND p_on < v_date THEN", "    IF false THEN")),
    ("N55", "money is applied before its bill", "A3l",
     rep("        IF NEW.applied_on < v_inv.invoice_date THEN", "        IF false THEN")),
    # ---- A4-A6: basis, restriction, tariff
    ("N56", "a restricted payment is applied oldest first", "A4f",
     rep("           OR (NEW.basis = 'oldest_first' AND v_restricted)\n", "")),
    ("N57", "an unrestricted payment says restriction", "A4e",
     rep("        IF (NEW.basis = 'restriction' AND NOT v_in_target)\n           OR", "        IF false\n           OR")),
    ("N58", "the floor takes an unregulated line", "A4i",
     rep("AND NOT (v_restricted AND NOT v_in_target AND v_line.regulatory_class = 'regulated'", "AND NOT (v_restricted AND NOT v_in_target")),
    ("N59", "a rule-chosen application cites no tariff in force", "A4c",
     rep("            PERFORM public.rule_row_cite('public.payment_allocation_tariffs'::regclass, NEW.allocation_tariff_id, NEW.applied_on);\n", "")),
    ("N60", "an overpayment credit draws on a pending payment", "C1m2",
     rep("        WHEN 'overpayment_credit' THEN p_kind = 'payment' AND v_status = 'posted'",
         "        WHEN 'overpayment_credit' THEN p_kind = 'payment' AND v_status IN ('posted', 'pending')")),
    ("N61", "a refund or credit draw skips the source cap", "C1k2",
     rep("        PERFORM public.check_cash_source('payment', NEW.source_payment_id, NEW.created_at, 'overpayment_credit', NEW.issued_date);", "        NULL;")),
    ("N62", "applications are not frozen", "APPLY:a v5.4.2-23 guard is missing",
     rep("CREATE TRIGGER a_enforce_accounting_freeze BEFORE INSERT ON public.invoice_applications\n    FOR EACH ROW EXECUTE FUNCTION public.enforce_accounting_freeze('applied_on');\nALTER TABLE public.invoice_applications ENABLE ALWAYS TRIGGER a_enforce_accounting_freeze;\n", "")),
    # ---- T: the within-bill order
    ("N63", "an order may list a charge type twice", "T3",
     rep("          GROUP BY () HAVING count(*) > count(DISTINCT l.charge_type))), '')", "          GROUP BY () HAVING false)), '')")),
    ("N64", "an order may leave a charge type out", "T2",
     rep("          WHERE NOT EXISTS (SELECT 1 FROM listed l WHERE l.charge_type = e.charge_type)),", "          WHERE false),")),
    ("N65", "a utility may write another utility's tariff", "T6",
     rep("    IF NOT public.is_platform_admin() AND (p_row ->> 'tenant_id')::uuid IS DISTINCT FROM public.get_user_tenant_id()", "    IF false")),
    # ---- the shapes and the seal
    ("N66", "a customer payment may carry a restriction", "APPLY:a v5.4.2-23 constraint is missing",
     rep("        CHECK ((restricted_to_invoice_id IS NULL OR payer_class = 'agency')", "        CHECK ((true)")),
    ("N67", "the application may edit an application", "APPLY:both are add-only",
     tail("GRANT UPDATE ON public.invoice_applications TO tally_app;")),
    ("N68", "one approval may make two credits", "APPLY:unique index is missing",
     rep("CREATE UNIQUE INDEX customer_credits_one_per_approval ON public.customer_credits (approval_id) WHERE approval_id IS NOT NULL;\n",
         "CREATE INDEX customer_credits_one_per_approval ON public.customer_credits (approval_id) WHERE approval_id IS NOT NULL;\n")),
    ("N69", "a counter comes back as a column", "APPLY:is a column again",
     tail("ALTER TABLE public.payments ADD COLUMN applied_amount numeric;")),
    ("N70", "the cap's walk stops two short of the lineage bound (it fails closed)", "b22:R11b",
     rep("    c_max      CONSTANT integer := 1000;", "    c_max      CONSTANT integer := 998;")),
    ("N71", "the cap's walk stops short and takes the entry it reached for the root", "b22:R11e",
     lambda x: rep("    IF v_root.reverses_ledger_entry_id IS NOT NULL THEN", "    IF false THEN")(
         rep("    c_max      CONSTANT integer := 1000;", "    c_max      CONSTANT integer := 998;")(x))),
    # ---- r2: round 1's findings (each names the r2 check that answers it)
    ("N72", "a payment may be born posted", "R1",
     rep("    IF NEW.status IS DISTINCT FROM (CASE TG_TABLE_NAME", "    IF false AND NEW.status IS DISTINCT FROM (CASE TG_TABLE_NAME")),
    ("N73", "payments default to posted again", "APPLY:no longer defaults to pending",
     tail("ALTER TABLE public.payments ALTER COLUMN status SET DEFAULT 'posted';")),
    ("N74", "a payment is posted by a row of another kind", "R2",
     rep("               AND l.transaction_type = v_kind\n", "")),
    ("N75", "a partial nsf row ends a payment", "R3",
     rep("l.transaction_type = 'nsf' AND l.customer_id = NEW.customer_id\n               AND o.id = OLD.status_cause_id AND public.ledger_entry_remaining(o.id) = 0)",
         "l.transaction_type = 'nsf' AND l.customer_id = NEW.customer_id\n               AND o.id = OLD.status_cause_id)")),
    ("N76", "reversed may name an nsf row", "R4",
     rep("l.transaction_type <> 'nsf' AND l.customer_id = NEW.customer_id", "l.customer_id = NEW.customer_id")),
    ("N77", "any ledger type may name an entry", "APPLY:a v5.4.2-23 constraint is missing",
     tail("ALTER TABLE public.account_ledger DROP CONSTRAINT account_ledger_reversal_types_only_check;")),
    ("N78", "a reversal may be dated after today", "R5b",
     rep("    IF NEW.transaction_date > CURRENT_DATE THEN", "    IF false THEN")),
    ("N79", "any credit may name a payment", "APPLY:a v5.4.2-23 constraint is missing",
     tail("ALTER TABLE public.customer_credits DROP CONSTRAINT customer_credits_payment_overpayment_check;")),
    ("N80", "an approval may be signed by another tenant's user", "APPLY:a v5.4.2-23 constraint is missing",
     tail("ALTER TABLE public.customer_credit_approvals DROP CONSTRAINT customer_credit_approvals_approved_by_fkey;")),
    ("N81", "a voided overpayment credit still holds its payment's money", "R7c",
     rep("     WHERE p_kind = 'payment' AND c.source_payment_id = p_id AND c.status <> 'voided'\n",
         "     WHERE p_kind = 'payment' AND c.source_payment_id = p_id\n")),
    ("N82", "an undo brings money back to an ended source", "R12j",
     rep("        WHEN 'undo' THEN v_status IN ('posted', 'active')", "        WHEN 'undo' THEN true")),
    ("N83", "refunded is a payment status again", "M3g",
     rep("            OR (OLD.status = 'posted' AND NEW.status IN ('nsf', 'reversed'))) THEN",
         "            OR (OLD.status = 'posted' AND NEW.status IN ('nsf', 'reversed', 'refunded'))) THEN")),
    ("N84", "donated is a credit status again", "R11c",
     rep("    IF NOT (OLD.status = 'active' AND NEW.status IN ('escheated', 'voided')) THEN",
         "    IF NOT (OLD.status = 'active' AND NEW.status IN ('escheated', 'voided', 'donated')) THEN")),
    ("N85", "a credit gives money with no credit_issued entry", "R9",
     rep("    IF p_purpose <> 'undo' AND v_entry IS NULL AND v_origin IS DISTINCT FROM 'refund_reissue' THEN", "    IF false THEN")),
    ("N86", "a credit's refund skips its cap", "R10",
     rep("        PERFORM public.check_cash_source('credit', NEW.refunds_customer_credit_id, NEW.created_at, 'refund', NEW.payment_date);", "        NULL;")),
    ("N87", "a donation is not a draw", "R11b",
     rep("     WHERE p_kind = 'credit' AND d.transaction_type = 'donation' AND d.reference_type = 'customer_credit' AND d.reference_id = p_id\n    UNION ALL",
         "     WHERE false AND d.transaction_type = 'donation' AND d.reference_type = 'customer_credit' AND d.reference_id = p_id\n    UNION ALL")),
    ("N88", "a credit is escheated with money left", "R12h",
     rep("        IF v_left <> 0 THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('customer credit %s moves to escheated",
         "        IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('customer credit %s moves to escheated")),
    ("N89", "a donation of a credit may be 0 or less", "R11f",
     rep("        IF NEW.amount <= 0 THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('account_ledger %s donates credit",
         "        IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('account_ledger %s donates credit")),
    ("N90", "a dormancy flag escheats a credit", "R12b",
     rep("e.customer_credit_id = NEW.id\n               AND e.event_type = 'escheated_to_state')", "e.customer_credit_id = NEW.id)")),
    ("N91", "a remittance may carry no amount", "R12c",
     rep("        IF NOT coalesce(NEW.amount_related > 0, false) THEN", "        IF false THEN")),
    ("N92", "an escheat skips the cap", "R12d",
     rep("        PERFORM public.check_cash_source('credit', NEW.customer_credit_id, NEW.created_at, 'escheat', (NEW.event_date AT TIME ZONE 'UTC')::date);", "        NULL;")),
    ("N93", "a credit is voided by a partial reversal", "R13",
     rep("               AND public.ledger_entry_remaining(o.id) = 0) END", ") END")),
    ("N94", "a draft bill's line has a position", "R16",
     rep("     WHERE l.id = p_line_id AND i.invoice_date <= p_on AND i.first_issued_at <= p_recorded_at;",
         "     WHERE l.id = p_line_id AND i.invoice_date <= p_on;")),
    ("N95", "a bill has a position before it was issued", "R16b",
     rep("     WHERE i.id = p_invoice_id AND i.invoice_date <= p_on AND i.first_issued_at <= p_recorded_at;",
         "     WHERE i.id = p_invoice_id AND i.invoice_date <= p_on;")),
    ("N96", "a refund voided later stops counting at an earlier instant", "R17",
     rep("                         AND (r.status IN ('pending', 'posted') OR r.status_recorded_at > p_recorded_at)), 0) AS refunded) x",
         "                         AND r.status IN ('pending', 'posted')), 0) AS refunded) x")),
    ("N97", "a caller rewrites the time of a payment's move", "R3e",
     rep(PAY_CAUSE, PAY_CAUSE.replace("\n           OR (NEW.status_recorded_at IS DISTINCT FROM OLD.status_recorded_at AND NOT v_super) THEN", " THEN"))),
    ("N98", "a payment's move keeps a caller's time", "R3d",
     rep("    IF NOT v_super OR NEW.status_recorded_at IS NOT DISTINCT FROM OLD.status_recorded_at THEN\n" + PAY_STAMP,
         "    IF false THEN\n" + PAY_STAMP)),
    ("N99", "a history row may be recorded before its source", "R18",
     rep("    IF p_row_created_at < v_src_at THEN", "    IF false THEN")),
    ("N100", "an application may be recorded before its bill was issued", "R18b",
     rep("    IF NEW.created_at < v_inv.first_issued_at THEN", "    IF false THEN")),
    ("N101", "a payment's posting entry is undone while it is applied", "CR3",
     rep("        IF coalesce((SELECT sum(a.amount) FROM public.invoice_applications a WHERE a.payment_id = v_src), 0) <> 0\n",
         "        IF false\n")),
    ("N102", "the bounce row takes no source lock", "CR3",
     rep("        PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('payment', v_src));\n        IF NEW.amount < 0 THEN",
         "        IF NEW.amount < 0 THEN")),
    ("N103", "a credit's credit_issued entry is undone while it is drawn on", "M3h",
     rep("        ELSIF EXISTS (SELECT 1 FROM public.cash_source_draws('credit', v_src) d HAVING coalesce(sum(d.amount), 0) <> 0) THEN", "        ELSIF false THEN")),
    ("N104", "the source is read before its lock", "CR9",
     lambda x: rep("            ERRCODE = 'foreign_key_violation';\n    END IF;\n    -- Which source may give money for what.",
                   "            ERRCODE = 'foreign_key_violation';\n    END IF;\n    PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key(p_kind, p_id));\n    -- Which source may give money for what.")(
         rep("    PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key(p_kind, p_id));\n    -- r3 (Fable S4)",
             "    -- r3 (Fable S4)")(x))),
    ("N105", "the cap forgets what was taken back on the ledger", "CR9b",
     rep("                        UNION ALL\n                        SELECT l.transaction_date, CASE WHEN v_origin = 'overpayment' THEN coalesce(x.absorbed, 0) ELSE l.amount - coalesce(x.absorbed, 0) END\n                          FROM public.account_ledger l LEFT JOIN public.overpayment_split(v_split) x ON x.id = l.id\n                         WHERE l.id = ANY (public.ledger_tree_ids(v_entry))\n                        UNION ALL\n                        -- missing",
         "                        UNION ALL\n                        -- missing")),
    ("N106", "a payment's status move at REPEATABLE READ", "CR12",
     rep("    IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('payment %s: a status move",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('payment %s: a status move")),
    ("N107", "a credit's status move at REPEATABLE READ", "CR12b",
     rep("    IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('customer credit %s: a status move",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('customer credit %s: a status move")),
    ("N108", "the application role may update a column of an application", "APPLY:both are add-only",
     tail("GRANT UPDATE (reason) ON public.invoice_applications TO tally_app;")),
    ("N109", "the core role may call the cap's entry point", "APPLY:executable beyond tally_app",
     tail("GRANT EXECUTE ON FUNCTION public.check_cash_source(text, uuid, timestamp with time zone, text, date) TO tally_core;")),
    ("N110", "approvals lose their tenant policy", "APPLY:lost its tenant_isolation policy",
     tail("DROP POLICY tenant_isolation ON public.customer_credit_approvals;")),
    # ---- r3: Kyle's K-10, Ryan's 2026-10-21 statuses, round 2's findings
    ("N111", "a refund row may be negative", "APPLY:a v5.4.2-23 constraint is missing",
     rep("        CHECK (transaction_type <> 'refund' OR amount > 0);", "        CHECK (true);")),
    ("N112", "a pending refund does not block the bounce", "S4",
     rep("               OR EXISTS (SELECT 1 FROM public.payments r WHERE r.refunds_payment_id = v_src AND r.status = 'pending')\n", "")),
    ("N113", "a payment may have two posting rows", "APPLY:unique index is missing",
     rep("CREATE UNIQUE INDEX account_ledger_payment_arrival_key ON public.account_ledger (reference_id)\n", "CREATE INDEX account_ledger_payment_arrival_key ON public.account_ledger (reference_id)\n")),
    ("N114", "a credit may have two credit_issued rows", "APPLY:unique index is missing",
     rep("CREATE UNIQUE INDEX account_ledger_credit_arrival_key ON public.account_ledger (reference_id)\n", "CREATE INDEX account_ledger_credit_arrival_key ON public.account_ledger (reference_id)\n")),
    ("N115", "a posting row may name its payment as a refund", "S6c",
     rep("        IF NEW.reference_type <> 'payment' OR NEW.transaction_type <> v_kind OR NEW.amount <> -v_pay.amount THEN",
         "        IF NEW.transaction_type <> v_kind OR NEW.amount <> -v_pay.amount THEN")),
    ("N116", "a posting row may be of any amount", "S6b",
     rep("        IF NEW.reference_type <> 'payment' OR NEW.transaction_type <> v_kind OR NEW.amount <> -v_pay.amount THEN",
         "        IF NEW.reference_type <> 'payment' OR NEW.transaction_type <> v_kind THEN")),
    ("N117", "a posting row may be of another kind", "S6d",
     rep("        IF NEW.reference_type <> 'payment' OR NEW.transaction_type <> v_kind OR NEW.amount <> -v_pay.amount THEN",
         "        IF NEW.reference_type <> 'payment' OR NEW.amount <> -v_pay.amount THEN")),
    ("N118", "a posting row may be on another customer's account", "S6d2",
     rep("        IF NOT FOUND OR v_pay.tenant_id <> NEW.tenant_id OR v_pay.customer_id <> NEW.customer_id THEN", "        IF NOT FOUND THEN")),
    ("N119", "an overpayment credit posts a credit_issued row", "S6g",
     rep("        IF v_credit.origin_type IN ('overpayment', 'refund_reissue') THEN", "        IF false THEN")),
    ("N120", "a credit_issued row may be of any amount", "S6f",
     rep("        IF NEW.amount <> -v_credit.original_amount THEN", "        IF false THEN")),
    ("N121", "a credit_issued row may be on another customer's account", "S6f2",
     rep("        IF NOT FOUND OR v_credit.tenant_id <> NEW.tenant_id OR v_credit.customer_id <> NEW.customer_id THEN", "        IF NOT FOUND THEN")),
    ("N122", "a donation may be on another customer's account", "S10",
     rep("        IF NOT EXISTS (SELECT 1 FROM public.customer_credits c\n                        WHERE c.id = NEW.reference_id AND c.tenant_id = NEW.tenant_id AND c.customer_id = NEW.customer_id) THEN",
         "        IF false THEN")),
    ("N123", "a remittance may name another customer", "APPLY:a v5.4.2-23 constraint is missing",
     tail("ALTER TABLE public.escheatment_events DROP CONSTRAINT escheatment_events_credit_customer_fkey;")),
    ("N124", "a remittance in a closed period", "S11",
     rep("    IF v_on <= v_through THEN", "    IF false THEN")),
    ("N125", "the remittance's freeze is dropped", "APPLY:a v5.4.2-23 guard is missing",
     tail("DROP TRIGGER a_enforce_accounting_freeze ON public.escheatment_events;")),
    ("N126", "a draw may be recorded before its payment was posted", "S12",
     rep("greatest(p.created_at, p.status_recorded_at)", "p.created_at")),
    ("N127", "a draw may be recorded before its credit was issued", "S12b",
     rep("    v_src_at := greatest(v_src_at, (SELECT l.created_at FROM public.account_ledger l WHERE l.id = v_entry));\n", "")),
    ("N128", "a draw begun before a refund left its source is not told to retry", "CR13b",
     rep("    IF FOUND THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s %s: a row drawing on it is recorded at %s, before %s left it",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s %s: a row drawing on it is recorded at %s, before %s left it")),
    ("N129", "an overpayment credit's void takes no lock on its payment", "CR17",
     rep("    IF NEW.status = 'voided' AND OLD.source_payment_id IS NOT NULL THEN\n        PERFORM", "    IF false THEN\n        PERFORM")),
    ("N130", "a payment's position ignores what was taken back", "S1e",
     rep("unnest(public.ledger_tree_ids(e.id) || e.id) AS t(id)\n                        JOIN public.account_ledger l ON l.id = t.id\n                       WHERE e.reference_type = 'payment'",
         "unnest(ARRAY[e.id]) AS t(id)\n                        JOIN public.account_ledger l ON l.id = t.id\n                       WHERE e.reference_type = 'payment'")),
    ("N131", "a credit's position ignores a donation's undo", "S9b",
     rep("unnest(public.ledger_tree_ids(d.id) || d.id) AS t(id)\n                        JOIN", "unnest(ARRAY[d.id]) AS t(id)\n                        JOIN")),
    ("N132", "a donation's undo still draws on the credit", "S9",
     rep("\n      CROSS JOIN LATERAL unnest(public.ledger_tree_ids(d.id) || d.id) AS t(id)", "\n      CROSS JOIN LATERAL unnest(ARRAY[d.id]) AS t(id)")),
    ("N133", "a payment is posted by an entry already undone", "S13",
     rep("\n               AND cardinality(public.ledger_tree_ids(l.id)) = 0)", ")")),
    ("N134", "refunded is a payment status value again", "APPLY:a v5.4.2-23 constraint is missing",
     rep("    CHECK ((status = ANY (ARRAY['pending'::text, 'posted'::text, 'nsf'::text, 'reversed'::text, 'voided'::text])));",
         "    CHECK ((status = ANY (ARRAY['pending'::text, 'posted'::text, 'nsf'::text, 'reversed'::text, 'refunded'::text, 'voided'::text])));")),
    ("N135", "approvals gain a second permissive policy", "APPLY:another policy beside it",
     tail("CREATE POLICY widen ON public.customer_credit_approvals USING (true);")),
    ("N136", "the application role loses the cap's entry point", "APPLY:or not by tally_app",
     tail("REVOKE EXECUTE ON FUNCTION public.check_cash_source(text, uuid, timestamp with time zone, text, date) FROM tally_app;")),
    ("N137", "a remittance's stamp is dropped", "APPLY:a v5.4.2-23 guard is missing",
     tail("DROP TRIGGER a_stamp_created_at ON public.escheatment_events;")),
    ("N138", "a credit may be for 0", "APPLY:a v5.4.2-23 constraint is missing",
     tail("ALTER TABLE public.customer_credits DROP CONSTRAINT customer_credits_original_amount_check;")),
    ("N139", "a refund payment may be positive", "APPLY:a v5.4.2-23 constraint is missing",
     tail("ALTER TABLE public.payments DROP CONSTRAINT payments_refund_is_refund_check;")),
    ("N140", "the cap lets a cent through", "R3b",
     rep("         WHERE x.used > v_amount\n", "         WHERE x.used > v_amount + 0.01\n")),
    # ---- r4: round 3's findings, Ryan's 2026-10-21 reissue
    ("N141", "the bounce ignores money of the overpayment credit still paying a bill", "V3b",
     rep("AND (coalesce((SELECT sum(a.amount) FROM public.invoice_applications a WHERE a.customer_credit_id = c.id), 0) <> 0\n                                  OR EXISTS",
         "AND (false\n                                  OR EXISTS")),
    ("N142", "the bounce ignores a refund of the overpayment credit still pending", "V3",
     rep("OR EXISTS (SELECT 1 FROM public.payments r WHERE r.refunds_customer_credit_id = c.id AND r.status = 'pending'))) THEN\n                RAISE EXCEPTION USING\n                    MESSAGE = format('account_ledger",
         "OR false)) THEN\n                RAISE EXCEPTION USING\n                    MESSAGE = format('account_ledger")),
    ("N143", "any live overpayment credit holds up the bounce (r3)", "V1",
     rep("                           WHERE c.source_payment_id = v_src AND c.status <> 'voided'\n                             AND (",
         "                           WHERE c.source_payment_id = v_src AND c.status <> 'voided'\n                             AND (true OR ")),
    ("N144", "the move to nsf ignores money of the overpayment credit still paying a bill", "V16",
     rep("AND (coalesce((SELECT sum(a.amount) FROM public.invoice_applications a WHERE a.customer_credit_id = c.id), 0) <> 0\n                              OR EXISTS",
         "AND (false\n                              OR EXISTS")),
    # N145 (r4: the bounce takes no lock on the overpayment credit) is retired in r5: every draw on
    # the credit takes its payment's lock first (N191, CR22), so that lock was redundant and is gone.
    ("N146", "an overpayment credit is read without its payment", "S7c",
     rep("    v_entry := CASE WHEN v_origin = 'overpayment' THEN public.cash_arrival_entry('payment', v_src_pay)\n                    ELSE public.cash_arrival_entry(p_kind, p_id) END;",
         "    v_entry := public.cash_arrival_entry(p_kind, p_id);")),
    ("N147", "an overpayment credit's position ignores its payment's bounce", "V1c",
     rep("                 WHEN c.origin_type = 'overpayment' THEN c.original_amount - coalesce((", "                 WHEN c.origin_type = 'overpayment' THEN c.original_amount - 0 * coalesce((")),
    ("N148", "a payment's position counts a bounced credit at its amount", "V1c",
     rep("            coalesce((SELECT sum(c.original_amount - coalesce((", "            coalesce((SELECT sum(c.original_amount - 0 * coalesce((")),
    ("N149", "a payment may hold two live overpayment credits", "APPLY:unique index is missing",
     rep("CREATE UNIQUE INDEX customer_credits_one_live_per_payment ON public.customer_credits (source_payment_id)\n", "CREATE INDEX customer_credits_one_live_per_payment ON public.customer_credits (source_payment_id)\n")),
    ("N150", "a reissue carries any amount", "V7b",
     rep("        IF NEW.original_amount <> least(-v_refund.amount, v_left) THEN", "        IF false THEN")),
    ("N151", "a refund still standing is reissued", "V7h",
     rep("        IF v_refund.refunds_customer_credit_id IS NULL OR v_refund.status NOT IN ('nsf', 'reversed') THEN", "        IF v_refund.refunds_customer_credit_id IS NULL THEN")),
    ("N152", "a reissue skips its credit's cap (and its recorded order)", "W11",
     rep("        PERFORM public.check_cash_source('credit', v_refund.refunds_customer_credit_id, NEW.created_at, 'reissue', NEW.issued_date);", "        NULL;")),
    ("N153", "nothing is reissued from an escheated credit", "V7c",
     rep("        WHEN 'reissue' THEN p_kind = 'credit' AND v_status IN ('active', 'escheated')", "        WHEN 'reissue' THEN p_kind = 'credit' AND v_status = 'active'")),
    ("N154", "a returned refund may stay on an escheated credit", "V7a",
     rep("    IF v_left > 0 THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('refund %s of credit", "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('refund %s of credit")),
    ("N155", "the escheated credit's settlement check is dropped", "APPLY:a v5.4.2-23 guard is missing",
     tail("DROP TRIGGER enforce_escheated_credit_settled ON public.payments;")),
    ("N156", "a reissue is voided back onto its escheated credit", "V7f",
     rep("        IF NOT EXISTS (SELECT 1 FROM public.customer_credits c WHERE c.id = v_from AND c.status = 'active') THEN", "        IF false THEN")),
    ("N157", "a credit is escheated with a refund pending", "V6",
     rep("    IF NEW.status = 'escheated' AND EXISTS (SELECT 1 FROM public.payments r WHERE r.refunds_customer_credit_id = NEW.id AND r.status = 'pending') THEN", "    IF false THEN")),
    ("N158", "a credit never issued cannot be voided", "V13",
     rep("OR public.cash_arrival_entry('credit', OLD.id) IS NULL\n                                THEN", "\n                                THEN")),
    ("N159", "a credit_issued row for a credit no longer active", "V13b",
     rep("        IF v_credit.status <> 'active' THEN", "        IF false THEN")),
    ("N160", "a posting row for a payment no longer pending", "V9",
     rep("        IF v_pay.status <> 'pending' THEN", "        IF false THEN")),
    ("N161", "a posting row takes no lock on its payment", "CR19",
     rep("        PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('payment', NEW.reference_id));\n", "")),
    ("N162", "a source's money counts before its arrival entry's date", "V10",
     rep("                        SELECT l.transaction_date, l.amount FROM public.account_ledger l\n                         WHERE l.id = v_entry AND",
         "                        SELECT '-infinity'::date, l.amount FROM public.account_ledger l\n                         WHERE l.id = v_entry AND")),
    ("N163", "an earlier deficit vetoes a later draw", "V11",
     rep("\n           AND x.on_date >= p_on", "")),
    ("N164", "a draw may be recorded before money given back under its arrival", "V14",
     rep("    IF FOUND AND p_row_created_at <> pg_catalog.now() THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s %s: a row drawing on it is recorded at %s, a time chosen for it, before %s was recorded under",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s %s: a row drawing on it is recorded at %s, a time chosen for it, before %s was recorded under")),
    ("N165", "a row giving money back waits like one taking it", "V12",
     rep("        IF NEW.amount < 0 THEN\n            IF NOT EXISTS (SELECT 1 FROM public.payments p WHERE p.id = v_src",
         "        IF false THEN\n            IF NOT EXISTS (SELECT 1 FROM public.payments p WHERE p.id = v_src")),
    ("N166", "money is given back to a bounced payment", "V15",
     rep("            IF NOT EXISTS (SELECT 1 FROM public.payments p WHERE p.id = v_src AND p.status IN ('pending', 'posted')) THEN", "            IF false THEN")),
    ("N167", "money is given back to an escheated credit", "V15b",
     rep("            IF NOT EXISTS (SELECT 1 FROM public.customer_credits c WHERE c.id = v_src AND c.status = 'active') THEN", "            IF false THEN")),
    ("N168", "a donation's correction is never capped", "V8",
     rep("                                         CASE WHEN NEW.amount > 0 THEN 'donation' ELSE 'undo' END, NEW.transaction_date);", "                                         'undo', NEW.transaction_date);")),
    ("N169", "a donation is undone onto an ended credit", "V5",
     rep("    IF v_root.transaction_type = 'donation' AND v_root.reference_type = 'customer_credit' THEN\n        PERFORM public.check_cash_source",
         "    IF false THEN\n        PERFORM public.check_cash_source")),
    ("N170", "a refund_reissue credit's shape check (origin and reissued refund together) is dropped", "APPLY:a v5.4.2-23 constraint is missing",
     tail("ALTER TABLE public.customer_credits DROP CONSTRAINT customer_credits_reissue_check;")),
    # ---- r5: round 4's findings
    ("N171", "a row goes under a refund's posting row after the refund came back", "W1",
     rep("        IF v_kind NOT IN ('pending', 'posted') THEN", "        IF false THEN")),
    ("N172", "a row under a refund's posting row takes no lock on the refund", "CR21",
     rep("    IF v_src IS NOT NULL THEN\n        PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('payment', v_src));\n        SELECT p.status INTO v_kind",
         "    IF v_src IS NOT NULL THEN\n        SELECT p.status INTO v_kind")),
    ("N173", "a take-back comes out of the payment, not first out of the credit", "W2",
     rep("            v_take := least(r.amount, greatest(v_hold_k, 0));", "            v_take := 0;")),
    ("N174", "a take-back recorded before the credit comes out of it", "W4",
     rep("        IF r.created_at >= c.created_at AND r.amount > 0 THEN", "        IF r.amount > 0 THEN")),
    ("N175", "the credit absorbs a take-back up to its amount, not what it still held (the r5 plan)", "W3",
     rep("            v_hold_k := c.original_amount - v_abs - public.cash_drawn_at('credit', c.id, r.created_at);", "            v_hold_k := c.original_amount - v_abs;")),
    ("N176", "what neither held falls on the payment, not the credit", "V1c",
     rep("            absorbed := v_take + least(v_short, greatest(c.original_amount - v_abs - v_take, 0));", "            absorbed := v_take;")),
    ("N177", "what the credit no longer held skips the payment's own part", "W3",
     rep("            v_short := r.amount - v_take - least(r.amount - v_take, greatest(v_hold_p, 0));", "            v_short := r.amount - v_take;")),
    ("N178", "a give-back goes to the payment, not first to the credit", "W2f",
     rep("            absorbed := -least(-r.amount, v_abs);", "            absorbed := 0;")),
    ("N179", "the payment's cap counts the whole take-back (r4)", "W2a",
     rep("ELSE l.amount - coalesce(x.absorbed, 0) END", "ELSE l.amount END")),
    ("N180", "the credit's cap counts the whole take-back (r4)", "W4a",
     rep("CASE WHEN v_origin = 'overpayment' THEN coalesce(x.absorbed, 0) ELSE", "CASE WHEN v_origin = 'overpayment' THEN l.amount ELSE")),
    ("N181", "the payment and its credit are not held together (W3a, in one instant, meets it first)", "W3a",
     rep("        IF v_pool_pay IS NOT NULL THEN\n            SELECT x.on_date, x.used, pp.amount", "        IF false THEN\n            SELECT x.on_date, x.used, pp.amount")),
    ("N182", "money is given back under a payment onto its escheated credit", "W5a",
     rep("            SELECT c.id INTO v_later_id FROM public.customer_credits c WHERE c.source_payment_id = v_src AND c.status = 'escheated';\n            IF FOUND THEN",
         "            SELECT c.id INTO v_later_id FROM public.customer_credits c WHERE c.source_payment_id = v_src AND c.status = 'escheated';\n            IF false THEN")),
    ("N183", "a reissue carries the whole refund, whatever is left (r4)", "V7i",
     rep("        IF NEW.original_amount <> least(-v_refund.amount, v_left) THEN", "        IF NEW.original_amount <> -v_refund.amount THEN")),
    ("N184", "the commit check refuses a K-10 deficit on the escheated credit (r4)", "W7",
     rep("    IF v_left > 0 THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('refund %s of credit", "    IF v_left <> 0 THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('refund %s of credit")),
    ("N185", "a reissue dated before its refund came back", "W8",
     rep("        IF NEW.issued_date < (SELECT l.transaction_date FROM public.account_ledger l WHERE l.id = v_refund.status_cause_id) THEN",
         "        IF false THEN")),
    ("N186", "a payment's status time may be in the future", "W10",
     rep("""    IF NEW.status_recorded_at IS DISTINCT FROM OLD.status_recorded_at
       AND (NOT pg_catalog.isfinite(NEW.status_recorded_at) OR NEW.status_recorded_at > pg_catalog.clock_timestamp()) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('payment %s""", """    IF false THEN
        RAISE EXCEPTION USING
            MESSAGE = format('payment %s""")),
    ("N187", "a credit's status time may be in the future", "W10e",
     rep("""    IF NEW.status_recorded_at IS DISTINCT FROM OLD.status_recorded_at
       AND (NOT pg_catalog.isfinite(NEW.status_recorded_at) OR NEW.status_recorded_at > pg_catalog.clock_timestamp()) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('customer credit %s""", """    IF false THEN
        RAISE EXCEPTION USING
            MESSAGE = format('customer credit %s""")),
    ("N188", "a history load is born with a future status time", "W10c",
     rep("    IF NEW.status_recorded_at IS NOT NULL\n       AND (NOT pg_catalog.isfinite(NEW.status_recorded_at)", "    IF false\n       AND (NOT pg_catalog.isfinite(NEW.status_recorded_at)")),
    ("N189", "an arrival row may be written at REPEATABLE READ", "CR20",
     rep("        OR (NEW.transaction_type IN ('payment', 'deposit', 'refund') AND NEW.reference_type IN ('payment', 'refund'))\n        OR (NEW.transaction_type IN ('credit_issued', 'donation') AND NEW.reference_type = 'customer_credit'))",
         ")")),
    ("N190", "a refund_reissue credit posts a credit_issued row", "W9",
     rep("        IF v_credit.origin_type IN ('overpayment', 'refund_reissue') THEN", "        IF v_credit.origin_type = 'overpayment' THEN")),
    ("N191", "a draw on an overpayment credit takes no lock on its payment", "CR22",
     rep("        IF v_pool_pay IS NOT NULL THEN\n            PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('payment', v_pool_pay));\n        END IF;\n", "")),
]


def sh(cmd: list[str], inp: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, input=inp, capture_output=True, text=True)


def sh_ordered(cmd: list[str], inp: str | None = None) -> subprocess.CompletedProcess:
    """stdout and stderr in one stream, in the order written."""
    return subprocess.run(cmd, input=inp, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)


def runner(check: str) -> tuple[list[str], str | None, str]:
    """The command, its input, and the check's bare name."""
    if re.fullmatch(r"CR\d+[a-z]?", check):
        return [str(HERE / "races/cash-23.sh"), DB], None, check
    battery, name = (ROOT / "tests/v5.4.2-22/battery-22.sql", check[4:]) if check.startswith("b22:") else (HERE / "battery-23.sql", check)
    # A mutation that loops must report, not hang: a timeout is a MISS (ERROR before the named FAIL).
    return ["docker", "exec", "-i", "-e", "PGOPTIONS=-c statement_timeout=300s", "tally-pg", "psql", "-U", "tally", "-d", DB, "-v", "ON_ERROR_STOP=1", "-q", "-o", "/dev/null", "-f", "-"], \
        battery.read_text(), name


def main() -> int:
    base = PATCH.read_text()
    only = set(sys.argv[1:])
    missed = ran = 0
    for mid, what, check, mut in MUTATIONS:
        if only and mid not in only:
            continue
        ran += 1
        try:
            patched = mut(base)
        except AssertionError as exc:
            print(f"{mid} ANCHOR-ERROR: {exc}")
            missed += 1
            continue
        setup = [sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-qc", q])
                 for q in (f"DROP DATABASE IF EXISTS {DB}", f"CREATE DATABASE {DB} TEMPLATE tally")]
        # A TEMPLATE clone does not copy the database ACL: revoke TEMP again.
        setup.append(sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", DB, "-v", "ON_ERROR_STOP=1", "-qc", f"REVOKE TEMP ON DATABASE {DB} FROM PUBLIC, tally_app, tally_core"]))
        if any(x.returncode for x in setup):
            print(f"{mid} SETUP-ERROR: {next(x.stderr.strip() for x in setup if x.returncode)[:140]}")
            missed += 1
            continue
        a = sh(["docker", "exec", "-i", "-e", "PGOPTIONS=-c search_path= -c check_function_bodies=on", "tally-pg",
                "psql", "-U", "tally", "-d", DB, "-v", "ON_ERROR_STOP=1", "-q", "-f", "-"], patched)
        if a.returncode:
            last = a.stderr.strip().splitlines()[-1] if a.stderr.strip() else "?"
            phrase = check.split(":", 1)[1] if check.startswith("APPLY:") else None
            if phrase is not None and phrase in a.stderr:
                print(f"{mid} caught at apply: {what} ({phrase})")
            elif phrase is not None:
                print(f"{mid} MISSED (apply failed, but not on \"{phrase}\"): {what}: {last[:140]}")
                missed += 1
            else:
                print(f"{mid} APPLY-ERROR ({what}): {last[:140]}")
                missed += 1
            continue
        if check.startswith("APPLY"):
            print(f"{mid} MISSED (applied cleanly): {what}")
            missed += 1
            continue
        # The worst statistics for the walks' plans: a vacuumed ledger the
        # planner believes empty (-22 r4).
        v = sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", DB, "-v", "ON_ERROR_STOP=1", "-qc", "VACUUM public.account_ledger"])
        if v.returncode:
            print(f"{mid} SETUP-ERROR: {v.stderr.strip()[:140]}")
            missed += 1
            continue
        cmd, inp, name = runner(check)
        out = sh_ordered(cmd, inp)
        text = out.stdout
        first = next((l for l in text.splitlines() if "FAIL" in l or "ERROR" in l), "")
        first = re.sub(r"^psql:[^:]+:\d+: ", "", first)[:140]
        # The first line that reports any failure, infrastructure errors included, must be the named check's.
        fails = [re.sub(r"^.*?(FAIL )", r"\1", l) for l in text.splitlines() if re.search(r"\bFAIL\b|ERROR|FATAL|PANIC", l)]
        if fails and re.match(rf"FAIL {re.escape(name)}[:\s]", fails[0]):
            print(f"{mid} caught at {check}: {what}")
        else:
            print(f"{mid} MISSED ({check}): {what}  [first: {first}]")
            missed += 1
    print(f"{ran - missed}/{ran} caught")
    sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-qc", f"DROP DATABASE IF EXISTS {DB}"])
    return 1 if missed else 0


if __name__ == "__main__":
    sys.exit(main())
