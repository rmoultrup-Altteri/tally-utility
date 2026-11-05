#!/usr/bin/env python3
"""v5.4.2-27 — prove the -27 checks CATCH drift, not merely pass.

Each mutation alters a copy of the patch, applies it (strict: search_path ''
and function-body checking on) to a fresh clone of `tally` with TEMP revoked,
and runs the script that owns the named check:

  battery check (K S F U H B D I)     battery-27.sql
  SR1-SR8                           races/shortfall-27.sh
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
     rep("CASE WHEN NEW.basis = 'undo' THEN 'undo' WHEN v_within THEN 'shortfall_within_family' ELSE 'shortfall' END",
         "CASE WHEN NEW.basis = 'undo' THEN 'undo' ELSE 'shortfall' END")),
    ("M13", "every shortfall application skips the family cap", "F1a",
     rep("p_purpose NOT IN ('reissue', 'overpayment_credit', 'shortfall_within_family') THEN", "p_purpose NOT IN ('reissue', 'overpayment_credit', 'shortfall_within_family', 'shortfall') THEN")),
    ("M14", "a repayment is not held to the target's cap", "K1",
     rep("        PERFORM public.check_shortfall_repaid(NEW.target_payment_id, NEW.applied_on);", "        NULL;")),
    ("M15", "an undo giving a repaid family money back is not checked", "U2",
     rep("        PERFORM public.check_shortfall_repaid(CASE WHEN p_kind = 'payment' THEN p_id ELSE v_pool_pay END, NULL);", "        NULL;")),
    ("M16", "a refund leaving a repaid family is not checked (Ryan, 2026-11-05)", "S2",
     rep("        PERFORM public.check_shortfall_repaid(coalesce(NEW.refunds_payment_id,", "        PERFORM pg_catalog.num_nulls(coalesce(NEW.refunds_payment_id,")),
    ("M17", "a move giving money back is checked from the first repayment's date (the S4 shape)", "S4",
     rep("    SELECT max(s.applied_on) INTO v_from FROM public.shortfall_applications s", "    SELECT min(s.applied_on) INTO v_from FROM public.shortfall_applications s")),
    ("M18", "a repayment is checked only from the latest row's date, not its own", "H2",
     rep("    v_from := coalesce(p_from, v_from);", "    v_from := greatest(p_from, v_from);")),
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
    ("M23", "the target's repayments are not among its draws", "K5",
     rep("    SELECT s.id, s.applied_on, -s.amount, s.created_at FROM public.shortfall_applications s\n     WHERE p_kind = 'payment' AND s.target_payment_id = p_id",
         "    SELECT s.id, s.applied_on, -s.amount, s.created_at FROM public.shortfall_applications s\n     WHERE false")),
    ("M24", "a credit's position does not count its shortfall applications", "K3",
     rep("                   WHERE s.customer_credit_id = p_credit_id AND s.applied_on <= p_on AND s.created_at <= p_recorded_at), 0),",
         "                   WHERE false), 0),")),
    ("M25", "a payment's position does not count its money applied to a shortfall", "K6b",
     rep("                   WHERE s.payment_id = p_payment_id AND s.applied_on <= p_on AND s.created_at <= p_recorded_at), 0),",
         "                   WHERE false), 0),")),
    ("M26", "a payment's position does not count what was repaid", "K3",
     rep("                   WHERE s.target_payment_id = p_payment_id AND s.applied_on <= p_on AND s.created_at <= p_recorded_at), 0)\n$$;",
         "                   WHERE false), 0)\n$$;")),
    ("M27", "repaid is shown but not counted in remaining", "K3",
     rep("d.received - d.applied - x.credited - d.refunded + d.repaid, d.repaid", "d.received - d.applied - x.credited - d.refunded, d.repaid")),
    ("M28", "the cover does not place a repayment on the payment's own part", "F3",
     rep("SELECT d.received - d.applied - d.refunded + d.repaid - (k.original_amount", "SELECT d.received - d.applied - d.refunded - (k.original_amount")),
    ("M29", "a repayment counts before its money date", "K3c",
     rep("                   WHERE s.target_payment_id = p_payment_id AND s.applied_on <= p_on AND s.created_at <= p_recorded_at), 0)\n$$;",
         "                   WHERE s.target_payment_id = p_payment_id AND s.created_at <= p_recorded_at), 0)\n$$;")),
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
