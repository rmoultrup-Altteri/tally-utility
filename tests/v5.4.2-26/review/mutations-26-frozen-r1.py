#!/usr/bin/env python3
"""v5.4.2-26 — prove the -26 checks CATCH drift, not merely pass.

Each mutation alters a copy of the patch, applies it (strict: search_path ''
and function-body checking on) to a fresh clone of a base that has -25 and
not -26 (M26_BASE, default ci_pre26 — tests/ci.sh leaves it), with TEMP
revoked, and runs the script that owns the named check:

  battery check (V C A E F H)          battery-26.sql
  CR1-CR8                              races/collections-26.sh
  APPLY:<phrase>                       the patch itself must refuse, with that phrase

CAUGHT only when the FIRST failure printed is the named check's (the -21
rule). A mutation an EARLIER check catches is reported as missed: its named
check is wrong, or a guard is redundant — fix the name or remove the
duplicate, never loosen the rule.

    python3 tests/v5.4.2-26/mutations-26.py [--anchors] [M01 M12 ...]
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[2]
PATCH = Path(os.environ.get("PATCH26") or ROOT / "sql/v5.4.2-26-collections-decisions.sql")
HERE = ROOT / "tests/v5.4.2-26"
BASE = os.environ.get("M26_BASE", "ci_pre26")
DB = "m26"


def rep(old: str, new: str) -> Callable[[str], str]:
    def m(s: str) -> str:
        assert s.count(old) == 1, f"mutation anchor not unique/found ({s.count(old)}): {old[:90]!r}"
        return s.replace(old, new, 1)
    return m


def tail(sql: str) -> Callable[[str], str]:
    """Append statements just before the patch's own invariant run."""
    return rep("DO $$ BEGIN\n    PERFORM public.assert_cash_guard_invariants();",
               sql + "\nDO $$ BEGIN\n    PERFORM public.assert_cash_guard_invariants();")


# Anchors that occur more than once carry the message line that follows them.
MUTATIONS = [
    # ---- C3: the decision's subject and facts
    ("M01", "a notice without its location", "C3a1",
     rep("       OR (NEW.act = 'notice' AND NEW.location_id IS NULL)\n", "")),
    ("M02", "a late fee with a location", "C3a2",
     rep("(NEW.location_id IS NOT NULL OR NEW.meter_id IS NOT NULL))", "(NEW.meter_id IS NOT NULL))")),
    ("M03", "a referral with a meter", "C3a6",
     rep("(NEW.location_id IS NOT NULL OR NEW.meter_id IS NOT NULL))", "(NEW.location_id IS NOT NULL))")),
    ("M04", "a disconnect decision with a bill", "C3a3",
     rep("       OR (NOT v_bill_act AND NEW.invoice_id IS NOT NULL)\n", "")),
    ("M05", "a bill act without its bill", "C3a4",
     rep("    IF (v_bill_act AND NEW.invoice_id IS NULL)\n", "    IF false\n")),
    ("M06", "a disconnect decision without its location", "C3a5",
     rep("       OR (NOT v_bill_act AND NEW.location_id IS NULL) THEN", "       THEN")),
    ("M07", "a decision on a draft bill", "C3b1",
     rep("        IF FOUND AND NOT public.is_invoice_issued(v_status) THEN", "        IF false THEN")),
    ("M08", "a disconnect at another customer's location", "C3c",
     rep("        IF v_found AND v_loc_cust IS DISTINCT FROM NEW.customer_id THEN", "        IF false THEN")),
    ("M09", "a notice threatening a location not the bill's", "C3d1",
     rep("        IF NEW.act = 'notice' AND v_bill_loc <> NEW.location_id THEN", "        IF false THEN")),
    ("M10", "a meter not deployed at the location", "C3e1",
     rep("    IF NEW.meter_id IS NOT NULL AND NOT EXISTS (\n           SELECT 1 FROM public.meter_deployments m\n            WHERE m.meter_id = NEW.meter_id AND m.location_id = NEW.location_id",
         "    IF false AND NOT EXISTS (\n           SELECT 1 FROM public.meter_deployments m\n            WHERE m.meter_id = NEW.meter_id AND m.location_id = NEW.location_id")),
    ("M11", "a meter counted on its removal day (boundary)", "C3e3",
     rep("            WHERE m.meter_id = NEW.meter_id AND m.location_id = NEW.location_id\n              AND daterange(m.install_date, m.removal_date, '[)') @> NEW.evaluation_date) THEN",
         "            WHERE m.meter_id = NEW.meter_id AND m.location_id = NEW.location_id\n              AND daterange(m.install_date, m.removal_date, '[]') @> NEW.evaluation_date) THEN")),
    # ---- C3f-C3j: the outcome
    ("M12", "eligible with a condition", "C3f1",
     rep("    IF (NEW.outcome = 'eligible' AND (cardinality(v_all) > 0 OR NEW.governing_condition IS NOT NULL",
         "    IF (NEW.outcome = 'eligible' AND (NEW.governing_condition IS NOT NULL")),
    ("M13", "eligible crediting a condition", "C3f15",
     rep("    IF (NEW.outcome = 'eligible' AND (cardinality(v_all) > 0 OR NEW.governing_condition IS NOT NULL",
         "    IF (NEW.outcome = 'eligible' AND (cardinality(v_all) > 0")),
    ("M14", "eligible with no last day", "C3f3",
     rep("                                      OR NEW.valid_until IS NULL OR NEW.valid_until < NEW.evaluation_date))",
         "                                      OR NEW.valid_until < NEW.evaluation_date))")),
    ("M15", "eligible until before its evaluation", "C3f4",
     rep("                                      OR NEW.valid_until IS NULL OR NEW.valid_until < NEW.evaluation_date))",
         "                                      OR NEW.valid_until IS NULL))")),
    ("M16", "eligible until its own day is refused (boundary)", "C3f5",
     rep("                                      OR NEW.valid_until IS NULL OR NEW.valid_until < NEW.evaluation_date))",
         "                                      OR NEW.valid_until IS NULL OR NEW.valid_until <= NEW.evaluation_date))")),
    ("M18", "blocked with a last day", "C3f9",
     rep("       OR (NEW.outcome = 'blocked' AND (NEW.valid_until IS NOT NULL\n                                        OR NOT coalesce",
         "       OR (NEW.outcome = 'blocked' AND (false\n                                        OR NOT coalesce")),
    ("M19", "blocked crediting a condition not active (an empty block is the first to pass)", "C3f6",
     rep("                                        OR NOT coalesce(NEW.governing_condition = ANY (NEW.active_conditions), false)))",
         "                                        ))")),
    ("M20", "blocked crediting nothing", "C3f8",
     rep("NOT coalesce(NEW.governing_condition = ANY (NEW.active_conditions), false)))",
         "NOT coalesce(NEW.governing_condition = ANY (NEW.active_conditions), true)))")),
    ("M21", "unevaluable with an active condition", "C3f10",
     rep("       OR (NEW.outcome = 'unevaluable' AND (cardinality(NEW.active_conditions) > 0 OR cardinality(NEW.unevaluable_conditions) = 0",
         "       OR (NEW.outcome = 'unevaluable' AND (cardinality(NEW.unevaluable_conditions) = 0")),
    ("M22", "unevaluable with nothing unevaluable", "C3f11",
     rep("       OR (NEW.outcome = 'unevaluable' AND (cardinality(NEW.active_conditions) > 0 OR cardinality(NEW.unevaluable_conditions) = 0",
         "       OR (NEW.outcome = 'unevaluable' AND (cardinality(NEW.active_conditions) > 0")),
    ("M23", "unevaluable crediting a condition", "C3f12",
     rep("                                            OR NEW.governing_condition IS NOT NULL OR NEW.valid_until IS NOT NULL)) THEN",
         "                                            OR NEW.valid_until IS NOT NULL)) THEN")),
    ("M24", "unevaluable with a last day", "C3f16",
     rep("                                            OR NEW.governing_condition IS NOT NULL OR NEW.valid_until IS NOT NULL)) THEN",
         "                                            OR NEW.governing_condition IS NOT NULL)) THEN")),
    ("M25", "a condition outside the vocabulary", "C3g1",
     rep("     WHERE NOT EXISTS (SELECT 1 FROM public.collections_conditions k WHERE k.condition_code = c);", "     WHERE false;")),
    ("M26", "an active condition named twice", "C3g2",
     rep("       OR cardinality(NEW.active_conditions) <> (SELECT count(DISTINCT c) FROM unnest(NEW.active_conditions) c)\n", "")),
    ("M27", "an unevaluable condition named twice", "C3g4",
     rep("       OR cardinality(NEW.unevaluable_conditions) <> (SELECT count(DISTINCT c) FROM unnest(NEW.unevaluable_conditions) c) THEN",
         "       THEN")),
    ("M28", "an execute decision holding past its day", "C3h1",
     rep("    IF NEW.act = 'disconnect_execute' AND NEW.outcome = 'eligible' AND NEW.valid_until <> NEW.evaluation_date THEN", "    IF false THEN")),
    ("M29", "a decision for tomorrow", "C3j1",
     rep("    IF NEW.evaluation_date > (pg_catalog.now() AT TIME ZONE 'UTC')::date THEN", "    IF false THEN")),
    ("M30", "a decision for today is refused (boundary)", "C3j2",
     rep("    IF NEW.evaluation_date > (pg_catalog.now() AT TIME ZONE 'UTC')::date THEN", "    IF NEW.evaluation_date >= (pg_catalog.now() AT TIME ZONE 'UTC')::date THEN")),
    # ---- C4, C5: one live decision; idempotent
    ("M31", "a second first decision", "C4a1",
     rep("    IF (NEW.supersedes_id IS NULL AND live.id IS NOT NULL)\n", "    IF false\n")),
    ("M32", "a successor of a decision not live", "C4a2",
     rep("       OR (NEW.supersedes_id IS NOT NULL AND live.id IS DISTINCT FROM NEW.supersedes_id) THEN", "       THEN")),
    ("M33", "a successor evaluated earlier", "C4b",
     rep("    IF live.id IS NOT NULL AND NEW.evaluation_date < live.evaluation_date THEN", "    IF false THEN")),
    ("M34", "a successor on the same date is refused (boundary)", "C4",
     rep("    IF live.id IS NOT NULL AND NEW.evaluation_date < live.evaluation_date THEN", "    IF live.id IS NOT NULL AND NEW.evaluation_date <= live.evaluation_date THEN")),
    ("M35", "a re-run on the same facts", "C5a",
     rep("    IF live.id IS NOT NULL AND NEW.evaluation_date = live.evaluation_date AND NEW.inputs_fingerprint = live.inputs_fingerprint THEN", "    IF false THEN")),
    ("M36", "the same facts on a new date are refused", "C5c",
     rep("    IF live.id IS NOT NULL AND NEW.evaluation_date = live.evaluation_date AND NEW.inputs_fingerprint = live.inputs_fingerprint THEN",
         "    IF live.id IS NOT NULL AND NEW.inputs_fingerprint = live.inputs_fingerprint THEN")),
    ("M37", "a decision takes no subject lock", "CR1",
     rep("    PERFORM public.collections_subject_lock(NEW.tenant_id, NEW.act, NEW.customer_id, NEW.invoice_id, NEW.location_id, NEW.meter_id, 'a collections decision');\n", "")),
    ("M38", "the live decision ignores the bill", "A0",
     rep("       AND d.invoice_id IS NOT DISTINCT FROM p_invoice_id AND d.location_id IS NOT DISTINCT FROM p_location_id\n",
         "       AND d.location_id IS NOT DISTINCT FROM p_location_id\n")),
    ("M39", "the live decision ignores the location", "A0",
     rep("       AND d.invoice_id IS NOT DISTINCT FROM p_invoice_id AND d.location_id IS NOT DISTINCT FROM p_location_id\n",
         "       AND d.invoice_id IS NOT DISTINCT FROM p_invoice_id\n")),
    ("M40", "the live decision ignores the meter", "A0",
     rep("       AND d.meter_id IS NOT DISTINCT FROM p_meter_id\n     ORDER BY d.record_seq DESC LIMIT 1", "     ORDER BY d.record_seq DESC LIMIT 1")),
    ("M41", "the live decision ignores the act", "A0",
     rep("     WHERE d.tenant_id = p_tenant_id AND d.act = p_act AND d.customer_id = p_customer_id\n", "     WHERE d.tenant_id = p_tenant_id AND d.customer_id = p_customer_id\n")),
    ("M42", "the live decision is the earliest", "C4a3",
     rep("     ORDER BY d.record_seq DESC LIMIT 1\n$$;", "     ORDER BY d.record_seq LIMIT 1\n$$;")),
    ("M43", "a decision's author not stamped", "C0b",
     rep("    NEW.recorded_txid := txid_current();\n    NEW.record_seq    := nextval('public.collections_record_seq');\n    BEGIN\n        NEW.created_by := NULLIF(current_setting('app.user_id', true), '')::uuid;",
         "    NEW.recorded_txid := txid_current();\n    NEW.record_seq    := nextval('public.collections_record_seq');\n    BEGIN\n        NEW.created_by := NULL;")),
    ("M44", "a decision's transaction not stamped", "C0b",
     rep("    NEW.recorded_txid := txid_current();\n", "")),
    # ---- C7: the act check
    ("M45", "an act citing another act's decision", "A2a",
     rep("    IF d.act <> p_act THEN", "    IF false THEN")),
    ("M46", "an act citing a blocked decision", "A3a",
     rep("    IF d.outcome <> 'eligible' THEN", "    IF false THEN")),
    ("M47", "an act citing a superseded decision", "A4a",
     rep("    IF p_live AND EXISTS (SELECT 1 FROM public.collections_decisions s WHERE s.supersedes_id = d.id) THEN", "    IF false THEN")),
    ("M48", "a bill act citing another bill's decision", "A5a",
     rep("        IF p_invoice_id IS DISTINCT FROM d.invoice_id THEN", "        IF false THEN")),
    ("M49", "a disconnect act at another location", "A5e",
     rep("        IF p_location_id IS DISTINCT FROM d.location_id OR (d.meter_id IS NOT NULL AND p_meter_id IS DISTINCT FROM d.meter_id) THEN",
         "        IF (d.meter_id IS NOT NULL AND p_meter_id IS DISTINCT FROM d.meter_id) THEN")),
    ("M50", "a disconnect act with another meter", "A5f",
     rep("        IF p_location_id IS DISTINCT FROM d.location_id OR (d.meter_id IS NOT NULL AND p_meter_id IS DISTINCT FROM d.meter_id) THEN",
         "        IF p_location_id IS DISTINCT FROM d.location_id THEN")),
    ("M51", "an act after its decision's window", "A6a",
     rep("    IF p_on < d.evaluation_date OR p_on > d.valid_until THEN", "    IF p_on < d.evaluation_date THEN")),
    ("M52", "an act before its decision's window", "A6b",
     rep("    IF p_on < d.evaluation_date OR p_on > d.valid_until THEN", "    IF p_on > d.valid_until THEN")),
    ("M53", "an act on its decision's last day is refused (boundary)", "A6c",
     rep("    IF p_on < d.evaluation_date OR p_on > d.valid_until THEN", "    IF p_on < d.evaluation_date OR p_on >= d.valid_until THEN")),
    ("M54", "an act on its decision's first day is refused (boundary; the first such act is A5g's order)", "A5g",
     rep("    IF p_on < d.evaluation_date OR p_on > d.valid_until THEN", "    IF p_on <= d.evaluation_date OR p_on > d.valid_until THEN")),
    ("M55", "an act takes no subject lock", "CR2",
     rep("    PERFORM public.collections_subject_lock(d.tenant_id, d.act, d.customer_id, d.invoice_id, d.location_id, d.meter_id, p_what);\n", "")),
    ("M56", "the subject lock is not pinned to READ COMMITTED", "CR7",
     rep("    IF current_setting('transaction_isolation') <> 'read committed' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s runs only under READ COMMITTED: the subject''s lock",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s runs only under READ COMMITTED: the subject''s lock")),
    # ---- dunning events
    ("M57", "a gated step with no decision", "A1a",
     rep("    IF (v_act IS NULL) <> (NEW.collections_decision_id IS NULL) THEN", "    IF false THEN")),
    ("M58", "a log line must cite the live decision", "A8b",
     rep("(NEW.event_date AT TIME ZONE 'UTC')::date, NOT v_log, 'dunning event ' || NEW.event_type);",
         "(NEW.event_date AT TIME ZONE 'UTC')::date, true, 'dunning event ' || NEW.event_type);")),
    ("M59", "a late fee logged with no charge", "A8a",
     rep("              AND NOT EXISTS (SELECT 1 FROM public.adhoc_charges c WHERE c.collections_decision_id = d.id))", "              AND false)")),
    ("M60", "a shutoff scheduled with no order", "A8d",
     rep("              AND NOT EXISTS (SELECT 1 FROM public.service_orders o WHERE o.collections_decision_id = d.id))", "              AND false)")),
    ("M61", "a disconnection logged with no executed visit", "A8g",
     rep("              AND NOT EXISTS (SELECT 1 FROM public.service_order_field_visits v WHERE v.collections_decision_id = d.id)) THEN", "              AND false) THEN")),
    ("M62", "the bill's row is not the stage's lock", "CR6b",
     rep("    SELECT i.dunning_stage INTO v_prev FROM public.invoices i WHERE i.id = NEW.invoice_id FOR NO KEY UPDATE;",
         "    SELECT i.dunning_stage INTO v_prev FROM public.invoices i WHERE i.id = NEW.invoice_id;")),
    ("M63", "a step that moves nothing names a stage", "E2b3",
     rep("        IF NEW.new_stage IS NOT NULL OR NEW.previous_stage IS NOT NULL THEN", "        IF false THEN")),
    ("M64", "a caller's new stage that disagrees", "E2b1",
     rep("        IF NEW.new_stage IS DISTINCT FROM v_new AND NEW.new_stage IS NOT NULL\n           OR NEW.previous_stage", "        IF false\n           OR NEW.previous_stage")),
    ("M65", "a caller's previous stage that disagrees", "E2b2",
     rep("           OR NEW.previous_stage IS DISTINCT FROM v_prev AND NEW.previous_stage IS NOT NULL THEN", "           THEN")),
    ("M66", "the previous stage is the caller's", "A6d",
     rep("        NEW.previous_stage := v_prev;\n", "")),
    ("M67", "the stage mapping moves a broken plan", "E2-5",
     rep("WHEN 'resolved' THEN 'resolved' END\n$$;", "WHEN 'resolved' THEN 'resolved' WHEN 'payment_plan_broken' THEN 'reminder_sent' END\n$$;")),
    ("M68", "the bill is not moved", "A6d",
     rep("CREATE TRIGGER z_dunning_move_stage AFTER INSERT ON public.dunning_events FOR EACH ROW EXECUTE FUNCTION public.dunning_move_stage();\n"
         "ALTER TABLE public.dunning_events ENABLE ALWAYS TRIGGER z_dunning_move_stage;\n", "")),
    ("M69", "the stage written directly", "E2a1",
     rep("            OR (TG_OP = 'UPDATE' AND NEW.dunning_stage IS DISTINCT FROM OLD.dunning_stage)) THEN", "            ) THEN")),
    ("M70", "a bill born past current", "E2a2",
     rep("       AND ((TG_OP = 'INSERT' AND NEW.dunning_stage IS DISTINCT FROM 'current')\n            OR", "       AND (false\n            OR")),
    ("M71", "the stage fence counts the move as direct", "A6c",
     rep("    IF pg_trigger_depth() < 2\n       AND ((TG_OP = 'INSERT' AND NEW.dunning_stage", "    IF pg_trigger_depth() < 3\n       AND ((TG_OP = 'INSERT' AND NEW.dunning_stage")),
    ("M73", "a dunning event's bill bound by a single column", "E1a",
     rep("    ADD CONSTRAINT dunning_events_invoice_id_fkey FOREIGN KEY (invoice_id, tenant_id, customer_id) REFERENCES public.invoices (id, tenant_id, customer_id),",
         "    ADD CONSTRAINT dunning_events_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices (id),")),
    ("M74", "a dunning event's decision not bound to its customer", "A5b",
     rep("    ADD CONSTRAINT dunning_events_decision_fkey FOREIGN KEY (collections_decision_id, tenant_id, customer_id)\n        REFERENCES public.collections_decisions (id, tenant_id, customer_id);",
         "    ADD CONSTRAINT dunning_events_decision_fkey FOREIGN KEY (collections_decision_id) REFERENCES public.collections_decisions (id);")),
    ("M75", "two steps on one decision", "A7a",
     rep("CREATE UNIQUE INDEX dunning_events_one_per_decision ON public.dunning_events (collections_decision_id) WHERE collections_decision_id IS NOT NULL;\n", "")),
    # ---- late-fee charges
    ("M76", "a late fee with no decision", "A1c",
     rep("    IF (NEW.charge_type = 'late_fee') <> (NEW.collections_decision_id IS NOT NULL) THEN", "    IF false THEN")),
    ("M77", "a late fee may cite a superseded decision", "A4c",
     rep("NEW.effective_date, true, 'late-fee charge ' || NEW.charge_number);", "NEW.effective_date, false, 'late-fee charge ' || NEW.charge_number);")),
    ("M78", "a late fee's decision cleared", "A9a",
     rep("        IF NEW.collections_decision_id IS DISTINCT FROM OLD.collections_decision_id\n           OR", "        IF false\n           OR")),
    ("M79", "a late fee moved to another bill", "A9b",
     rep("           OR (OLD.collections_decision_id IS NOT NULL AND NEW.triggered_by_invoice_id IS DISTINCT FROM OLD.triggered_by_invoice_id) THEN", "           THEN")),
    ("M80", "any charge's bill frozen", "A9c",
     rep("           OR (OLD.collections_decision_id IS NOT NULL AND NEW.triggered_by_invoice_id IS DISTINCT FROM OLD.triggered_by_invoice_id) THEN",
         "           OR (NEW.triggered_by_invoice_id IS DISTINCT FROM OLD.triggered_by_invoice_id) THEN")),
    ("M81", "two late fees on one decision", "A7b",
     rep("CREATE UNIQUE INDEX adhoc_charges_one_per_decision ON public.adhoc_charges (collections_decision_id) WHERE collections_decision_id IS NOT NULL;\n", "")),
    # ---- disconnect orders
    ("M82", "a disconnect order with no decision", "A1f",
     rep("        IF (NEW.order_type = 'disconnect') <> (NEW.collections_decision_id IS NOT NULL) THEN", "        IF false THEN")),
    ("M83", "a disconnect order born completed", "F4e",
     rep("            IF NEW.status = 'completed' THEN", "            IF false THEN")),
    ("M84", "an order may cite a superseded decision", "A4d",
     rep("(pg_catalog.now() AT TIME ZONE 'UTC')::date, true, 'disconnect order ' || NEW.order_number);",
         "(pg_catalog.now() AT TIME ZONE 'UTC')::date, false, 'disconnect order ' || NEW.order_number);")),
    ("M85", "an order's decision re-pointed", "F4a4",
     rep("    IF NEW.collections_decision_id IS DISTINCT FROM OLD.collections_decision_id\n       OR ((OLD.order_type", "    IF false\n       OR ((OLD.order_type")),
    ("M86", "a disconnect order's meter changed", "F4a1",
     rep("           AND (NEW.order_type, NEW.customer_id, NEW.location_id, NEW.meter_id, NEW.tenant_id)\n               IS DISTINCT FROM (OLD.order_type, OLD.customer_id, OLD.location_id, OLD.meter_id, OLD.tenant_id)) THEN",
         "           AND (NEW.order_type, NEW.customer_id, NEW.location_id, NEW.tenant_id)\n               IS DISTINCT FROM (OLD.order_type, OLD.customer_id, OLD.location_id, OLD.tenant_id)) THEN")),
    ("M87", "an order turned into a disconnect", "F4a3",
     rep("       OR ((OLD.order_type = 'disconnect' OR NEW.order_type = 'disconnect')", "       OR ((OLD.order_type = 'disconnect')")),
    ("M88", "a completed disconnect reopened", "F4c",
     rep("        IF OLD.status = 'completed' THEN", "        IF false THEN")),
    ("M89", "an executed order cancelled", "F4d1",
     rep("        IF v_executed AND NEW.status <> 'completed' THEN", "        IF false THEN")),
    ("M90", "a disconnect completed with no execution", "F4b",
     rep("        IF NOT v_executed AND NEW.status = 'completed' THEN", "        IF false THEN")),
    ("M91", "two orders on one decision", "A7c",
     rep("CREATE UNIQUE INDEX service_orders_one_per_decision ON public.service_orders (collections_decision_id) WHERE collections_decision_id IS NOT NULL;\n", "")),
    ("M92", "an order's decision not bound to its customer", "A5g",
     rep("    ADD CONSTRAINT service_orders_decision_fkey FOREIGN KEY (collections_decision_id, tenant_id, customer_id)\n        REFERENCES public.collections_decisions (id, tenant_id, customer_id);",
         "    ADD CONSTRAINT service_orders_decision_fkey FOREIGN KEY (collections_decision_id) REFERENCES public.collections_decisions (id);")),
    # ---- field visits
    ("M93", "a visit for another tenant answers not found", "H2",
     rep("    PERFORM public.collections_tenant_check('service_order_field_visits', NEW.tenant_id);\n", "")),
    ("M94", "a visit to an order that is not a disconnect", "F1a",
     rep("    IF o.order_type <> 'disconnect' THEN", "    IF false THEN")),
    ("M95", "an execution with no decision", "F2a1",
     rep("        IF NEW.collections_decision_id IS NULL THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('field visit: an execution",
         "        IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('field visit: an execution")),
    ("M96", "an execution's decision for another location", "F2a5",
     rep("        PERFORM public.collections_act_check(NEW.collections_decision_id, 'disconnect_execute', NULL, o.location_id, o.meter_id,",
         "        PERFORM public.collections_act_check(NEW.collections_decision_id, 'disconnect_execute', NULL, NULL, o.meter_id,")),
    ("M97", "a visit to a closed order", "F1n",
     rep("    IF o.status IN ('completed', 'cancelled', 'superseded') THEN", "    IF false THEN")),
    ("M98", "a visit takes no lock on its order", "CR8",
     rep("    SELECT * INTO o FROM public.service_orders x WHERE x.id = NEW.service_order_id FOR SHARE;\n", "")),
    ("M99", "no meter expected from the deployments", "F2g",
     rep("        v_meter := CASE WHEN cardinality(v_ids) = 1 THEN v_ids[1] END;", "        v_meter := NULL;")),
    ("M100", "one of several deployed meters expected", "F1m",
     rep("        v_meter := CASE WHEN cardinality(v_ids) = 1 THEN v_ids[1] END;", "        v_meter := v_ids[1];")),
    ("M101", "a drifted meter matches", "F1j",
     rep("    NEW.matched := coalesce(v_meter IS NOT NULL\n                            AND EXISTS (SELECT 1 FROM public.meter_deployments m\n                                         WHERE m.meter_id = v_meter AND m.location_id = o.location_id\n                                           AND daterange(m.install_date, m.removal_date, '[)') @> v_on)\n",
         "    NEW.matched := coalesce(v_meter IS NOT NULL\n")),
    ("M102", "the serial compared as typed", "F1b",
     rep("                            AND upper(btrim(NEW.captured_meter_serial)) = upper(btrim(NEW.expected_meter_serial))",
         "                            AND NEW.captured_meter_serial = NEW.expected_meter_serial")),
    ("M103", "the service point not compared", "F1p",
     rep("\n                            AND upper(btrim(NEW.captured_location_number)) = upper(btrim(NEW.expected_location_number)), false);", ", false);")),
    ("M104", "a caller's match kept", "F1g",
     rep("    NEW.matched := coalesce(v_meter IS NOT NULL", "    NEW.matched := NEW.matched OR coalesce(v_meter IS NOT NULL")),
    ("M105", "a blank evidence reference", "F1e",
     rep("    IF EXISTS (SELECT 1 FROM unnest(NEW.evidence_refs) r WHERE r IS NULL OR r !~ '[[:alnum:]]') THEN", "    IF false THEN")),
    ("M106", "an execution with nothing captured", "F2a6",
     rep("        IF NEW.captured_meter_serial IS NULL OR NEW.captured_location_number IS NULL THEN", "        IF false THEN")),
    ("M107", "an execution on a mismatch without approval", "F2b",
     rep("            IF NEW.mismatch_approval_id IS NULL THEN", "            IF false THEN")),
    ("M108", "a mismatch approval of the wrong kind", "F3g",
     rep("            IF NOT FOUND OR a.service_order_id <> o.id OR a.kind <> 'meter_mismatch' THEN", "            IF NOT FOUND OR a.service_order_id <> o.id THEN")),
    ("M109", "an execution capturing other values than approved", "F3e",
     rep("            IF upper(btrim(av.captured_meter_serial)) IS DISTINCT FROM upper(btrim(NEW.captured_meter_serial))\n", "            IF false\n")),
    ("M110", "an execution with no evidence and no approval", "F2c",
     rep("            IF NEW.no_evidence_approval_id IS NULL THEN", "            IF false THEN")),
    ("M111", "a no-evidence approval of another order", "F3f",
     rep("            IF NOT FOUND OR a.service_order_id <> o.id OR a.kind <> 'no_evidence' THEN", "            IF NOT FOUND OR a.kind <> 'no_evidence' THEN")),
    ("M112", "a visit's author not stamped", "F1b",
     rep("    NEW.record_seq := nextval('public.collections_record_seq');\n    BEGIN\n        NEW.created_by := NULLIF(current_setting('app.user_id', true), '')::uuid;",
         "    NEW.record_seq := nextval('public.collections_record_seq');\n    BEGIN\n        NEW.created_by := NULL;")),
    ("M113", "an abort may cite a decision", "F1c3",
     rep("               AND (outcome = 'executed' OR (collections_decision_id IS NULL AND mismatch_approval_id IS NULL AND no_evidence_approval_id IS NULL)))",
         "               )")),
    ("M114", "two executions on one decision", "F2d",
     rep("CREATE UNIQUE INDEX service_order_field_visits_one_per_decision ON public.service_order_field_visits (collections_decision_id) WHERE collections_decision_id IS NOT NULL;\n", "")),
    ("M115", "two executions of one order", "F2f",
     rep("CREATE UNIQUE INDEX service_order_field_visits_one_executed ON public.service_order_field_visits (service_order_id) WHERE outcome = 'executed';\n", "")),
    # ---- approvals
    ("M116", "an operator approves", "F3a",
     rep("    IF NOT public.session_is_supervisor() THEN", "    IF false THEN")),
    ("M117", "an approval for an order that is not a disconnect", "F3b6",
     rep("    IF FOUND AND o.order_type <> 'disconnect' THEN", "    IF false THEN")),
    ("M118", "a mismatch approval naming no visit", "F3b1",
     rep("        IF NOT FOUND OR v.service_order_id IS DISTINCT FROM NEW.service_order_id OR v.outcome <> 'aborted' OR v.matched",
         "        IF FOUND AND (v.service_order_id IS DISTINCT FROM NEW.service_order_id OR v.outcome <> 'aborted' OR v.matched)")),
    ("M119", "a mismatch approval naming another order's visit", "F3b4",
     rep("        IF NOT FOUND OR v.service_order_id IS DISTINCT FROM NEW.service_order_id OR v.outcome <> 'aborted' OR v.matched",
         "        IF NOT FOUND OR v.outcome <> 'aborted' OR v.matched")),
    ("M120", "a mismatch approval naming an execution", "F3b8",
     rep("        IF NOT FOUND OR v.service_order_id IS DISTINCT FROM NEW.service_order_id OR v.outcome <> 'aborted' OR v.matched",
         "        IF NOT FOUND OR v.service_order_id IS DISTINCT FROM NEW.service_order_id OR v.matched")),
    ("M121", "a mismatch approval naming a matched visit", "F3b2",
     rep("        IF NOT FOUND OR v.service_order_id IS DISTINCT FROM NEW.service_order_id OR v.outcome <> 'aborted' OR v.matched",
         "        IF NOT FOUND OR v.service_order_id IS DISTINCT FROM NEW.service_order_id OR v.outcome <> 'aborted'")),
    ("M122", "a mismatch approval with no evidence", "F3b3",
     rep("           OR NOT coalesce(NEW.evidence_ref ~ '[[:alnum:]]', false) THEN", "           THEN")),
    ("M123", "a no-evidence approval naming a visit", "F3b5",
     rep("    ELSIF NEW.visit_id IS NOT NULL THEN", "    ELSIF false THEN")),
    ("M124", "the approver is the caller's", "F3c",
     rep("    NEW.approved_by := NULLIF(current_setting('app.user_id', true), '')::uuid;\n", "")),
    # ---- do_not_disconnect
    ("M125", "do_not_disconnect written directly", "E4a",
     rep("            OR (TG_OP = 'UPDATE' AND NEW.do_not_disconnect IS DISTINCT FROM OLD.do_not_disconnect)) THEN", "            ) THEN")),
    ("M126", "a customer born protected", "E4b",
     rep("       AND ((TG_OP = 'INSERT' AND NEW.do_not_disconnect)\n", "       AND (false\n")),
    ("M127", "the fence counts the enrollment trigger as direct", "E4c",
     rep("    IF pg_trigger_depth() < 2\n       AND ((TG_OP = 'INSERT' AND NEW.do_not_disconnect)", "    IF pg_trigger_depth() < 3\n       AND ((TG_OP = 'INSERT' AND NEW.do_not_disconnect)")),
    ("M129", "the application may edit a decision", "V4",
     tail("GRANT UPDATE ON public.collections_decisions TO tally_app;")),
    ("M130", "a decision's bill bound without its customer", "C3b2",
     rep("    CONSTRAINT collections_decisions_invoice_fkey FOREIGN KEY (invoice_id, tenant_id, customer_id) REFERENCES public.invoices (id, tenant_id, customer_id),",
         "    CONSTRAINT collections_decisions_invoice_fkey FOREIGN KEY (invoice_id, tenant_id) REFERENCES public.invoices (id, tenant_id),")),
]



def sh(cmd: list[str], inp: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, input=inp, capture_output=True, text=True)


def sh_ordered(cmd: list[str], inp: str | None = None) -> subprocess.CompletedProcess:
    """stdout and stderr in one stream, in the order written."""
    return subprocess.run(cmd, input=inp, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)


def runner(check: str) -> tuple[list[str], str | None, str]:
    """The command, its input, and the check's bare name."""
    if re.fullmatch(r"CR\d+[a-z]?", check):
        return ["bash", str(HERE / "races/collections-26.sh"), DB], None, check
    # A mutation that loops must report, not hang: a timeout is a MISS (ERROR before the named FAIL).
    return ["docker", "exec", "-i", "-e", "PGOPTIONS=-c statement_timeout=300s", "tally-pg", "psql", "-U", "tally", "-d", DB, "-v", "ON_ERROR_STOP=1", "-q", "-o", "/dev/null", "-f", "-"], \
        (HERE / "battery-26.sql").read_text(), check


def main() -> int:
    base = PATCH.read_text()
    args = sys.argv[1:]
    anchors_only = "--anchors" in args
    only = {a for a in args if a != "--anchors"}
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
        if anchors_only:
            continue
        setup = [sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-qc", q])
                 for q in (f"DROP DATABASE IF EXISTS {DB}", f"CREATE DATABASE {DB} TEMPLATE {BASE}")]
        # A TEMPLATE clone does not copy the database ACL: revoke TEMP again.
        setup.append(sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", DB, "-v", "ON_ERROR_STOP=1", "-qc", f"REVOKE TEMP ON DATABASE {DB} FROM PUBLIC, tally_app, tally_core"]))
        if any(x.returncode for x in setup):
            print(f"{mid} SETUP-ERROR: {next(x.stderr.strip() for x in setup if x.returncode)[:140]}")
            missed += 1
            continue
        a = sh(["docker", "exec", "-i", "-e", "PGOPTIONS=-c search_path= -c check_function_bodies=on", "tally-pg",
                "psql", "-U", "tally", "-d", DB, "-v", "ON_ERROR_STOP=1", "-q", "-o", "/dev/null", "-f", "-"], patched)
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
        cmd, inp, name = runner(check)
        text = sh_ordered(cmd, inp).stdout
        first = next((l for l in text.splitlines() if "FAIL" in l or "ERROR" in l), "")
        first = re.sub(r"^psql:[^:]+:\d+: ", "", first)[:160]
        # The first line that reports any failure, infrastructure errors included, must be the named check's.
        fails = [re.sub(r"^.*?(FAIL )", r"\1", l) for l in text.splitlines() if re.search(r"\bFAIL\b|ERROR|FATAL|PANIC", l)]
        if fails and re.match(rf"FAIL {re.escape(name)}[:\s]", fails[0]):
            print(f"{mid} caught at {check}: {what}")
        else:
            print(f"{mid} MISSED ({check}): {what}  [first: {first}]")
            missed += 1
    if anchors_only:
        print(f"{ran - missed}/{ran} anchors unique")
        return 1 if missed else 0
    print(f"{ran - missed}/{ran} caught")
    sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-qc", f"DROP DATABASE IF EXISTS {DB}"])
    return 1 if missed else 0


if __name__ == "__main__":
    sys.exit(main())
