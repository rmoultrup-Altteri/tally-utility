#!/usr/bin/env python3
"""v5.4.2-25 — prove the -25 checks CATCH drift, not merely pass.

Each mutation alters a copy of the patch, applies it (strict: search_path ''
and function-body checking on) to a fresh clone of a base that has -23 and
not -25 (M25_BASE, default ci_pre25 — tests/ci.sh leaves it), with TEMP
revoked, and runs the script that owns the named check:

  battery check (S M K X U N D R T H)  battery-25.sql
  DR1-DR9                              races/disputes-25.sh
  APPLY:<phrase>                       the patch itself must refuse, with that phrase

CAUGHT only when the FIRST failure printed is the named check's (the -21
rule). A mutation an EARLIER check catches is reported as missed: its named
check is wrong, or a guard is redundant — fix the name or remove the
duplicate, never loosen the rule.

    python3 tests/v5.4.2-25/mutations-25.py [--anchors] [M01 M12 ...]
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[2]
PATCH = Path(os.environ.get("PATCH25") or ROOT / "sql/v5.4.2-25-disputes.sql")
HERE = ROOT / "tests/v5.4.2-25"
BASE = os.environ.get("M25_BASE", "ci_pre25")
DB = "m25"


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
    # ---- L2: the document checks
    ("M01", "a subject both listed and excluded", "X3",
     rep("     WHERE coalesce(p_doc #> '{subjects,excluded}', '[]'::jsonb) ? c;\n    IF v_bad IS NOT NULL THEN",
         "     WHERE false;\n    IF v_bad IS NOT NULL THEN")),
    ("M02", "a code listed twice", "X4",
     rep("GROUP BY c HAVING count(*) > 1) x;", "GROUP BY c HAVING count(*) > 2) x;")),
    ("M03", "a first stage filed from a prior decision", "X5",
     rep("    IF v_n > 0 AND v_stages #>> '{0,file_within,from}' = 'prior_decision' THEN", "    IF false THEN")),
    ("M04", "a final stage that is not the last", "X6",
     rep("     WHERE (s -> 'final') = 'true'::jsonb AND i < v_n;", "     WHERE (s -> 'final') = 'true'::jsonb AND i < v_n - 1;")),
    ("M05", "a duty outside the vocabulary", "X9",
     rep("     WHERE NOT EXISTS (SELECT 1 FROM public.dispute_duties d WHERE d.duty_code = c);", "     WHERE false;")),
    ("M06", "a law class outside the vocabulary is left to the FK", "X7",
     rep("    IF NOT EXISTS (SELECT 1 FROM public.dispute_customer_classes c\n                    WHERE c.state_code = p_row ->> 'state_code'",
         "    IF false AND NOT EXISTS (SELECT 1 FROM public.dispute_customer_classes c\n                    WHERE c.state_code = p_row ->> 'state_code'")),
    ("M07", "a subject outside the vocabulary passes the facet", "X1",
     rep("'$.subjects.codes[*]',    'public.dispute_subjects', 'subject_code', NULL,\n         'The subjects a listed document admits",
         "'$.subjects.codes[*]',    NULL, NULL, NULL,\n         'The subjects a listed document admits")),
    ("M08", "a block outside the vocabulary passes the facet", "X2",
     rep("'$.blocks.codes[*]',      'public.dispute_blocks',   'block_code',   NULL,\n         'What the shelter stops: each a dispute_blocks row. A sheltered determination records",
         "'$.blocks.codes[*]',      NULL, NULL,   NULL,\n         'What the shelter stops: each a dispute_blocks row. A sheltered determination records")),
    ("M09", "an excluded subject outside the vocabulary passes the tariff's facet", "U4",
     rep("'$.subjects.excluded[*]', 'public.dispute_subjects', 'subject_code', NULL,\n         'The subjects the policy excludes",
         "'$.subjects.excluded[*]', NULL, NULL, NULL,\n         'The subjects the policy excludes")),
    ("M10", "another utility writes a tariff", "U7",
     rep("    IF NOT public.is_platform_admin() AND (p_row ->> 'tenant_id')::uuid IS DISTINCT FROM public.get_user_tenant_id()\n"
         "       AND NOT coalesce((SELECT r.rolsuper OR r.rolbypassrls FROM pg_roles r WHERE r.rolname = current_user), false) THEN\n"
         "        RAISE EXCEPTION USING\n            MESSAGE = 'new row violates row-level security policy for table \"dispute_tariffs\"",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = 'new row violates row-level security policy for table \"dispute_tariffs\"")),
    # ---- L6: never looser than the law
    ("M11", "a tariff may block less than the law", "N1a",
     rep("         WHERE NOT (v_t #> '{blocks,codes}') ? c;", "         WHERE false;")),
    ("M12", "a tariff may admit fewer subjects", "N2a",
     rep("         WHERE NOT c = ANY (public.dispute_subjects_admitted(v_t -> 'subjects'));", "         WHERE false;")),
    ("M13", "a start outside the order passes", "N3a",
     rep("        ELSIF NOT (c_rank ? (v_te ->> 'kind') AND c_rank ? (v_le ->> 'kind')", "        ELSIF false AND NOT (c_rank ? (v_te ->> 'kind') AND c_rank ? (v_le ->> 'kind')")),
    ("M14", "a narrower start in the order passes", "N8a",
     rep("                   AND (c_rank ->> (v_te ->> 'kind'))::integer >= (c_rank ->> (v_le ->> 'kind'))::integer) THEN",
         "                   ) THEN")),
    ("M15", "a shorter window of days passes", "N7a",
     rep("            IF (v_te ->> 'days')::integer < (v_le ->> 'days')::integer OR v_te ->> 'from' <> v_le ->> 'from' THEN",
         "            IF v_te ->> 'from' <> v_le ->> 'from' THEN")),
    ("M16", "a window from another anchor passes", "N7b",
     rep("            IF (v_te ->> 'days')::integer < (v_le ->> 'days')::integer OR v_te ->> 'from' <> v_le ->> 'from' THEN",
         "            IF (v_te ->> 'days')::integer < (v_le ->> 'days')::integer THEN")),
    ("M17", "the law's unruled start is compared", "N4c",
     rep("        IF v_le ->> 'kind' = 'unruled' THEN\n            NULL;\n        ELSIF v_te ->> 'kind' = v_le ->> 'kind' AND v_le ->> 'kind' = 'within_days' THEN",
         "        IF false THEN\n            NULL;\n        ELSIF v_te ->> 'kind' = v_le ->> 'kind' AND v_le ->> 'kind' = 'within_days' THEN")),
    ("M18", "a sooner end in days passes", "N4a",
     rep("            IF v_le ->> 'kind' = 'earlier_of_resolution_and_days' AND (v_te ->> 'days')::integer < (v_le ->> 'days')::integer THEN",
         "            IF false THEN")),
    ("M19", "the law's own days are refused (boundary)", "N4c",
     rep("            IF v_le ->> 'kind' = 'earlier_of_resolution_and_days' AND (v_te ->> 'days')::integer < (v_le ->> 'days')::integer THEN",
         "            IF v_le ->> 'kind' = 'earlier_of_resolution_and_days' AND (v_te ->> 'days')::integer <= (v_le ->> 'days')::integer THEN")),
    ("M20", "an end outside the order passes", "N4d",
     rep("        ELSIF NOT (v_te ->> 'kind' = 'resolution' AND v_le ->> 'kind' = 'earlier_of_resolution_and_days') THEN",
         "        ELSIF false THEN")),
    ("M21", "a must-pay that asks more passes", "N5a",
     rep("            v_problem := v_problem || format('must_pay: %s asks for %s; the tariff''s %s asks more or is not comparable (fail toward protection)',",
         "            v_problem := v_problem || NULL::text; PERFORM format('must_pay: %s asks for %s; the tariff''s %s asks more or is not comparable (fail toward protection)',")),
    ("M22", "the average cap's figures are not compared", "N5b",
     rep("              AND (v_tp -> 'history_years') = (v_lp -> 'history_years') AND (v_tp -> 'no_history') = (v_lp -> 'no_history') THEN",
         "              THEN")),
    ("M23", "withholding less passes", "N7d",
     rep("            IF (v_tp ->> 'fraction')::numeric < (v_lp ->> 'fraction')::numeric THEN", "            IF false THEN")),
    ("M24", "the law's own cap is refused (boundary)", "N7e",
     rep("            IF (v_tp ->> 'fraction')::numeric < (v_lp ->> 'fraction')::numeric THEN",
         "            IF (v_tp ->> 'fraction')::numeric <= (v_lp ->> 'fraction')::numeric THEN")),
    ("M25", "a delegation is compared", "U1",
     rep("        CONTINUE WHEN v_l ->> 'governs' IS DISTINCT FROM 'law';", "")),
    # ---- the seed and the floors
    ("M26", "the protected row loses late_fee", "K2",
     rep("\"blocks\\\":{\\\"citation\\\":\\\"16 TAC 7.45(6)(D)(ii)\\\",\\\"codes\\\":[\\\"disconnect_order\\\",\\\"disconnect_execute\\\",\\\"late_fee\\\"]}",
         "\"blocks\\\":{\\\"citation\\\":\\\"16 TAC 7.45(6)(D)(ii)\\\",\\\"codes\\\":[\\\"disconnect_order\\\",\\\"disconnect_execute\\\"]}")),
    ("M27", "a cited law row closes on its citation's date", "H2",
     rep("    RETURN (SELECT max(d.received_on) FROM public.dispute_determinations x JOIN public.disputes d ON d.id = x.dispute_id\n             WHERE x.rule_id = p_rule_id);",
         "    RETURN NULL;")),
    ("M28", "a cited tariff closes on its citation's date", "H4",
     rep("    RETURN (SELECT max(d.received_on) FROM public.dispute_determinations x JOIN public.disputes d ON d.id = x.dispute_id\n             WHERE x.tariff_id = p_tariff_id);",
         "    RETURN NULL;")),
    # ---- D1: the dispute
    ("M29", "a subject outside the vocabulary is left to the FK", "D1m",
     rep("    IF NOT EXISTS (SELECT 1 FROM public.dispute_subjects s WHERE s.subject_code = NEW.subject) THEN", "    IF false THEN")),
    ("M30", "a dispute naming nothing", "D1f",
     rep("    IF NEW.invoice_id IS NULL AND NEW.reading_id IS NULL THEN", "    IF false THEN")),
    ("M31", "a dispute born resolved", "D1o",
     rep("    IF NEW.status IS DISTINCT FROM 'open' OR NEW.status_cause_id IS NOT NULL OR NEW.status_recorded_at IS NOT NULL THEN", "    IF false THEN")),
    ("M32", "a draft bill disputed", "D1h",
     rep("            IF v_issued IS NULL THEN", "            IF false THEN")),
    ("M33", "a dispute received before its bill", "D1j",
     rep("            IF NEW.received_on < v_date THEN\n                RAISE EXCEPTION USING\n                    MESSAGE = format('dispute: received %s, before the bill''s date",
         "            IF false THEN\n                RAISE EXCEPTION USING\n                    MESSAGE = format('dispute: received %s, before the bill''s date")),
    ("M34", "a dispute received on the bill's date is refused (boundary)", "D1j2",
     rep("            IF NEW.received_on < v_date THEN\n                RAISE EXCEPTION USING\n                    MESSAGE = format('dispute: received %s, before the bill''s date",
         "            IF NEW.received_on <= v_date THEN\n                RAISE EXCEPTION USING\n                    MESSAGE = format('dispute: received %s, before the bill''s date")),
    ("M35", "a reading of another customer's location", "D1i",
     rep("            IF v_holder IS DISTINCT FROM NEW.customer_id THEN", "            IF false THEN")),
    ("M36", "a dispute received before its reading", "D1k",
     rep("            IF NEW.received_on < v_date THEN\n                RAISE EXCEPTION USING\n                    MESSAGE = format('dispute: received %s, before the reading",
         "            IF false THEN\n                RAISE EXCEPTION USING\n                    MESSAGE = format('dispute: received %s, before the reading")),
    ("M37", "a dispute received in the future", "D1l",
     rep("    IF NEW.received_on > current_date THEN", "    IF false THEN")),
    ("M38", "a dispute's identity may change", "D1s",
     rep("    IF (to_jsonb(NEW) - c_moved) IS DISTINCT FROM (to_jsonb(OLD) - c_moved) THEN", "    IF false THEN")),
    ("M39", "a dispute's status may be written directly", "D1t",
     rep("    IF NOT EXISTS (SELECT 1 FROM public.dispute_events e\n                    WHERE e.id = NEW.status_cause_id AND e.dispute_id = NEW.id AND e.event_type = NEW.status",
         "    IF false AND NOT EXISTS (SELECT 1 FROM public.dispute_events e\n                    WHERE e.id = NEW.status_cause_id AND e.dispute_id = NEW.id AND e.event_type = NEW.status")),
    ("M40", "no opened event", "D1b",
     rep("CREATE TRIGGER z_dispute_opened_event AFTER INSERT ON public.disputes FOR EACH ROW EXECUTE FUNCTION public.dispute_opened_event();\n"
         "ALTER TABLE public.disputes ENABLE ALWAYS TRIGGER z_dispute_opened_event;\n", "")),
    ("M41", "the application may update a dispute", "D1p",
     tail("GRANT UPDATE ON public.disputes TO tally_app;")),
    # ---- D2: amounts and lines
    ("M42", "another utility writes an amount", "D2n",
     rep("    PERFORM public.dispute_tenant_check('dispute_amounts', NEW.tenant_id);\n", "")),
    ("M43", "an amount after the resolution", "D2m",
     rep("    IF d.status <> 'open' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('disputed amount:",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('disputed amount:")),
    ("M44", "an amount effective before the dispute", "D2f",
     rep("    IF NEW.effective_on < d.received_on OR NEW.effective_on > current_date OR NEW.created_at < d.created_at THEN", "    IF false THEN")),
    ("M45", "an amount takes no dispute lock", "DR8",
     rep("    d := public.dispute_lock(NEW.dispute_id, 'a disputed amount');",
         "    SELECT * INTO d FROM public.disputes y WHERE y.id = NEW.dispute_id;")),
    ("M46", "another utility writes a line", "D2o",
     rep("    PERFORM public.dispute_tenant_check('dispute_amount_lines', NEW.tenant_id);\n", "")),
    ("M47", "a reading dispute's amount takes bill lines", "D2j",
     rep("    IF v_invoice IS NULL THEN", "    IF false THEN")),
    ("M48", "a line added in a later transaction", "DR9",
     rep("    IF v_txid IS DISTINCT FROM txid_current() THEN", "    IF false THEN")),
    ("M49", "a line's bill is the caller's", "D2b",
     rep("    NEW.invoice_id := v_invoice;\n", "")),
    ("M50", "a line above its charge", "D2c",
     rep("    IF FOUND AND (v_charge <= 0 OR NEW.amount > v_charge) THEN", "    IF FOUND AND v_charge <= 0 THEN")),
    ("M51", "a line at its whole charge is refused (boundary)", "D2",
     rep("    IF FOUND AND (v_charge <= 0 OR NEW.amount > v_charge) THEN", "    IF FOUND AND (v_charge <= 0 OR NEW.amount >= v_charge) THEN")),
    ("M52", "a credit line disputed", "D2c2",
     rep("    IF FOUND AND (v_charge <= 0 OR NEW.amount > v_charge) THEN", "    IF FOUND AND NEW.amount > v_charge AND v_charge > 0 THEN")),
    ("M53", "lines that do not add up", "D2a",
     rep("    IF v_sum IS DISTINCT FROM v_amount THEN", "    IF false THEN")),
    # ---- D3/D4: the determination
    ("M54", "another utility writes a determination", "D4z2",
     rep("    PERFORM public.dispute_tenant_check('dispute_determinations', NEW.tenant_id);\n", "")),
    ("M55", "a determination after the resolution", "D4k",
     rep("    IF d.status <> 'open' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('dispute determination:",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('dispute determination:")),
    ("M56", "an event at REPEATABLE READ (a determination meets -17's own check first)", "DR7b",
     rep("    IF current_setting('transaction_isolation') <> 'read committed' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s runs only under READ COMMITTED: the dispute",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s runs only under READ COMMITTED: the dispute")),
    ("M57", "the dispute's lock is not taken", "DR1",
     rep("    PERFORM pg_advisory_xact_lock(public.dispute_lock_key(p_dispute_id));\n", "")),
    ("M58", "an amount row of another dispute", "D4j",
     rep("    IF NOT FOUND OR a.dispute_id <> d.id OR a.created_at > NEW.created_at THEN", "    IF NOT FOUND THEN")),
    ("M59", "a second live determination", "D4m",
     rep("        IF EXISTS (SELECT 1 FROM public.dispute_determinations x WHERE x.dispute_id = d.id) THEN", "        IF false THEN")),
    ("M60", "a superseded row superseded again", "D4s",
     rep("           OR EXISTS (SELECT 1 FROM public.dispute_determinations x WHERE x.supersedes_id = p.id) THEN", "           THEN")),
    ("M61", "another dispute's determination superseded", "D4t",
     rep("        IF NOT FOUND OR p.dispute_id <> d.id OR p.created_at > NEW.created_at", "        IF NOT FOUND OR p.created_at > NEW.created_at")),
    ("M62", "a class outside the vocabulary is left to the FK", "D4p",
     rep("    IF NOT EXISTS (SELECT 1 FROM public.dispute_customer_classes c\n                    WHERE c.state_code = NEW.state_code",
         "    IF false AND NOT EXISTS (SELECT 1 FROM public.dispute_customer_classes c\n                    WHERE c.state_code = NEW.state_code")),
    ("M63", "a law row not the one in force for the utility", "D4a",
     rep("    IF v_expected IS DISTINCT FROM NEW.rule_id THEN", "    IF false THEN")),
    ("M64", "a law citation takes no lock", "DR6b",
     rep("    PERFORM public.rule_law_row_cite('public.dispute_rules', NEW.rule_id, NEW.tenant_id, NEW.service_type, NEW.system_kind, NEW.state_code,\n"
         "                                     jsonb_build_object('customer_class', NEW.customer_class), d.received_on);\n", "")),
    ("M65", "another utility's tariff", "D4f",
     rep("        IF NOT FOUND OR t.tenant_id <> NEW.tenant_id OR t.state_code <> NEW.state_code OR t.service_type <> NEW.service_type\n           OR t.system_kind <> NEW.system_kind THEN",
         "        IF false THEN")),
    ("M66", "a tariff not in force", "D4c",
     rep("        IF NOT daterange(t.effective_from, t.effective_to, '[)') @> d.received_on THEN", "        IF false THEN")),
    ("M67", "a tariff citation takes no lock", "DR6",
     rep("        PERFORM public.rule_row_cite('public.dispute_tariffs', NEW.tariff_id, d.received_on);\n", "")),
    ("M68", "a delegation shelters with no tariff", "D4d",
     rep("        IF NEW.outcome <> 'no_terms' THEN", "        IF false THEN")),
    ("M69", "no terms while a policy is in force", "D4e",
     rep("        IF public.rule_tariff_row_as_of('public.dispute_tariffs', NEW.tenant_id, NEW.service_type, NEW.system_kind, NEW.state_code, '{}'::jsonb, d.received_on) IS NOT NULL THEN",
         "        IF false THEN")),
    ("M70", "no terms that shelters something", "D4n",
     rep("    IF NEW.outcome = 'no_terms' AND (NEW.sheltered_amount <> 0 OR", "    IF NEW.outcome = 'no_terms' AND (false OR")),
    ("M71", "not sheltered that shelters something", "D4z",
     rep("    IF NEW.outcome = 'not_sheltered' AND (NEW.sheltered_amount <> 0 OR", "    IF NEW.outcome = 'not_sheltered' AND (false OR")),
    ("M72", "sheltered with no amount to pay", "D4n3",
     rep("    IF NEW.outcome = 'sheltered' AND (NEW.must_pay_amount IS NULL OR NEW.must_pay_component IS NULL) THEN", "    IF false THEN")),
    ("M73", "a component the document does not have", "D4g",
     rep("        IF NOT coalesce(v_doc #>> '{must_pay,id}' = NEW.must_pay_component, false) THEN", "        IF false THEN")),
    ("M74", "blocks other than the document's", "D4h",
     rep("            IF (SELECT coalesce(array_agg(DISTINCT b ORDER BY b), '{}') FROM unnest(NEW.blocks) b) IS DISTINCT FROM v_blocks\n"
         "               OR cardinality(NEW.blocks) <> cardinality(v_blocks) THEN",
         "            IF cardinality(NEW.blocks) <> cardinality(v_blocks) THEN")),
    ("M75", "the document's blocks with one repeated", "D4h2",
     rep("               OR cardinality(NEW.blocks) <> cardinality(v_blocks) THEN", "               THEN")),
    ("M76", "more sheltered than the amount", "D4i",
     rep("    IF NEW.sheltered_amount < 0 OR NEW.sheltered_amount > a.amount OR NEW.must_pay_amount < 0 THEN",
         "    IF NEW.sheltered_amount < 0 OR NEW.must_pay_amount < 0 THEN")),
    ("M77", "the whole amount sheltered is refused (boundary)", "D3",
     rep("    IF NEW.sheltered_amount < 0 OR NEW.sheltered_amount > a.amount OR NEW.must_pay_amount < 0 THEN",
         "    IF NEW.sheltered_amount < 0 OR NEW.sheltered_amount >= a.amount OR NEW.must_pay_amount < 0 THEN")),
    ("M78", "a negative amount to pay is left to the CHECK", "D4i2",
     rep("    IF NEW.sheltered_amount < 0 OR NEW.sheltered_amount > a.amount OR NEW.must_pay_amount < 0 THEN",
         "    IF NEW.sheltered_amount < 0 OR NEW.sheltered_amount > a.amount THEN")),
    ("M79", "a shelter ending before the dispute", "D4o",
     rep("    IF NEW.shelter_ends_on < d.received_on THEN", "    IF false THEN")),
    # ---- D5: events and the status move
    ("M80", "the application writes an opened event", "D5a",
     rep("           OR EXISTS (SELECT 1 FROM public.dispute_events e WHERE e.dispute_id = NEW.dispute_id) THEN", "           THEN")),
    ("M81", "another utility writes an event", "D5w",
     rep("    PERFORM public.dispute_tenant_check('dispute_events', NEW.tenant_id);\n", "")),
    ("M82", "an event after the resolution", "D5o",
     rep("    IF d.status <> 'open' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('dispute event:",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('dispute event:")),
    ("M83", "an event before the dispute", "D5g",
     rep("    IF NEW.occurred_on < d.received_on OR NEW.occurred_on > current_date OR NEW.created_at < d.created_at THEN", "    IF false THEN")),
    ("M84", "a resolution with no outcome is left to the CHECK", "D5h",
     rep("    IF (NEW.event_type = 'resolved') <> (NEW.outcome IS NOT NULL)\n       OR (NEW.outcome = 'adjusted' AND v_n <> 1)",
         "    IF false\n       OR (NEW.outcome = 'adjusted' AND v_n <> 1)")),
    ("M85", "an adjusted resolution naming nothing", "D5i",
     rep("       OR (NEW.outcome = 'adjusted' AND v_n <> 1)\n", "       OR (NEW.outcome = 'adjusted' AND v_n > 1)\n")),
    ("M86", "a sustained resolution naming a correction", "D5k",
     rep("       OR (NEW.outcome IS DISTINCT FROM 'adjusted' AND v_n <> 0) THEN", "       THEN")),
    ("M87", "an adjustment of another customer", "D5l",
     rep("        IF v_cust IS DISTINCT FROM d.customer_id OR v_kind IS DISTINCT FROM 'adjustment' THEN", "        IF v_kind IS DISTINCT FROM 'adjustment' THEN")),
    ("M88", "a credit that is not a dispute resolution", "D5l2",
     rep("        IF v_cust IS DISTINCT FROM d.customer_id OR v_kind IS DISTINCT FROM 'dispute_resolution' THEN", "        IF v_cust IS DISTINCT FROM d.customer_id THEN")),
    ("M89", "another customer's bill as a correction", "D5l3",
     rep("        IF v_cust IS DISTINCT FROM d.customer_id THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('dispute event: bill %s",
         "        IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('dispute event: bill %s")),
    ("M90", "a stage event with no determination", "D5e",
     rep("        IF x.id IS NULL THEN", "        IF false THEN")),
    ("M91", "a stage the document does not have", "D5c",
     rep("        IF v_stage IS NULL OR NEW.decider_role IS DISTINCT FROM v_stage ->> 'decider' OR NEW.decider_user_id IS NULL THEN",
         "        IF NEW.decider_role IS DISTINCT FROM v_stage ->> 'decider' AND v_stage IS NOT NULL THEN")),
    ("M92", "a decider other than the stage's", "D5d",
     rep("        IF v_stage IS NULL OR NEW.decider_role IS DISTINCT FROM v_stage ->> 'decider' OR NEW.decider_user_id IS NULL THEN",
         "        IF v_stage IS NULL THEN")),
    ("M93", "a non-stage event naming a stage", "D5x",
     rep("    ELSIF NEW.stage_id IS NOT NULL OR NEW.decider_role IS NOT NULL OR NEW.decider_user_id IS NOT NULL THEN", "    ELSIF false THEN")),
    ("M94", "an event takes no dispute lock", "DR3",
     rep("    d := public.dispute_lock(NEW.dispute_id, 'a dispute event');", "    SELECT * INTO d FROM public.disputes y WHERE y.id = NEW.dispute_id;")),
    ("M95", "the resolution does not move the status", "D5n",
     rep("CREATE TRIGGER z_dispute_move_status AFTER INSERT ON public.dispute_events FOR EACH ROW\n"
         "    WHEN (NEW.event_type = ANY (ARRAY['resolved'::text, 'withdrawn'::text])) EXECUTE FUNCTION public.dispute_move_status();\n"
         "ALTER TABLE public.dispute_events ENABLE ALWAYS TRIGGER z_dispute_move_status;\n", "")),
    # ---- D6: the readers
    ("M96", "the shelter reader needs no coordinates", "R1",
     rep("    PERFORM public.cash_coordinates_required('dispute_shelter_as_of', p_on, p_recorded_at);\n", "")),
    ("M97", "a dispute is read before it was recorded", "R4b",
     rep("     WHERE d.invoice_id = p_invoice_id AND d.created_at <= p_recorded_at AND d.received_on <= p_on",
         "     WHERE d.invoice_id = p_invoice_id AND d.received_on <= p_on")),
    ("M98", "a dispute is read before it was received", "R6",
     rep("     WHERE d.invoice_id = p_invoice_id AND d.created_at <= p_recorded_at AND d.received_on <= p_on",
         "     WHERE d.invoice_id = p_invoice_id AND d.created_at <= p_recorded_at")),
    ("M99", "a determination is read before it was recorded", "R3",
     rep("             WHERE y.dispute_id = d.id AND y.created_at <= p_recorded_at\n", "             WHERE y.dispute_id = d.id\n")),
    ("M100", "a supersession is read before it was recorded", "R3",
     rep("WHERE z.supersedes_id = y.id AND z.created_at <= p_recorded_at)", "WHERE z.supersedes_id = y.id)")),
    ("M101", "the resolution is read before its date", "R2",
     rep("                          AND e.created_at <= p_recorded_at AND e.occurred_on <= p_on)", "                          AND e.created_at <= p_recorded_at)")),
    ("M102", "the resolution is read before it was recorded", "R5b",
     rep("                          AND e.created_at <= p_recorded_at AND e.occurred_on <= p_on)", "                          AND e.occurred_on <= p_on)")),
    ("M103", "the shelter outlives its last day", "R7b",
     rep("           CASE WHEN x.id IS NULL OR x.shelter_ends_on < p_on THEN 0::numeric ELSE x.sheltered_amount END,",
         "           CASE WHEN x.id IS NULL THEN 0::numeric ELSE x.sheltered_amount END,")),
    ("M104", "the shelter ends on its last day (boundary)", "R7",
     rep("           CASE WHEN x.id IS NULL OR x.shelter_ends_on < p_on THEN 0::numeric ELSE x.sheltered_amount END,",
         "           CASE WHEN x.id IS NULL OR x.shelter_ends_on <= p_on THEN 0::numeric ELSE x.sheltered_amount END,")),
    ("M105", "the line reader spreads over credit lines too", "R8",
     rep("                 WHERE NOT sh.has_lines AND il.invoice_id = line.invoice_id AND il.amount > 0) w",
         "                 WHERE NOT sh.has_lines AND il.invoice_id = line.invoice_id) w")),
    ("M106", "the line reader ignores the amount's lines", "R8b",
     rep("                 WHERE sh.has_lines AND al.dispute_amount_id = sh.dispute_amount_id\n", "                 WHERE false AND al.dispute_amount_id = sh.dispute_amount_id\n")),
    # ---- T: the meaning changes
    ("M107", "pending_dispute still protects", "T1a",
     rep("   SET is_disconnect_protective = false,\n", "   SET is_disconnect_protective = true,\n")),
    ("M108", "pending_dispute takes enrollments", "T1c",
     rep("    IF NEW.program_type = 'pending_dispute' AND (TG_OP = 'INSERT' OR OLD.program_type IS DISTINCT FROM NEW.program_type) THEN", "    IF false THEN")),
    ("M109", "a reading marked disputed with no open dispute", "T2b",
     rep("    IF NEW.status = 'disputed' AND NOT v_open THEN", "    IF false THEN")),
    ("M110", "a reading unmarked while its dispute is open", "T2d",
     rep("    IF OLD.status = 'disputed' AND v_open THEN", "    IF false THEN")),
]


def sh(cmd: list[str], inp: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, input=inp, capture_output=True, text=True)


def sh_ordered(cmd: list[str], inp: str | None = None) -> subprocess.CompletedProcess:
    """stdout and stderr in one stream, in the order written."""
    return subprocess.run(cmd, input=inp, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)


def runner(check: str) -> tuple[list[str], str | None, str]:
    """The command, its input, and the check's bare name."""
    if re.fullmatch(r"DR\d+[a-z]?", check):
        return ["bash", str(HERE / "races/disputes-25.sh"), DB], None, check
    # A mutation that loops must report, not hang: a timeout is a MISS (ERROR before the named FAIL).
    return ["docker", "exec", "-i", "-e", "PGOPTIONS=-c statement_timeout=300s", "tally-pg", "psql", "-U", "tally", "-d", DB, "-v", "ON_ERROR_STOP=1", "-q", "-o", "/dev/null", "-f", "-"], \
        (HERE / "battery-25.sql").read_text(), check


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
