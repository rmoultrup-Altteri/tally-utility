#!/usr/bin/env python3
"""v5.4.2-27 — prove the -27 checks CATCH drift, not merely pass.

Each mutation alters a copy of the patch, applies it (strict: search_path ''
and function-body checking on) to a fresh clone of `tally` with TEMP revoked,
and runs the script that owns the named check:

  battery check (K T C E S F U H B D I) battery-27.sql
  SR1-SR9                           races/shortfall-27.sh
  APPLY:<phrase>                    the patch itself must refuse (its tail runs
                                    the invariants), with that phrase

CAUGHT only when the FIRST failure printed is the named check's (the -21
rule). A mutation an EARLIER check catches is reported as missed: its named
check is wrong, or a guard is redundant — fix the name or remove the
duplicate, never loosen the rule.

    python3 tests/v5.4.2-27/mutations-27.py [M01 M12 ...]
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[2]
PATCH = ROOT / "sql/v5.4.2-27-shortfall-applications.sql"
HERE = ROOT / "tests/v5.4.2-27"
DB = "m27"


def rep(old: str, new: str) -> Callable[[str], str]:
    def m(s: str) -> str:
        assert s.count(old) == 1, f"mutation anchor not unique/found ({s.count(old)}): {old[:90]!r}"
        return s.replace(old, new, 1)
    return m


TARGET_CHOSEN = ("    IF NEW.created_at < v_target.status_recorded_at THEN\n        IF NEW.created_at <> pg_catalog.now() THEN\n")

MUTATIONS = [
    # ---- the row
    ("M01", "a shortfall application may be recorded in the future", "K23",
     rep("    IF NOT pg_catalog.isfinite(NEW.created_at) OR NEW.created_at > pg_catalog.clock_timestamp() THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('shortfall application %s is recorded at",
         "    IF NOT pg_catalog.isfinite(NEW.created_at) THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('shortfall application %s is recorded at")),
    ("M02", "a shortfall is repaid on a payment that has not ended", "K13",
     rep("    IF v_target.status NOT IN ('nsf', 'reversed') THEN", "    IF v_target.status NOT IN ('nsf', 'reversed', 'posted', 'pending') THEN")),
    ("M03", "a repayment with a chosen time may precede the bounce", "K23b",
     rep(TARGET_CHOSEN, "    IF NEW.created_at < v_target.status_recorded_at THEN\n        IF false THEN\n")),
    ("M04", "a repayment begun before the bounce is not told to retry", "SR6",
     rep("    IF NEW.created_at < v_target.status_recorded_at THEN\n", "    IF NEW.created_at < v_target.status_recorded_at AND NEW.created_at <> pg_catalog.now() THEN\n")),
    ("M05", "a repayment is not ordered after the target's draws", "SR5",
     rep("    PERFORM public.check_cash_order('payment', NEW.target_payment_id, NEW.created_at,", "    PERFORM pg_catalog.num_nulls('payment', NEW.target_payment_id, NEW.created_at,")),
    ("M06", "a repayment is not ordered after its family credits' draws", "SR8",
     rep("    PERFORM public.check_cash_order('credit', f.id, NEW.created_at, NULL, 'a repayment of its payment''s shortfall')",
         "    PERFORM pg_catalog.num_nulls('credit', f.id, NEW.created_at, NULL, 'a repayment of its payment''s shortfall')")),
    ("M07", "the target's lock is not taken", "SR1",
     rep("    PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('payment', NEW.target_payment_id));\n", "")),
    ("M08", "an undo may name an undo", "K11",
     rep("        IF v_undone.basis = 'undo'\n           OR v_undone.payment_id", "        IF false\n           OR v_undone.payment_id")),
    ("M09", "an undo may name another source's row", "K9b",
     rep("           OR v_undone.payment_id IS DISTINCT FROM NEW.payment_id\n           OR v_undone.customer_credit_id IS DISTINCT FROM NEW.customer_credit_id THEN",
         "           THEN")),
    ("M10", "an undo may be dated before what it undoes", "K9",
     rep("        IF NEW.applied_on < v_undone.applied_on THEN", "        IF false THEN")),
    ("M11", "undos may exceed what they undo", "K10",
     rep("        IF v_net < 0 THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('shortfall application %s: its undos", "        IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('shortfall application %s: its undos")),
    ("M12", "a credit's money applied to its own payment's shortfall is held to the family cap", "F2",
     rep("CASE WHEN NEW.basis = 'undo' THEN 'shortfall_undo' WHEN v_within THEN 'shortfall_within_family' ELSE 'shortfall' END",
         "CASE WHEN NEW.basis = 'undo' THEN 'shortfall_undo' ELSE 'shortfall' END")),
    ("M13", "every shortfall application skips the family cap", "F1a",
     rep("p_purpose NOT IN ('reissue', 'overpayment_credit', 'shortfall_within_family') THEN", "p_purpose NOT IN ('reissue', 'overpayment_credit', 'shortfall_within_family', 'shortfall') THEN")),
    ("M14", "a repayment is not held to the target's cap", "K1",
     rep("        PERFORM public.check_shortfall_repaid(NEW.target_payment_id, NEW.applied_on);", "        NULL;")),
    ("M15", "an undo giving a repaid family money back is not checked", "U2",
     rep("        PERFORM public.check_shortfall_repaid(CASE WHEN p_kind = 'payment' THEN p_id ELSE v_pool_pay END, NULL);", "        NULL;")),
    ("M16", "a refund leaving a repaid family is not checked (Ryan, 2026-11-05)", "S2",
     rep("        PERFORM public.check_shortfall_repaid(coalesce(NEW.refunds_payment_id,", "        PERFORM pg_catalog.num_nulls(coalesce(NEW.refunds_payment_id,")),
    ("M17", "a move giving money back reads an undo at its own date, not its row's (the S4 shape)", "S4",
     rep("SELECT CASE WHEN p_from IS NULL THEN coalesce(u.applied_on, s.applied_on) ELSE s.applied_on END, -s.amount", "SELECT s.applied_on, -s.amount")),
    ("M18", "a move giving money back is checked from the latest repayment's date (r1, Codex B1)", "C1",
     rep("    SELECT min(s.applied_on) INTO v_from FROM public.shortfall_applications s", "    SELECT max(s.applied_on) INTO v_from FROM public.shortfall_applications s")),
    ("M18b", "a repayment reads an undo from its row's date too (it would hide money the positions show)", "C4",
     rep("SELECT CASE WHEN p_from IS NULL THEN coalesce(u.applied_on, s.applied_on) ELSE s.applied_on END, -s.amount", "SELECT coalesce(u.applied_on, s.applied_on), -s.amount")),
    ("M16b", "a family credit's refund leaving a repaid family is not checked (Fable S2)", "C6",
     rep("            (SELECT k.source_payment_id FROM public.customer_credits k WHERE k.id = public.overpayment_root(NEW.refunds_customer_credit_id))), NULL);",
         "            NULL), NULL);")),
    ("M16c", "the target's cap leaves out its family credits' draws (Opus S3)", "F2",
     rep("                    WHERE k.source_payment_id = pp.id AND k.status <> 'voided' AND c.status <> 'voided'\n                      AND d.id NOT IN (SELECT g.id FROM public.overpayment_family(k.id) g)",
         "                    WHERE false\n                      AND d.id NOT IN (SELECT g.id FROM public.overpayment_family(k.id) g)")),
    ("M16d", "the target's cap leaves out what was taken back under its posting entry (Opus S3)", "K2",
     rep("                    WHERE l.id = ANY (public.ledger_tree_ids(public.cash_arrival_entry('payment', pp.id)))\n                   UNION ALL\n                   SELECT '-infinity'::date, pp.amount",
         "                    WHERE false\n                   UNION ALL\n                   SELECT '-infinity'::date, pp.amount")),
    # ---- targets (r2)
    ("M36", "a bounced deposit is a target (Opus S1)", "T1",
     rep("    IF v_target.is_deposit THEN", "    IF false THEN")),
    ("M37", "a refund is a target (Opus S2)", "T2",
     rep("    IF v_target.refunds_payment_id IS NOT NULL OR v_target.refunds_customer_credit_id IS NOT NULL THEN", "    IF false THEN")),
    # ---- the carry (r2; Ryan, 2026-11-05)
    ("M38", "an undo onto an escheated credit is refused (r1: the escheat trap)", "E3",
     rep("        WHEN 'shortfall_undo' THEN v_status IN ('posted', 'active') OR (p_kind = 'credit' AND v_status = 'escheated')",
         "        WHEN 'shortfall_undo' THEN v_status IN ('posted', 'active')")),
    ("M39", "what an undo gives back to an escheated credit is not checked at commit", "E3",
     rep("    v_left := public.customer_credit_own_remaining_as_of(NEW.customer_credit_id, DATE '9999-12-31', pg_catalog.clock_timestamp());\n    IF v_left > 0 THEN",
         "    v_left := public.customer_credit_own_remaining_as_of(NEW.customer_credit_id, DATE '9999-12-31', pg_catalog.clock_timestamp());\n    IF false THEN")),
    ("M40", "the carry's size is not checked", "E4",
     rep("    IF NEW.original_amount <> least(-v_undo.amount, v_left) THEN", "    IF false THEN")),
    ("M41", "the carry may be dated before the undo", "E5",
     rep("    IF NEW.issued_date < v_undo.applied_on THEN", "    IF false THEN")),
    ("M42", "the carry may name a repayment, not an undo", "E6",
     rep("    IF v_undo.basis IS DISTINCT FROM 'undo' OR v_undo.customer_credit_id IS NULL OR v_from IS DISTINCT FROM 'escheated' THEN",
         "    IF v_undo.customer_credit_id IS NULL OR v_from IS DISTINCT FROM 'escheated' THEN")),
    ("M44", "the walk up a reissue line does not follow a shortfall reissue", "E13b",
     rep("         WHERE u.origin_type IN ('refund_reissue', 'shortfall_reissue') AND u.gen <= public.reissue_line_bound()\n    )\n    SELECT (SELECT u.id FROM up u WHERE u.origin_type = 'overpayment')",
         "         WHERE u.origin_type IN ('refund_reissue') AND u.gen <= public.reissue_line_bound()\n    )\n    SELECT (SELECT u.id FROM up u WHERE u.origin_type = 'overpayment')")),
    ("M45", "the walk down a family does not follow a shortfall reissue", "E13b",
     rep("                WHERE s.customer_credit_id = d.id) k", "                WHERE false) k")),
    ("M46", "a shortfall reissue's issued is read from the ledger (it has no entry)", "E7b",
     rep("                 WHEN c.origin_type IN ('refund_reissue', 'shortfall_reissue') THEN c.original_amount", "                 WHEN c.origin_type IN ('refund_reissue') THEN c.original_amount")),
    ("M47", "what a credit had given at an instant leaves out the carry (the shares misplace a take-back)", "E14c",
     rep("        SELECT k.original_amount FROM public.customer_credits k JOIN public.shortfall_applications s ON s.id = k.reissues_shortfall_application_id\n         WHERE p_kind = 'credit' AND s.customer_credit_id = p_id AND k.created_at <= p_at",
         "        SELECT k.original_amount FROM public.customer_credits k JOIN public.shortfall_applications s ON s.id = k.reissues_shortfall_application_id\n         WHERE false AND k.created_at <= p_at")),
    ("M48", "a shortfall reissue gives no money without an arrival entry", "E9",
     rep("coalesce(v_origin, '') NOT IN ('refund_reissue', 'shortfall_reissue') THEN", "coalesce(v_origin, '') NOT IN ('refund_reissue') THEN")),
    ("M49", "a shortfall reissue may be voided", "E10",
     rep("    ELSIF OLD.origin_type = 'shortfall_reissue' AND NEW.status = 'voided' THEN", "    ELSIF false THEN")),
    ("M50", "a shortfall reissue may post a credit_issued row", "E11",
     rep("        IF EXISTS (SELECT 1 FROM public.customer_credits c WHERE c.id = NEW.reference_id AND c.origin_type = 'shortfall_reissue') THEN", "        IF false THEN")),
    ("M51", "a shortfall reissue's undo may change", "E12",
     rep("    ELSIF NEW.reissues_shortfall_application_id IS DISTINCT FROM OLD.reissues_shortfall_application_id THEN", "    ELSIF false THEN")),
    # ---- the source's own bounce
    ("M19", "a payment applied to a shortfall may have its money taken back", "K7",
     rep("    IF public.shortfall_applied_from(v_pay) THEN", "    IF false THEN")),
    ("M20", "a payment applied to a shortfall may move to nsf", "B3",
     rep("    IF public.shortfall_applied_from(NEW.id) THEN", "    IF false THEN")),
    ("M21", "a payment's overpayment credit applied to a shortfall does not hold up its bounce", "B2",
     rep("                      AND coalesce((SELECT sum(s.amount) FROM public.shortfall_applications s WHERE s.customer_credit_id = c.id), 0) <> 0)",
         "                      AND false)")),
    # ---- the readers
    ("M22", "the source's shortfall applications are not among its draws", "K4",
     rep("    SELECT s.id, s.applied_on, s.amount, s.created_at FROM public.shortfall_applications s\n     WHERE (p_kind = 'payment' AND s.payment_id = p_id) OR (p_kind = 'credit' AND s.customer_credit_id = p_id)",
         "    SELECT s.id, s.applied_on, s.amount, s.created_at FROM public.shortfall_applications s\n     WHERE false")),
    ("M23", "the target's repayments are not among its draws (its recorded order)", "SR5",
     rep("    SELECT s.id, s.applied_on, -s.amount, s.created_at FROM public.shortfall_applications s\n     WHERE p_kind = 'payment' AND s.target_payment_id = p_id",
         "    SELECT s.id, s.applied_on, -s.amount, s.created_at FROM public.shortfall_applications s\n     WHERE false")),
    ("M24", "a credit's position does not count its shortfall applications", "K3",
     rep("                   WHERE s.customer_credit_id = p_credit_id AND s.applied_on <= p_on AND s.created_at <= p_recorded_at), 0),",
         "                   WHERE false), 0),")),
    ("M25", "a payment's position does not count its money applied to a shortfall", "K6b",
     rep("                   WHERE s.payment_id = p_payment_id AND s.applied_on <= p_on AND s.created_at <= p_recorded_at), 0),",
         "                   WHERE false), 0),")),
    ("M26", "a payment's position does not count what was repaid", "K3",
     rep("                   WHERE s.target_payment_id = p_payment_id AND s.applied_on <= p_on AND s.created_at <= p_recorded_at), 0.00)\n$$;",
         "                   WHERE false), 0.00)\n$$;")),
    ("M27", "repaid is shown but not counted in remaining", "K3",
     rep("d.received - d.applied - x.credited - d.refunded + d.repaid, d.repaid", "d.received - d.applied - x.credited - d.refunded, d.repaid")),
    ("M28", "the cover does not place a repayment on the payment's own part", "F3",
     rep("SELECT d.received - d.applied - d.refunded + d.repaid - (k.original_amount", "SELECT d.received - d.applied - d.refunded - (k.original_amount")),
    ("M29", "a repayment counts before its money date", "K3c",
     rep("                   WHERE s.target_payment_id = p_payment_id AND s.applied_on <= p_on AND s.created_at <= p_recorded_at), 0.00)\n$$;",
         "                   WHERE s.target_payment_id = p_payment_id AND s.created_at <= p_recorded_at), 0.00)\n$$;")),
    # ---- r3
    ("M56", "an undo may be dated after today and after its row (Opus B1, Fable B1)", "R0",
     rep("        IF NEW.applied_on > greatest((pg_catalog.now() AT TIME ZONE 'Etc/GMT-14')::date, v_undone.applied_on) THEN",
         "        IF false AND NEW.applied_on > greatest((pg_catalog.now() AT TIME ZONE 'Etc/GMT-14')::date, v_undone.applied_on) THEN")),
    ("M57", "today is read at UTC-12 (an undo the utility dates today would be refused)", "R2",
     rep("        IF NEW.applied_on > greatest((pg_catalog.now() AT TIME ZONE 'Etc/GMT-14')::date, v_undone.applied_on) THEN",
         "        IF NEW.applied_on > greatest((pg_catalog.now() AT TIME ZONE 'Etc/GMT+12')::date, v_undone.applied_on) THEN")),
    ("M57b", "today is read a day late (an undo dated tomorrow is admitted)", "R0b",
     rep("        IF NEW.applied_on > greatest((pg_catalog.now() AT TIME ZONE 'Etc/GMT-14')::date, v_undone.applied_on) THEN",
         "        IF NEW.applied_on > greatest((pg_catalog.now() AT TIME ZONE 'Etc/GMT-14')::date + 1, v_undone.applied_on) THEN")),
    ("M58", "an undo of a repayment dated ahead must still be dated by today (Fable N1)", "R3b",
     rep("        IF NEW.applied_on > greatest((pg_catalog.now() AT TIME ZONE 'Etc/GMT-14')::date, v_undone.applied_on) THEN",
         "        IF NEW.applied_on > (pg_catalog.now() AT TIME ZONE 'Etc/GMT-14')::date THEN")),
    ("M59", "a carry may be born ended by a history load (Codex B1)", "E6c",
     rep("    IF NEW.status IS DISTINCT FROM 'active' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('credit %s reissues shortfall application %s and is born %s",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('credit %s reissues shortfall application %s and is born %s")),
    ("M60", "a carry may name an undo that gave nothing to an escheated credit (Opus S1, Fable S1)", "E15",
     rep("    IF NOT v_undo.gave_to_escheated THEN", "    IF false THEN")),
    # M60b, M60e: a wrong stamp is caught by its re-read under the lock, at
    # the first undo it misreads, before E15a reads the stamp's values.
    ("M60b", "every undo of a credit's repayment is recorded as giving to an escheated credit (the re-read refuses an active credit's undo)", "S3",
     rep("        AND coalesce((SELECT c.status = 'escheated' FROM public.customer_credits c WHERE c.id = NEW.customer_credit_id), false);",
         "        AND true;")),
    ("M60e", "no undo is recorded as giving to an escheated credit (the re-read refuses the undo onto an escheated one)", "E3",
     rep("        AND coalesce((SELECT c.status = 'escheated' FROM public.customer_credits c WHERE c.id = NEW.customer_credit_id), false);",
         "        AND false;")),
    ("M60c", "an undo's record of its credit's status is not read again under the credit's lock", "SR11",
     rep("       AND NEW.gave_to_escheated IS DISTINCT FROM coalesce((SELECT c.status = 'escheated' FROM public.customer_credits c WHERE c.id = v_src), false) THEN",
         "       AND false THEN")),
    ("M60d", "the database's record of an undo's credit status is not written (the stamp trigger dropped)", "APPLY:a v5.4.2-27 guard is missing",
     rep("ALTER TABLE public.shortfall_applications ENABLE ALWAYS TRIGGER a_stamp_gave_to_escheated;\n",
         "DROP TRIGGER a_stamp_gave_to_escheated ON public.shortfall_applications;\n")),
    ("M61", "a carry's line is not held to the depth bound (Codex S1)", "E17",
     rep("    IF public.reissue_generation(v_undo.customer_credit_id) + 1 > public.reissue_line_bound() THEN", "    IF false THEN")),
    ("M62", "a carry may name an undo of a credit that was never escheated (Codex S1)", "S3c",
     rep("    IF v_undo.basis IS DISTINCT FROM 'undo' OR v_undo.customer_credit_id IS NULL OR v_from IS DISTINCT FROM 'escheated' THEN",
         "    IF v_undo.basis IS DISTINCT FROM 'undo' OR v_undo.customer_credit_id IS NULL THEN")),
    ("M63", "a credit's draws leave out its carries (Fable S1)", "E7d",
     rep("    SELECT c.id, c.issued_date, c.original_amount, c.created_at FROM public.customer_credits c\n      JOIN public.shortfall_applications s ON s.id = c.reissues_shortfall_application_id\n     WHERE p_kind = 'credit' AND s.customer_credit_id = p_id AND c.status <> 'voided'",
         "    SELECT c.id, c.issued_date, c.original_amount, c.created_at FROM public.customer_credits c\n      JOIN public.shortfall_applications s ON s.id = c.reissues_shortfall_application_id\n     WHERE false")),
    ("M65", "what a payment had given at an instant leaves out what was repaid to it (Codex r3 S2)", "J1",
     rep("        SELECT -s.amount FROM public.shortfall_applications s\n         WHERE p_kind = 'payment' AND s.target_payment_id = p_id AND s.created_at <= p_at",
         "        SELECT -s.amount FROM public.shortfall_applications s\n         WHERE false AND s.created_at <= p_at")),
    ("M64", "what a source had given at an instant leaves out its shortfall applications (Codex r4 S1)", "J2",
     rep("        SELECT s.amount FROM public.shortfall_applications s\n         WHERE ((p_kind = 'payment' AND s.payment_id = p_id) OR (p_kind = 'credit' AND s.customer_credit_id = p_id)) AND s.created_at <= p_at",
         "        SELECT s.amount FROM public.shortfall_applications s\n         WHERE false AND s.created_at <= p_at")),
    ("M66", "an undo and its credit's escheat in one statement are told to retry (Opus r4 S1)", "E21",
     rep("        IF (SELECT c.status_recorded_at FROM public.customer_credits c WHERE c.id = v_src) = pg_catalog.now() THEN",
         "        IF false THEN")),
    # ---- the definitions the invariant holds
    ("M30", "the freeze trigger is dropped", "APPLY:a v5.4.2-27 guard is missing",
     rep("CREATE TRIGGER a_enforce_accounting_freeze BEFORE INSERT ON public.shortfall_applications\n    FOR EACH ROW EXECUTE FUNCTION public.enforce_accounting_freeze('applied_on');\nALTER TABLE public.shortfall_applications ENABLE ALWAYS TRIGGER a_enforce_accounting_freeze;\n", "")),
    ("M31", "the target key loses the tenant (a single-column key skips row-level security)", "APPLY:a v5.4.2-27 constraint is missing",
     rep("        FOREIGN KEY (target_payment_id, tenant_id, customer_id) REFERENCES public.payments (id, tenant_id, customer_id),",
         "        FOREIGN KEY (target_payment_id) REFERENCES public.payments (id),")),
    ("M32", "the table is not forced under row-level security", "APPLY:forced row security",
     rep("ALTER TABLE public.shortfall_applications FORCE ROW LEVEL SECURITY;\n", "")),
    ("M33", "tally_app may update the table", "APPLY:tally_app may only SELECT and INSERT",
     rep("GRANT SELECT, INSERT ON public.shortfall_applications TO tally_app;", "GRANT SELECT, INSERT, UPDATE ON public.shortfall_applications TO tally_app;")),
    ("M34", "the target's cap is executable by tally_core", "APPLY:check_shortfall_repaid is executable beyond tally_app",
     rep("GRANT EXECUTE ON FUNCTION public.check_shortfall_repaid(uuid, date) TO tally_app;", "GRANT EXECUTE ON FUNCTION public.check_shortfall_repaid(uuid, date) TO tally_app, tally_core;")),
    ("M52", "tally_app may only read the table (its INSERT not required alone; Codex S1)", "APPLY:tally_app may only SELECT and INSERT",
     rep("GRANT SELECT, INSERT ON public.shortfall_applications TO tally_app;", "GRANT SELECT ON public.shortfall_applications TO tally_app;")),
    ("M53", "tally_core may hold REFERENCES on the table (Codex S1)", "APPLY:tally_core only read it",
     rep("GRANT SELECT ON public.shortfall_applications TO tally_core;", "GRANT SELECT, REFERENCES ON public.shortfall_applications TO tally_core;")),
    ("M54", "the carry's commit check is dropped", "APPLY:a v5.4.2-27 guard is missing",
     rep("ALTER TABLE public.shortfall_applications ENABLE ALWAYS TRIGGER enforce_shortfall_undo_carried;\n", "DROP TRIGGER enforce_shortfall_undo_carried ON public.shortfall_applications;\n")),
    ("M55", "one carry per undo is not kept", "APPLY:customer_credits_one_per_shortfall_undo",
     rep("CREATE UNIQUE INDEX customer_credits_one_per_shortfall_undo ON public.customer_credits (reissues_shortfall_application_id)\n    WHERE reissues_shortfall_application_id IS NOT NULL;",
         "CREATE INDEX customer_credits_one_per_shortfall_undo ON public.customer_credits (reissues_shortfall_application_id)\n    WHERE reissues_shortfall_application_id IS NOT NULL;")),
    ("M35", "the draws' read loses its plan settings (-23's walk pins)", "APPLY:lost its plan settings",
     rep("    RETURNS TABLE (id uuid, on_date date, amount numeric, created_at timestamp with time zone)\n    LANGUAGE sql STABLE\n    SET search_path = public, pg_temp\n    SET enable_seqscan = off\n",
         "    RETURNS TABLE (id uuid, on_date date, amount numeric, created_at timestamp with time zone)\n    LANGUAGE sql STABLE\n    SET search_path = public, pg_temp\n")),
]


def sh(cmd: list[str], inp: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, input=inp, capture_output=True, text=True)


def sh_ordered(cmd: list[str], inp: str | None = None) -> subprocess.CompletedProcess:
    """stdout and stderr in one stream, in the order written."""
    return subprocess.run(cmd, input=inp, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)


def runner(check: str) -> tuple[list[str], str | None, str]:
    """The command, its input, and the check's bare name."""
    if re.fullmatch(r"SR\d+[a-z]?", check):
        return [str(HERE / "races/shortfall-27.sh"), DB], None, check
    battery, name = HERE / "battery-27.sql", check
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
            # r7 (Codex S2): the first error the apply printed, as the
            # behavioral branch takes the first failure.
            first_err = next((l for l in a.stderr.splitlines() if "ERROR" in l), "")
            if phrase is not None and phrase in first_err:
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
        # Fresh statistics for the walks' plans, as tests/ci.sh gives the
        # battery: autovacuum can leave "pages present, 0 rows", which slows
        # the deep lines badly (R21). -22 r4; r8 (Fable S1) added the cash
        # tables the reissue line's walks read; r10 (Codex S1) corrected this
        # comment, which called the vacuumed state the worst.
        v = sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", DB, "-v", "ON_ERROR_STOP=1", "-qc", "VACUUM public.account_ledger, public.payments, public.customer_credits"])
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
