#!/usr/bin/env python3
"""v5.4.2-23 — prove the -23 checks CATCH drift, not merely pass.

Each mutation alters a copy of the patch, applies it (strict: search_path ''
and function-body checking on) to a fresh clone of `tally` with TEMP revoked,
and runs the script that owns the named check:

  battery check (T A M C X LC F I)  battery-23.sql
  b22:<check>                       battery-22.sql (the -22 rows -23 re-reads)
  CR1-CR8                           races/cash-23.sh
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
PAY_CAUSE = "        IF NEW.status_cause_id IS DISTINCT FROM OLD.status_cause_id THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('payment %s: status_cause_id"

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
     rep("    IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('a reversal",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('a reversal")),
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
     rep("p.amount - x.applied - x.credited - x.refunded", "p.amount - x.applied - x.refunded")),
    # ---- M2, M3: write-once and status moves
    ("N24", "a payment's amount is not fixed", "M2",
     rep("ARRAY['id', 'tenant_id', 'payment_number', 'customer_id', 'payment_date', 'amount',", "ARRAY['id', 'tenant_id', 'payment_number', 'customer_id', 'payment_date',")),
    ("N25", "a later reference may be rewritten", "M2c",
     rep("        IF v_old -> v_col <> 'null'::jsonb AND v_new -> v_col IS DISTINCT FROM v_old -> v_col THEN", "        IF false THEN")),
    ("N26", "a payment's restriction is not fixed", "M2d",
     rep("        'restricted_to_line_item_id', 'nsf_original_payment_id',", "        'nsf_original_payment_id',")),
    ("N27", "a payment's cause may change without its status", "M3e",
     rep(PAY_CAUSE, PAY_CAUSE.replace("IF NEW.status_cause_id IS DISTINCT FROM OLD.status_cause_id THEN", "IF false THEN"))),
    ("N28", "a posted payment may return to pending", "M3d",
     rep("            OR (OLD.status = 'posted' AND NEW.status IN ('nsf', 'reversed', 'refunded'))) THEN",
         "            OR (OLD.status = 'posted' AND NEW.status IN ('nsf', 'reversed', 'refunded', 'pending'))) THEN")),
    ("N29", "a move to posted names nothing", "M3",
     rep("        WHEN 'posted' THEN EXISTS (", "        WHEN 'posted' THEN NEW.status_cause_id IS NULL OR EXISTS (")),
    ("N30", "a move to posted may name another payment's entry", "M3b",
     rep("AND l.reference_type IN ('payment', 'refund') AND l.reference_id = NEW.id AND l.amount = -NEW.amount)",
         "AND l.reference_type IN ('payment', 'refund'))")),
    ("N31", "bounced money still pays bills", "M3f",
     rep("    IF NEW.status IN ('nsf', 'reversed', 'voided') THEN", "    IF false THEN")),
    ("N32", "a payment's move takes no source lock", "CR3",
     rep("    PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('payment', OLD.id));\n", "")),
    ("N33", "a payment is refunded with money left", "M3i",
     rep("        IF v_left IS DISTINCT FROM 0 THEN", "        IF false THEN")),
    ("N34", "a credit is voided while applied", "M3h",
     rep("    IF NEW.status = 'voided' AND (v_pos.applied <> 0 OR v_pos.refunded <> 0) THEN", "    IF false THEN")),
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
     rep("     WHERE x.drawn > v_amount\n", "     WHERE x.drawn > v_amount + 1000000\n")),
    ("N40", "a refund does not draw on its payment", "C1l",
     rep("     WHERE r.status IN ('pending', 'posted')\n       AND ((p_kind = 'payment'", "     WHERE false\n       AND ((p_kind = 'payment'")),
    ("N41", "an overpayment credit does not draw on its payment", "C1k",
     rep("     WHERE p_kind = 'payment' AND c.source_payment_id = p_id AND c.origin_type = 'overpayment'\n    UNION ALL",
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
     rep("NOT (v_pay.status = 'posted' AND NOT v_pay.is_deposit AND v_pay.amount > 0)", "NOT (NOT v_pay.is_deposit AND v_pay.amount > 0)")),
    ("N52", "a deposit pays a bill", "A3g",
     rep("NOT (v_pay.status = 'posted' AND NOT v_pay.is_deposit AND v_pay.amount > 0)", "NOT (v_pay.status = 'posted' AND v_pay.amount > 0)")),
    ("N53", "a voided credit pays", "A3k",
     rep("        IF v_kind = 'credit' AND v_cred.status <> 'active' THEN", "        IF false THEN")),
    ("N54", "money is applied before it arrived", "A3i",
     rep("        IF NEW.applied_on < v_src_date OR NEW.applied_on < v_inv.invoice_date THEN", "        IF NEW.applied_on < v_inv.invoice_date THEN")),
    ("N55", "money is applied before its bill", "A3l",
     rep("        IF NEW.applied_on < v_src_date OR NEW.applied_on < v_inv.invoice_date THEN", "        IF NEW.applied_on < v_src_date THEN")),
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
     rep("        SELECT p.status, p.status = 'posted' AND NOT p.is_deposit AND p.amount > 0 AND NEW.issued_date >= p.payment_date",
         "        SELECT p.status, NOT p.is_deposit AND p.amount > 0 AND NEW.issued_date >= p.payment_date")),
    ("N61", "a refund or credit draw skips the source cap", "C1k",
     rep("    PERFORM public.check_cash_source(v_kind, v_id, NEW.created_at);\n    RETURN NULL;", "    RETURN NULL;")),
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
    ("N68", "one approval may make two credits", "APPLY:customer_credits_one_per_approval is missing",
     rep("CREATE UNIQUE INDEX customer_credits_one_per_approval ON public.customer_credits (approval_id) WHERE approval_id IS NOT NULL;\n",
         "CREATE INDEX customer_credits_one_per_approval ON public.customer_credits (approval_id) WHERE approval_id IS NOT NULL;\n")),
    ("N69", "a counter comes back as a column", "APPLY:is a column again",
     tail("ALTER TABLE public.payments ADD COLUMN applied_amount numeric;")),
    ("N70", "the cap's walk stops two short of the lineage bound (it fails closed)", "b22:R11b",
     rep("    c_max      CONSTANT integer := 1000;", "    c_max      CONSTANT integer := 998;")),
    ("N71", "the cap's walk stops short and takes the entry it reached for the root", "b22:R11e",
     lambda x: rep("    IF v_root.reverses_ledger_entry_id IS NOT NULL THEN", "    IF false THEN")(
         rep("    c_max      CONSTANT integer := 1000;", "    c_max      CONSTANT integer := 998;")(x))),
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
