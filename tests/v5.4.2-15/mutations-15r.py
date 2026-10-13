#!/usr/bin/env python3
"""v5.4.2-15 (rewrite) — prove the checks CATCH drift, not merely pass.

Each mutation alters a copy of the patch and is judged by the script that owns the named check:

  battery check (D X K S M C U N P F R A V Q H)   battery-15r.sql, run to the end past failures, on a clone of
                                                   `tally` with the mutated patch applied
  MIG:P1f MIG:P2 ...                               migration-15r.py with PATCH15 = the mutated patch
  APPLY:<phrase>                                   the mutated patch itself must refuse, with that phrase

CAUGHT only when the named check prints its own FAIL line (the battery runs on past a failure, so a mutation
that several checks catch is caught by the one named). A mutation another check catches but the named one does
not is reported as missed: the name is wrong or the check is too narrow — fix that, never loosen the rule.

Needs a PRE-15 base (`tally` while -15 is not mirrored); runs a few mutations at a time on separate clones:

    python3 tests/v5.4.2-15/mutations-15r.py [M01 M07 ...]
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[2]
PATCH = ROOT / "sql/v5.4.2-15-deposits-law-to-core.sql"
HERE = ROOT / "tests/v5.4.2-15"
WORKERS = int(os.environ.get("MUT_WORKERS", "4"))


def rep(old: str, new: str) -> Callable[[str], str]:
    def m(s: str) -> str:
        assert s.count(old) == 1, f"mutation anchor not unique/found ({s.count(old)}): {old[:90]!r}"
        return s.replace(old, new, 1)
    return m


def off(cond: str) -> Callable[[str], str]:
    """Replace an `IF <cond> THEN` (unique) with `IF false THEN`."""
    return rep(cond, "IF false THEN")


MUTATIONS: list[tuple[str, str, str, Callable[[str], str]]] = [
    # ---- the close floor
    ("M01", "the floor ignores deposits", "R25",
     rep("SELECT d.posted_on AS d FROM public.deposits d WHERE d.rule_id = p_rule_id", "SELECT NULL::date WHERE false")),
    ("M02", "the floor ignores return-due rows", "H13",
     rep("SELECT r.due_on FROM public.deposit_return_due r WHERE r.rule_id = p_rule_id", "SELECT NULL::date WHERE false")),
    ("M03", "the floor is the earliest citation", "H13",
     rep("SELECT max(c.d) INTO v_floor FROM (", "SELECT min(c.d) INTO v_floor FROM (")),
    ("M04", "the tariff floor ignores deposits", "R26",
     rep("RETURN (SELECT max(d.posted_on) FROM public.deposits d WHERE d.tariff_id = p_tariff_id);", "RETURN NULL;")),
    # ---- the law table's insert check
    ("M05", "a single cap may have two parts", "X2", off("IF v_comb = 'single' AND v_n <> 1 THEN")),
    ("M06", "a lesser-of cap may have one part", "X3", off("IF v_comb <> 'single' AND v_n < 2 THEN")),
    ("M07", "a cap kind may be named twice", "X1",
     rep("        IF v_dup IS NOT NULL THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('%s: the cap names the cap part kind", "        IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('%s: the cap names the cap part kind")),
    ("M08", "cap parts may be in any order", "X4",
     rep("        IF (SELECT array_agg(p ->> 'kind' ORDER BY o) IS DISTINCT FROM", "        IF false AND (SELECT array_agg(p ->> 'kind' ORDER BY o) IS DISTINCT FROM")),
    ("M09", "instalments need not add up to one", "X5",
     rep("        IF v_sum IS DISTINCT FROM 1 THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('%s: the instalment fractions add up to %s; they must add up to exactly 1 (v5.4.2-15)', v_who, v_sum), ERRCODE = 'check_violation';\n        END IF;\n        IF EXISTS",
         "        IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('%s: the instalment fractions add up to %s; they must add up to exactly 1 (v5.4.2-15)', v_who, v_sum), ERRCODE = 'check_violation';\n        END IF;\n        IF EXISTS")),
    ("M10", "instalments may be out of order", "X6", rep("WHERE x.prev IS NOT NULL AND x.d <= x.prev", "WHERE false")),
    ("M11", "a waiver may reach a trigger the document lacks", "X9", rep("WHERE w #>> '{applies_to,kind}' = 'trigger'", "WHERE false")),
    ("M12", "a trigger code may be used twice", "X10",
     rep("     GROUP BY t ->> 'trigger_code' HAVING count(*) > 1 ORDER BY 1 LIMIT 1;", "     GROUP BY t ->> 'trigger_code' HAVING count(*) > 99 ORDER BY 1 LIMIT 1;")),
    ("M13", "a return reason may be used twice", "X12",
     rep("     GROUP BY r #>> '{when,reason}' HAVING count(*) > 1 ORDER BY 1 LIMIT 1;", "     GROUP BY r #>> '{when,reason}' HAVING count(*) > 99 ORDER BY 1 LIMIT 1;")),
    ("M14", "a return on entering a waiver class needs no such waiver", "X11", rep("WHERE r #>> '{when,reason}' = 'entered_waiver_class'", "WHERE false")),
    ("M15", "by-hold thresholds may descend", "X13", rep("WHERE x.prev IS NOT NULL AND x.m <= x.prev", "WHERE false")),
    ("M16", "a published rate need not be registered", "P4", rep("WHERE NOT EXISTS (SELECT 1 FROM public.rule_parameters p WHERE p.parameter_name = x.n);", "WHERE false;")),
    ("M17", "a law row may be written for the carried-history basis", "D9",
     off("IF NOT EXISTS (SELECT 1 FROM public.deposit_bases b WHERE b.basis_code = p_row ->> 'basis' AND b.insertable) THEN")),
    ("M18", "a disqualifier need not be in its vocabulary", "X14",
     rep("     WHERE NOT EXISTS (SELECT 1 FROM public.deposit_refund_disqualifiers q WHERE q.disqualifier_code = d);", "     WHERE false;")),
    # ---- the tariff table
    ("M19", "a tariff for a category the utility has not defined", "U4",
     rep("    IF NOT EXISTS (SELECT 1 FROM public.deposit_utility_categories c\n                    WHERE c.tenant_id = (p_row ->> 'tenant_id')::uuid", "    IF false AND NOT EXISTS (SELECT 1 FROM public.deposit_utility_categories c\n                    WHERE c.tenant_id = (p_row ->> 'tenant_id')::uuid")),
    ("M20", "a tariff trigger code need not be in the vocabulary", "N13",
     rep("     WHERE NOT EXISTS (SELECT 1 FROM public.deposit_triggers x WHERE x.trigger_code = t ->> 'trigger_code');", "     WHERE false;")),
    ("M21", "the amount is not compared", "N1", rep("ELSIF v_months > v_allowed THEN", "ELSIF false THEN")),
    ("M22", "the law's own figure is looser", "N2", rep("ELSIF v_months > v_allowed THEN", "ELSIF v_months >= v_allowed THEN")),
    ("M23", "a fraction of annual billing is converted wrongly", "N2", rep("WHEN 'fraction_of_annual_billing' THEN 12 / (v_part ->> 'divisor')::numeric", "WHEN 'fraction_of_annual_billing' THEN 6 / (v_part ->> 'divisor')::numeric")),
    ("M24", "every class's law is compared", "N10",
     rep("WHERE r ->> 'customer_class' = v_class AND r #>> '{terms,governs}' = 'law' LOOP", "WHERE r #>> '{terms,governs}' = 'law' LOOP")),
    ("M25", "a trigger that fires sooner is not looser", "N5", rep("IF (v_tc ->> 'value')::numeric < (v_lc ->> 'value')::numeric", "IF (v_tc ->> 'value')::numeric > (v_lc ->> 'value')::numeric")),
    ("M26", "a missing days-to-pay guard counts as the law's", "N14", rep("IF coalesce(v_tg, 0) < v_lg THEN", "IF coalesce(v_tg, v_lg) < v_lg THEN")),
    ("M27", "the law's own days to pay is looser", "N15", rep("IF coalesce(v_tg, 0) < v_lg THEN", "IF coalesce(v_tg, 0) <= v_lg THEN")),
    ("M28", "fewer days to pay are fine", "N7", rep("IF coalesce(v_tg, 0) < v_lg THEN", "IF coalesce(v_tg, 0) < 0 THEN")),
    # ---- the categories
    ("M29", "a category may be edited", "C7", rep("    IF TG_OP = 'UPDATE' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit category", "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit category")),
    # ---- the rate floor
    ("M30", "no floor", "F1", off("IF v_floor IS NOT NULL AND NEW.annual_rate < v_floor THEN")),
    ("M31", "a rate equal to the floor is below it", "F2", rep("IF v_floor IS NOT NULL AND NEW.annual_rate < v_floor THEN", "IF v_floor IS NOT NULL AND NEW.annual_rate <= v_floor THEN")),
    ("M32", "the by-hold values are not part of the floor", "F9",
     rep("                              UNION SELECT h ->> 'name' FROM jsonb_array_elements(v_row.terms #> '{interest,rate,by_hold}') h LOOP", "                              LOOP")),
    ("M33", "the floor is the least of the values named", "F9",
     rep("v_val := public.deposit_published_rate(v_name, p_state_code, p_service_type, p_on);\n                    v_floor := greatest(v_floor, v_val);",
         "v_val := public.deposit_published_rate(v_name, p_state_code, p_service_type, p_on);\n                    v_floor := least(coalesce(v_floor, v_val), v_val);")),
    ("M34", "a rate named only as a reference binds", "F8", rep("                        AND r.terms #>> '{interest,rate,binding}' = 'minimum' LOOP", "                        LOOP")),
    ("M35", "a category is held to no class", "F7",
     rep("        SELECT array_agg(c.law_class) INTO v_classes FROM public.deposit_utility_categories c\n         WHERE c.tenant_id = p_tenant_id AND c.state_code = p_state_code AND c.service_type = p_service_type AND c.category_code = p_category;",
         "        v_classes := NULL;")),
    ("M36", "no published value known: no floor", "F4",
     rep("        RAISE EXCEPTION USING\n            MESSAGE = format('there is no published value of", "        RETURN NULL;\n        RAISE EXCEPTION USING\n            MESSAGE = format('there is no published value of")),
    ("M37", "a utility with no profile has no floor", "F16", off("IF NOT v_seen THEN")),
    ("M38", "a settled accrual may be re-rated", "A18", off("IF v_settled IS NOT NULL AND NEW.effective_date <= v_settled THEN")),
    ("M39", "a rate for an undefined category", "F13", rep("    IF NEW.tariff_category IS NOT NULL AND NOT EXISTS (", "    IF false AND NOT EXISTS (")),
    ("M40", "the lookup ignores the category's own row", "F14", rep("AND r.tariff_category = p_category AND r.effective_date <= p_on", "AND false")),
    ("M41", "a different class's floor is used for a category", "F10",
     rep("customer_class = ANY (coalesce(v_classes, '{}'))\n                        AND r.owner_span", "customer_class IS NOT NULL\n                        AND r.owner_span")),
    # ---- deposits
    ("M42", "a law row of another class may be cited", "R3",
     rep("PERFORM public.rule_law_row_cite('public.deposit_rules'::regclass, NEW.rule_id, NEW.tenant_id, NEW.service_type, NEW.system_kind, NEW.state_code,\n                                         jsonb_build_object('customer_class', NEW.customer_class, 'basis', NEW.basis), NEW.posted_on);",
         "PERFORM public.rule_row_cite('public.deposit_rules'::regclass, NEW.rule_id, NEW.posted_on);")),
    ("M43", "a category of another class", "R10", off("IF v_cat.law_class <> NEW.customer_class THEN")),
    ("M44", "a tariff row other than the one in force", "R14", off("IF v_expect IS DISTINCT FROM NEW.tariff_id THEN")),
    ("M45", "a delegated law row needs no tariff", "R13", rep("ELSIF v_doc ->> 'governs' = 'delegated_to_utility' THEN", "ELSIF false THEN")),
    ("M46", "a capped document needs no recorded cap", "R5", rep("            IF NEW.cap_amount IS NULL THEN\n                RAISE EXCEPTION USING\n                    MESSAGE = format('deposit rejected: law row %s caps the deposit", "            IF false THEN\n                RAISE EXCEPTION USING\n                    MESSAGE = format('deposit rejected: law row %s caps the deposit")),
    ("M47", "a statutory cap names any part", "R6", off("IF v_part IS NULL THEN")),
    ("M48", "a tariff cap cites no tariff row", "R17", off("IF NEW.cap_source = 'tariff' AND NEW.tariff_id IS NULL THEN")),
    ("M49", "the measure observed need not meet the threshold", "R19", off("IF NOT v_met THEN")),
    ("M50", "the trigger cited may be another's", "R20", rep("IF v_trig IS NULL OR v_trig ->> 'trigger_code' IS DISTINCT FROM NEW.trigger_basis THEN", "IF v_trig IS NULL THEN")),
    ("M51", "a trigger basis needs no trigger", "R21", off("IF v_basis.requires_trigger <> (NEW.trigger_basis IS NOT NULL) THEN")),
    ("M52", "the carried-history basis may be taken", "R9", off("IF v_basis.insertable IS NOT TRUE THEN")),
    ("M53", "a deposit's law row may be changed", "R23", rep("OR OLD.rule_id IS DISTINCT FROM NEW.rule_id", "")),
    ("M54", "a deposit's principal may be changed", "R24", rep("OR OLD.principal <> NEW.principal", "")),
    ("M55", "a law row that does not exist is a foreign key", "R2b",
     rep("check_violation';\n        END IF;\n        -- The row the utility's profile", "foreign_key_violation';\n        END IF;\n        -- The row the utility's profile")),
    # ---- events
    ("M56", "a successor may be cited for a period before it took effect", "A19",
     rep("AND daterange(r.effective_from, r.effective_to, '[)') @> daterange(p_from, p_to, '[]'))));", "AND true)));")),
    ("M57", "a rate row of another category may be cited", "A4",
     rep("        OR NOT coalesce(v_rate.tariff_category IS NULL OR v_rate.tariff_category = d.tariff_category, false) THEN", "        THEN")),
    ("M58", "a rate row in effect after the period starts", "A5", off("IF v_rate.effective_date > NEW.period_start THEN")),
    ("M59", "a rate applied other than the cited row's", "A2", off("IF NEW.rate_applied <> v_rate.annual_rate THEN")),
    ("M60", "an accrual period that has not ended", "A10", off("IF NEW.period_end >= (now() AT TIME ZONE 'UTC')::date THEN")),
    ("M61", "an accrual recorded before its period ends", "A11", off("IF NEW.period_end >= NEW.effective_on THEN")),
    ("M62", "an accrual on more than was held", "A9", off("IF NEW.principal_basis > v_held THEN")),
    ("M63", "an accrual spanning a return", "Q16", off("IF v_last_return IS NOT NULL THEN")),
    ("M64", "interest credited before it is earned", "Q19", off("IF NEW.amount <= 0 OR NEW.amount > v_earned - b.interest_credited THEN")),
    ("M65", "a return dated inside an accrued period", "Q12",
     rep("AND b.accrued_through IS NOT NULL AND NEW.effective_on <= b.accrued_through THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit %s: interest is accrued through", "AND false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit %s: interest is accrued through")),
    ("M66", "a partial return of the whole remainder", "Q15", rep("IF NEW.amount <= 0 OR NEW.amount >= b.remainder THEN", "IF NEW.amount <= 0 OR NEW.amount > b.remainder THEN")),
    ("M67", "a settled partial row can be cited again", "Q8c", off("IF NOT public.deposit_return_due_is_live(NEW.return_due_id) THEN")),
    ("M68", "a withdrawn due row can be cited", "V21", off("IF v_due.withdrawn THEN")),
    ("M69", "another deposit's due row can be cited", "V25", rep("IF NOT FOUND OR v_due.deposit_id <> d.id THEN", "IF NOT FOUND THEN")),
    ("M70", "a partial return of another amount settles a row", "Q7", rep("OR (NEW.event_type = 'principal_returned' AND NEW.amount <> v_due.amount) THEN", "THEN")),
    ("M71", "a refund settles a partial row", "Q6", rep("IF (NEW.event_type = 'principal_returned') <> (v_due.amount IS NOT NULL)\n           OR", "IF false\n           OR")),
    ("M72", "a return before its due row fell due", "V26", off("IF NEW.effective_on < v_due.due_on THEN")),
    ("M73", "a law row cited for an event need not be the deposit's key", "A6",
     rep("    IF NOT public.deposit_rule_citable(p_deposit_id, p_rule_id, p_from, p_to) THEN", "    IF false THEN")),
    # ---- the return-due record
    ("M74", "a due row needs no return rule", "V4", rep("IF NEW.amount IS NULL AND NOT EXISTS (", "IF false AND NOT EXISTS (")),
    ("M75", "a due row for an instrument no return rule reaches", "V5", rep("WHERE (r -> 'instruments') ? d.instrument) THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit return due: law row %s has no return rule", "WHERE true) THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit return due: law row %s has no return rule")),
    ("M76", "a partial return needs no partial rule", "Q1", rep("WHERE x.partial AND (r -> 'instruments') ? d.instrument) THEN", "WHERE true) THEN")),
    ("M77", "a partial return of everything held", "Q2", rep("IF NEW.amount >= (SELECT b.remainder", "IF NEW.amount > (SELECT b.remainder")),
    ("M78", "a due row after the return started", "V28", rep("IF d.status IN ('refund_pending', 'refunded', 'released') THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit return due: deposit %s is already", "IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit return due: deposit %s is already")),
    ("M79", "a due row before posting", "V7", rep("IF NEW.due_on < d.posted_on THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit return due: due_on", "IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit return due: due_on")),
    ("M80", "two live due rows", "V3", off("IF v_live IS NOT NULL THEN")),
    ("M81", "a due row may supersede any row", "V22", rep("IF NEW.supersedes_due_id IS NOT NULL AND NOT EXISTS (", "IF false AND NOT EXISTS (")),
    ("M82", "a due row may cite any law row", "V6", rep("PERFORM public.deposit_cite_rule('deposit return due', d.id, NEW.rule_id, NEW.due_on, NEW.due_on);", "NULL;")),
    ("M83", "a due row needs no evidence", "V2", rep("IF NOT EXISTS (SELECT 1 FROM public.deposit_return_due_evidence e WHERE e.due_id = NEW.id) THEN", "IF false THEN")),
    ("M84", "evidence for a rule the document lacks", "V9", rep("    IF v_rule IS NULL THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit return due evidence: the cited law row has no return rule", "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit return due evidence: the cited law row has no return rule")),
    ("M85", "evidence for another rule's reason", "V8", off("IF v_rule #>> '{when,reason}' IS DISTINCT FROM NEW.reason_code THEN")),
    ("M86", "evidence of the wrong kind", "V10",
     rep("    IF v_reason.evidence_kind IS DISTINCT FROM (CASE WHEN NEW.invoice_id IS NOT NULL THEN 'invoice'", "    IF false AND v_reason.evidence_kind IS DISTINCT FROM (CASE WHEN NEW.invoice_id IS NOT NULL THEN 'invoice'")),
    ("M87", "a partial reason on a whole row", "Q3", off("IF v_reason.partial IS DISTINCT FROM (v_due.amount IS NOT NULL) THEN")),
    ("M88", "another customer's bill", "V12", rep("SELECT 1 FROM public.invoices i WHERE i.id = NEW.invoice_id AND i.customer_id = v_due.customer_id\n           AND", "SELECT 1 FROM public.invoices i WHERE i.id = NEW.invoice_id\n           AND")),
    ("M89", "a bill from before posting", "V13", rep("AND i.invoice_date >= v_due.posted_on AND i.invoice_date <= v_due.due_on) THEN", "AND i.invoice_date <= v_due.due_on) THEN")),
    ("M90", "a bill after the due date", "V14", rep("AND i.invoice_date >= v_due.posted_on AND i.invoice_date <= v_due.due_on) THEN", "AND i.invoice_date >= v_due.posted_on) THEN")),
    ("M91", "a state change to any status", "V15", rep("           AND s.to_status = ANY (v_reason.qualifying_statuses)\n", "")),
    ("M92", "another customer's state change", "V16", rep("WHERE s.id = NEW.customer_state_event_id AND s.customer_id = v_due.customer_id", "WHERE s.id = NEW.customer_state_event_id")),
    ("M93", "a state change after the due date", "V17", rep("BETWEEN v_due.posted_on AND v_due.due_on) THEN", ">= v_due.posted_on) THEN")),
    # ---- the migration and the registration
    ("M94", "the precondition lets a real deposit through", "MIG:P3a", off("IF v_dep + v_wvr + v_rate + v_acc > 0 THEN")),
    ("M95", "a second run does not skip the patch", "MIG:P2", rep("\\if :already", "\\if false")),
    # (M96, a carried deposit accruing, is not a mutation: the accrual CHECK, the citation guard and the legacy guard each refuse it, and all three
    #  say "carried legacy deposit"; migration-15r P1f proves the refusal, not which layer gave it.)
    ("M97", "the -06 view stays", "APPLY:cannot drop function", rep("DROP VIEW IF EXISTS public.deposits_refund_due;", "")),
    # ---- the seeds
    ("M98", "the residential cap is one-eighth", "K2", rep('"parts": [{"id": "c1", "kind": "fraction_of_annual_billing", "divisor": 6}]}\'::jsonb;', '"parts": [{"id": "c1", "kind": "fraction_of_annual_billing", "divisor": 8}]}\'::jsonb;')),
    ("M99", "the usage trigger fires at three times", "K2", rep('"op": "at_least", "value": 2},\n                          "guards": [{"kind": "payment_due_days", "days": 2}]}]', '"op": "at_least", "value": 3},\n                          "guards": [{"kind": "payment_due_days", "days": 2}]}]')),
    ("M100", "the Texas rows bind investor-owned owners only", "K3", rep("'owner_types', ARRAY['investor_owned', 'cooperative']", "'owner_types', ARRAY['investor_owned']")),
    ("M101", "the Texas rows start in 2005", "K3", rep("'effective_from', DATE '2004-07-12', 'effective_to', NULL,\n                'source_note', CASE WHEN", "'effective_from', DATE '2005-07-12', 'effective_to', NULL,\n                'source_note', CASE WHEN")),
    ("M102", "the city's delegations bind cooperatives", "APPLY:conflicting key value violates exclusion constraint", rep("'owner_types', ARRAY['municipal']", "'owner_types', ARRAY['cooperative']")),
    ("M103", "the 366 rows carry the 7.45 waivers", "K6",
     rep("'cap', '{\"strategy\": \"none\", \"version\": 1}'::jsonb,\n                                            'triggers', '[]'::jsonb, 'waivers', '[]'::jsonb,", "'cap', '{\"strategy\": \"none\", \"version\": 1}'::jsonb,\n                                            'triggers', '[]'::jsonb, 'waivers', v_waivers,")),
    ("M104", "the return-reasons facet reads the rule ids", "APPLY:not in deposit_return_reasons", rep("'$.return[*].when.reason'", "'$.return[*].id'")),
    ("M105", "the waiver-class facet is unscoped", "X8", rep("'{\"state_code\": \"state_code\", \"service_type\": \"service_type\"}'::jsonb,", "NULL,")),
    ("M106", "the vocabularies have no immutability guard", "APPLY:vocabulary_guard",
     rep("EXECUTE format('CREATE TRIGGER vocabulary_guard BEFORE INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_rule_vocabulary_immutable()', t);", "NULL;")),
    ("M107", "a utility may write the vocabularies", "H10",
     rep("EXECUTE format('REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.%I FROM tally_app, tally_core', t);", "EXECUTE format('GRANT INSERT ON public.%I TO tally_app', t);")),
    ("M108", "the law table is registered without its insert check", "M1",
     rep("'public.deposit_rule_close_floor(uuid)', 'public.deposit_rule_insert_check(jsonb)');", "'public.deposit_rule_close_floor(uuid)', NULL);")),
    ("M109", "the law table is registered without its close floor", "M1",
     rep("'public.deposit_rule_close_floor(uuid)', 'public.deposit_rule_insert_check(jsonb)');", "NULL, 'public.deposit_rule_insert_check(jsonb)');")),
    ("M110", "the tariff table is registered without its comparator", "U1",
     rep("'public.deposit_rules', 'public.deposit_tariff_compare(jsonb,jsonb)');", "NULL, NULL);")),
    # ---- r1 reviews: the comparator, the cap, the floor, the instalments
    ("M111", "months of the highest bill pass", "N16", rep("IF v_t #>> '{amount,of}' = 'highest' THEN", "IF false THEN")),
    ("M112", "a minimum amount passes", "N17", rep("ELSIF v_t #>> '{amount,minimum_amount,kind}' = 'amount' THEN", "ELSIF false THEN")),
    ("M113", "a class with no law passes", "N18", rep("IF v_miss <> '{}'::datemultirange THEN", "IF false THEN")),
    ("M114", "a longer count window passes", "N20", rep("IF (v_tc #>> '{window,size}')::numeric > (v_lc #>> '{window,size}')::numeric THEN", "IF false THEN")),
    ("M115", "dropping the consecutive protection passes", "N21", rep("IF (v_lc ->> 'consecutive')::boolean AND NOT (v_tc ->> 'consecutive')::boolean THEN", "IF false THEN")),
    ("M116", "counting disputed bills passes", "N22", rep("IF (v_lc ->> 'exclude_disputed')::boolean AND NOT (v_tc ->> 'exclude_disputed')::boolean THEN", "IF false THEN")),
    ("M117", "a lower count passes", "N23", rep("IF (v_tc ->> 'at_least')::numeric < (v_lc ->> 'at_least')::numeric THEN", "IF false THEN")),
    ("M118", "an incomparable condition passes", "N24", rep("                    ELSE\n                        v_problem := v_problem || format('the %s trigger''s condition cannot be compared with the law''s %s trigger", "                    ELSIF false THEN\n                        v_problem := v_problem || format('the %s trigger''s condition cannot be compared with the law''s %s trigger")),
    ("M119", "an amount against an unruled cap passes", "N25", rep("AND v_row #>> '{terms,cap,strategy}' = 'unruled' THEN", "AND false THEN")),
    ("M120", "a tariff trigger may have two guards of one kind", "N26",
     rep("    IF v_bad IS NOT NULL THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s: trigger %s has two guards of one kind — one guard per kind (v5.4.2-15)'", "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s: trigger %s has two guards of one kind — one guard per kind (v5.4.2-15)'")),
    ("M121", "a law trigger may have two guards of one kind", "X15",
     rep("    IF v_bad IS NOT NULL THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s: trigger %s has two guards of one kind — one guard per kind, so", "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s: trigger %s has two guards of one kind — one guard per kind, so")),
    ("M122", "a return of the excess over the cap needs no cap", "X16", rep("IF v_t #>> '{cap,strategy}' IS DISTINCT FROM 'parts' AND EXISTS (", "IF false AND EXISTS (")),
    ("M123", "a rate for every category clears only its categories' classes", "F17",
     rep("SELECT array_agg(c.class_code) INTO v_classes FROM public.deposit_customer_classes c\n         WHERE c.state_code = p_state_code AND c.service_type = p_service_type;",
         "SELECT array_agg(DISTINCT c.law_class) INTO v_classes FROM public.deposit_utility_categories c\n         WHERE c.tenant_id = p_tenant_id AND c.state_code = p_state_code AND c.service_type = p_service_type;")),
    ("M124", "a class with no law has no floor", "F19", rep("        IF v_missing IS NOT NULL THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('no law is known for the class(es)", "        IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('no law is known for the class(es)")),
    ("M125", "a cap above its statutory part's figure", "R28", rep("IF v_stat IS NOT NULL AND NEW.cap_amount > v_stat + 0.005 THEN", "IF false THEN")),
    ("M126", "a deposit need not be born held", "R31", rep("IF NEW.status <> 'held' OR NEW.refunded_on IS NOT NULL OR NEW.released_on IS NOT NULL THEN", "IF false THEN")),
    ("M127", "a new deposit may carry legacy interest", "R32", rep("IF NEW.legacy_interest_earned IS NOT NULL THEN\n            RAISE EXCEPTION USING MESSAGE = 'deposit rejected: legacy_interest_earned", "IF false THEN\n            RAISE EXCEPTION USING MESSAGE = 'deposit rejected: legacy_interest_earned")),
    ("M128", "what else was held without a combined cap", "R33", rep("IF (NEW.cap_other_held IS NOT NULL) <> ((v_doc #>> '{cap,scope}') = 'combined') THEN", "IF false THEN")),
    ("M129", "a tariff trigger cites no tariff row", "R34",
     rep("                IF NEW.tariff_id IS NULL THEN\n                    RAISE EXCEPTION USING MESSAGE = 'deposit rejected: a trigger said to come from the tariff", "                IF false THEN\n                    RAISE EXCEPTION USING MESSAGE = 'deposit rejected: a trigger said to come from the tariff")),
    ("M130", "a tariff's instalment schedule is ignored", "I1", rep("(SELECT jsonb_array_length(t.terms -> 'instalments') FROM public.deposit_tariffs t WHERE t.id = d.tariff_id), 0)", "0)")),
    ("M131", "the number of instalments is not checked", "I2b", rep("IF v_n + 1 <> v_doc_n OR d.received_at_posting + v_sum <> d.principal THEN", "IF d.received_at_posting + v_sum <> d.principal THEN")),
    ("M132", "instalments need not add up to the principal", "I3", rep("IF v_n + 1 <> v_doc_n OR d.received_at_posting + v_sum <> d.principal THEN", "IF v_n + 1 <> v_doc_n THEN")),
    ("M133", "an instalment on a deposit received whole", "I4", rep("    IF d.received_at_posting IS NULL THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit instalment: deposit %s was received whole", "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit instalment: deposit %s was received whole")),
    ("M134", "an instalment due before posting", "I5", rep("    IF NEW.due_on < d.posted_on THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit instalment", "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit instalment")),
    ("M135", "a refund of less than the remainder", "Q26", rep("        IF NEW.amount <> b.remainder THEN\n            RAISE EXCEPTION USING MESSAGE = format('deposit %s: refund_initiated amount", "        IF false THEN\n            RAISE EXCEPTION USING MESSAGE = format('deposit %s: refund_initiated amount")),
    ("M136", "cash may be released", "Q27", rep("IF NEW.event_type = 'released' AND d.instrument = 'cash' THEN", "IF false THEN")),
    ("M137", "a last event with interest uncredited", "Q28", rep("IF b.interest_credited <> b.interest_accrued THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('deposit %s: %s of accrued", "IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('deposit %s: %s of accrued")),
    ("M138", "the precondition ignores accruals on carried deposits", "MIG:P5ba", rep("SELECT count(*) INTO v_acc FROM public.deposit_events e WHERE e.event_type = 'interest_accrued';", "v_acc := 0;")),
    # ---- r2 reviews
    ("M139", "an instalment added after the schedule was checked", "I6", rep("        PERFORM public.deposit_instalments_check(NEW.deposit_id);", "        NULL;")),
    ("M140", "a lesser-of cap lifted by naming its larger part", "R40", rep("IF v_doc #>> '{cap,combinator}' = 'lesser_of' THEN\n                SELECT min(", "IF false THEN\n                SELECT min(")),
    ("M141", "a cap on the highest bills is unchecked", "R42", rep("WHEN 'highest_bills' THEN p_basis", "WHEN 'highest_bills' THEN NULL")),
    ("M142", "a city's cap above its tariff's amount", "R35", rep("IF v_tamt IS NOT NULL AND NEW.cap_amount IS NOT NULL AND NEW.cap_amount > v_tamt + 0.005 THEN", "IF false THEN")),
    ("M143", "a months tariff's multiple is wrong", "R38", rep("ELSE NEW.cap_basis_amount * (v_tariff.terms #>> '{amount,months}')::numeric END", "ELSE NEW.cap_basis_amount * 99 END")),
    ("M144", "a months tariff needs no monthly billing figure", "R39", rep("IF (NEW.cap_basis_amount IS NULL) <> (v_tariff.terms #>> '{amount,strategy}' IS DISTINCT FROM 'months_of_billing') THEN", "IF false THEN")),
    ("M145", "a cap part named where the document sets no cap", "R36", rep("ELSIF NEW.cap_component IS NOT NULL THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('deposit rejected: law row %s sets no cap, so", "ELSIF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('deposit rejected: law row %s sets no cap, so")),
    ("M146", "a statutory cap under a document that sets none", "R44", rep("ELSIF NEW.cap_source = 'statute' THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('deposit rejected: a statutory cap is the cited document''s — law row %s sets none", "ELSIF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('deposit rejected: a statutory cap is the cited document''s — law row %s sets none")),
    ("M147", "a trigger under another code escapes the comparison", "N27", rep("CONTINUE WHEN NOT v_related;", "CONTINUE WHEN NOT v_samecode;")),
    ("M148", "the law's other guards need not be carried", "N28", rep("IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_tt -> 'guards') x WHERE x = v_g) THEN", "IF false THEN")),
    ("M149", "a fractional count of events meets a threshold", "R45", rep(" AND NEW.trigger_observed = trunc(NEW.trigger_observed)", "")),
    ("M150", "a successor row for other owners is citable", "A22", rep("AND r.owner_span = own.owner_span AND r.system_span = own.system_span AND r.jurisdiction_span = own.jurisdiction_span", "")),
    ("M151", "the close floor ignores accruals", "A20", rep("SELECT coalesce(e.period_end, e.effective_on) FROM public.deposit_events e WHERE e.rule_id = p_rule_id", "SELECT NULL::date WHERE false")),
    ("M152", "a tariff's instalments need not add up", "N29",
     rep("SELECT sum((i ->> 'fraction')::numeric) INTO v_sum FROM jsonb_array_elements(v_t -> 'instalments') i;\n        IF v_sum IS DISTINCT FROM 1 THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('%s: the instalment fractions add up to %s; they must add up to exactly 1 (v5.4.2-15)', v_who, v_sum), ERRCODE = 'check_violation';\n        END IF;\n    END IF;\nEND;", "NULL;\n    END IF;\nEND;")),
    ("M153", "an instalment received for more than is to come", "I7", rep("IF NEW.amount <= 0 OR NEW.amount > d.principal - coalesce((SELECT sum(e.amount) FROM public.deposit_events e", "IF NEW.amount <= 0 OR false AND NEW.amount > d.principal - coalesce((SELECT sum(e.amount) FROM public.deposit_events e")),
    ("M154", "a rate for every category ignores a class with no law", "F20", rep("SELECT string_agg(c, ', ' ORDER BY c) INTO v_missing FROM unnest(coalesce(v_classes, '{}')) c", "SELECT string_agg(c, ', ' ORDER BY c) INTO v_missing FROM unnest(CASE WHEN p_category IS NULL THEN '{}'::text[] ELSE coalesce(v_classes, '{}') END) c")),
    ("M155", "a tariff outlasts its class's law", "N30", rep("SELECT coalesce(range_agg(daterange((r ->> 'effective_from')::date, (r ->> 'effective_to')::date, '[)')), '{}'::datemultirange) INTO v_cov", "SELECT datemultirange(v_range) INTO v_cov")),
    # ---- r3 reviews
    ("M156", "the class's law counts for a segment it does not bind", "N35", rep("AND (r ->> 'owner_span')::int4multirange @> public.rule_applicability_ordinal('owner_type', v_prof.owner_type)", "")),
    ("M157", "a combined condition has no leaves", "N32", rep("FOR x IN SELECT e FROM jsonb_array_elements(coalesce(p_cond -> 'of', '[]'::jsonb)) e LOOP", "FOR x IN SELECT e FROM jsonb_array_elements('[]'::jsonb) e LOOP")),
    ("M158", "a count in another unit is compared as if in the same", "N33", rep("AND v_tc #>> '{window,unit}' = v_lc #>> '{window,unit}' THEN\n                        IF (v_tc ->> 'at_least')", "THEN\n                        IF (v_tc ->> 'at_least')")),
    ("M159", "a recorded cap needs no source", "R49", rep("AND (cap_source IS NOT NULL) AND (((cap_source = 'statute'::text)", "AND (((cap_source = 'statute'::text)")),
    ("M160", "a delegation's cap need not be recorded", "R50", rep("IF v_tariff.terms #>> '{amount,strategy}' IN ('fixed', 'months_of_billing') AND NEW.cap_amount IS NULL THEN", "IF false THEN")),
    ("M161", "a lesser-of cap of parts on different bases", "X17", rep("IF v_comb <> 'single' AND (SELECT count(*) FROM jsonb_array_elements(v_t #> '{cap,parts}') p WHERE p ->> 'kind' <> 'fixed_amount') > 1 THEN", "IF false THEN")),
    ("M162", "the tariff holds only a cap said to come from it", "R51", rep("IF v_tamt IS NOT NULL AND NEW.cap_amount IS NOT NULL AND NEW.cap_amount > v_tamt + 0.005 THEN", "IF NEW.cap_source = 'tariff' AND v_tamt IS NOT NULL AND NEW.cap_amount IS NOT NULL AND NEW.cap_amount > v_tamt + 0.005 THEN")),
    ("M163", "a months tariff is converted to a fraction part wrongly", "R51", rep("WHEN 'fraction_of_annual_billing' THEN NEW.cap_basis_amount / 12 * (v_tariff.terms #>> '{amount,months}')::numeric", "WHEN 'fraction_of_annual_billing' THEN NEW.cap_basis_amount * (v_tariff.terms #>> '{amount,months}')::numeric")),
    ("M164", "a seasonal cap ignores its multiple", "R48", rep("WHEN 'seasonal_average' THEN p_basis * (p_part ->> 'multiple')::numeric", "WHEN 'seasonal_average' THEN p_basis")),
    ("M165", "a strict law ratio and an inclusive tariff one are the same", "N38", rep("OR ((v_tc ->> 'value')::numeric = (v_lc ->> 'value')::numeric AND v_tc ->> 'op' = 'at_least' AND v_lc ->> 'op' = 'greater_than') THEN", "THEN")),
    ("M166", "a greater-of cap is compared on the parts that convert", "N43", rep("WHEN v_comb = 'greater_of' AND NOT EXISTS (SELECT 1 FROM unnest(v_pms) x WHERE x IS NULL) THEN (SELECT max(x) FROM unnest(v_pms) x)", "WHEN v_comb = 'greater_of' THEN (SELECT max(x) FROM unnest(v_pms) x)")),
    # (the min / max of a lesser-of / greater-of is not a mutation: version 1 allows one part that converts, so there is one figure to take)
]


def sh(cmd: list[str], inp: str | None = None, env=None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, input=inp, capture_output=True, text=True, env=env)


def psql_admin(q: str) -> None:
    sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-qc", q])


def run_one(idx: int, mid: str, what: str, check: str, mut: Callable[[str], str], base: str, battery_sql: str) -> tuple[str, bool]:
    db = f"m15mut{os.getpid()}x{idx % WORKERS}"
    try:
        patched = mut(base)
    except AssertionError as exc:
        return f"{mid} ANCHOR-ERROR: {exc}", False
    if check.startswith("MIG:"):
        with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as f:
            f.write(patched)
        check = check[4:]
        env = dict(os.environ, PATCH15=f.name)
        out = sh([sys.executable, str(HERE / "migration-15r.py"), "tally"], env=env)
        os.unlink(f.name)
        text = out.stdout + out.stderr
        if re.search(rf"FAIL {re.escape(check)}[:\s]", text):
            return f"{mid} caught at {check}: {what}", True
        first = next((l for l in text.splitlines() if "FAIL" in l or "Error" in l), "")[:120]
        return f"{mid} MISSED ({check}): {what}  [first: {first}]", False
    psql_admin(f"DROP DATABASE IF EXISTS {db}")
    psql_admin(f"CREATE DATABASE {db} TEMPLATE tally")
    sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", db, "-qc", f"REVOKE TEMP ON DATABASE {db} FROM PUBLIC, tally_app, tally_core"])
    a = sh(["docker", "exec", "-i", "tally-pg", "psql", "-U", "tally", "-d", db, "-v", "ON_ERROR_STOP=1", "-q", "-f", "-"],
           "SET search_path = ''; SET check_function_bodies = on;\n" + patched)
    try:
        if a.returncode:
            last = next((l for l in a.stderr.splitlines() if "ERROR" in l), a.stderr.strip()[-200:] or "?")
            if check.startswith("APPLY:"):
                phrase = check.split(":", 1)[1]
                if phrase in a.stderr:
                    return f"{mid} caught at apply: {what} ({phrase!r})", True
                return f"{mid} MISSED (apply failed, but not on {phrase!r}): {what}: {last[:140]}", False
            return f"{mid} APPLY-ERROR ({what}): {last[:140]}", False
        if check.startswith("APPLY"):
            return f"{mid} MISSED (applied cleanly): {what}", False
        path = f"/tmp/bat_{db}.sql"
        sh(["docker", "exec", "-i", "tally-pg", "sh", "-c", f"cat > {path}"], battery_sql)
        out = sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", db, "-q", "-f", path])
        text = out.stdout + out.stderr
        if re.search(rf"FAIL {re.escape(check)}[a-z]?[:\s]", text):
            return f"{mid} caught at {check}: {what}", True
        first = next((l for l in text.splitlines() if "FAIL" in l or "ERROR" in l), "")
        first = re.sub(r"^psql:[^:]+:\d+: ", "", first)[:120]
        return f"{mid} MISSED ({check}): {what}  [first: {first}]", False
    finally:
        psql_admin(f"DROP DATABASE IF EXISTS {db}")


def main() -> int:
    base = PATCH.read_text()
    battery_sql = (HERE / "battery-15r.sql").read_text().replace("\\set ON_ERROR_STOP 1", "\\set ON_ERROR_STOP 0\n\\set ON_ERROR_ROLLBACK on", 1)
    only = set(sys.argv[1:])
    todo = [(i, *m) for i, m in enumerate(MUTATIONS) if not only or m[0] in only]
    # one worker per clone name: mutations sharing a name run one after the other
    lanes: dict[int, list] = {}
    for t in todo:
        lanes.setdefault(t[0] % WORKERS, []).append(t)

    def lane(items):
        return [run_one(i, mid, what, check, mut, base, battery_sql) for i, mid, what, check, mut in items]

    results = []
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        for res in ex.map(lane, lanes.values()):
            results.extend(res)
    results.sort(key=lambda r: int(re.match(r"M(\d+)", r[0]).group(1)))
    missed = 0
    for line, ok in results:
        print(line)
        missed += 0 if ok else 1
    print(f"{len(results) - missed}/{len(results)} caught")
    return 1 if missed else 0


if __name__ == "__main__":
    sys.exit(main())
