#!/usr/bin/env python3
"""v5.4.2-22 — prove the -22 checks CATCH drift, not merely pass.

Each mutation alters a copy of the patch, applies it (strict: search_path ''
and function-body checking on) to a fresh clone of `tally` with TEMP revoked,
and runs the script that owns the named check:

  battery check (H P C F R W G I)  battery-22.sql
  CR1-CR8                          races/close-22.sh
  APPLY:<phrase>               the patch itself must refuse (its tail runs the
                               invariants), with that phrase

CAUGHT only when the FIRST failure printed is the named check's (the -21
rule). A mutation an EARLIER check catches is reported as missed: its named
check is wrong, or a guard is redundant — fix the name or remove the
duplicate, never loosen the rule.

    python3 tests/v5.4.2-22/mutations-22.py [M07 M12 ...]
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[2]
PATCH = ROOT / "sql/v5.4.2-22-periods-snapshot-gl-aging.sql"
HERE = ROOT / "tests/v5.4.2-22"
DB = "m22"


def rep(old: str, new: str) -> Callable[[str], str]:
    def m(s: str) -> str:
        assert s.count(old) == 1, f"mutation anchor not unique/found ({s.count(old)}): {old[:90]!r}"
        return s.replace(old, new, 1)
    return m


def tail(sql: str) -> Callable[[str], str]:
    """Append statements just before the patch's own invariant run."""
    return rep("DO $$ BEGIN\n    PERFORM public.assert_periods_guard_invariants();",
               sql + "\nDO $$ BEGIN\n    PERFORM public.assert_periods_guard_invariants();")


MUTATIONS = [
    # ---- F: the freeze
    ("M01", "the freeze spares the closed-through day itself", "F2d",
     rep("    IF v_new <= v_through OR v_old <= v_old_through THEN", "    IF v_new < v_through OR v_old < v_old_through THEN")),
    ("M02", "the freeze reads the head without locking it", "CR1",
     rep("     WHERE h.tenant_id = NEW.tenant_id\n       FOR SHARE;", "     WHERE h.tenant_id = NEW.tenant_id;")),
    ("M03", "payments are not frozen", "F2",
     rep("    v_old_through date;\nBEGIN\n    IF TG_OP = 'UPDATE' THEN", "    v_old_through date;\nBEGIN\n    IF TG_TABLE_NAME = 'payments' THEN RETURN NEW; END IF;\n    IF TG_OP = 'UPDATE' THEN")),
    ("M04", "customer credits are not frozen", "F3",
     rep("    v_old_through date;\nBEGIN\n    IF TG_OP = 'UPDATE' THEN", "    v_old_through date;\nBEGIN\n    IF TG_TABLE_NAME = 'customer_credits' THEN RETURN NEW; END IF;\n    IF TG_OP = 'UPDATE' THEN")),
    ("M38", "the freeze trigger on payments fires on date changes only", "APPLY:a v5.4.2-22 guard is missing",
     rep("CREATE TRIGGER a_enforce_accounting_freeze BEFORE INSERT OR UPDATE OF payment_date, tenant_id ON public.payments\n",
         "CREATE TRIGGER a_enforce_accounting_freeze BEFORE UPDATE OF payment_date, tenant_id ON public.payments\n")),
    ("M05", "the owner is exempt from the freeze", "F4",
     rep("    SELECT h.closed_through INTO v_through\n      FROM public.accounting_close_heads h\n     WHERE h.tenant_id = NEW.tenant_id\n       FOR SHARE;",
         "    IF (SELECT r.rolsuper FROM pg_catalog.pg_roles r WHERE r.rolname = current_user) THEN RETURN NEW; END IF;\n    SELECT h.closed_through INTO v_through\n      FROM public.accounting_close_heads h\n     WHERE h.tenant_id = NEW.tenant_id\n       FOR SHARE;")),
    ("M06", "a moved payment is checked on its new date only", "F2c",
     rep("    IF v_new <= v_through OR v_old <= v_old_through THEN", "    IF v_new <= v_through THEN")),
    # ---- P: periods
    ("M07", "no no-gap check", "P3",
     rep("IF v_last IS NOT NULL AND NEW.period_start IS DISTINCT FROM v_last + 1 THEN",
         "IF v_last IS NOT NULL AND NEW.period_start <= v_last THEN")),
    ("M08", "a period may be born closed", "P4",
     rep("IF NEW.status IS DISTINCT FROM 'open' OR NEW.closed_at IS NOT NULL OR NEW.closed_by IS NOT NULL\n           OR NEW.withdrawn_at IS NOT NULL OR NEW.withdrawn_by IS NOT NULL THEN",
         "IF NEW.status NOT IN ('open', 'closed', 'withdrawn') THEN")),
    ("M09", "anyone may close a period by UPDATE", "P8b",
     rep("    IF current_user = 'tally_close'\n       AND OLD.status = 'open'", "    IF true\n       AND OLD.status = 'open'")),
    ("M10", "a period insert at any isolation, with no chain lock", "CR6",
     rep("        PERFORM pg_advisory_xact_lock(hashtextextended('accounting_periods:' || NEW.tenant_id::text, 0));\n", "")),
    # ---- H: the head
    ("M11", "the owner may move the head", "H3",
     rep("    IF current_user <> 'tally_close'\n       OR NEW.tenant_id", "    IF false\n       OR NEW.tenant_id")),
    ("M12", "a head may be born closed", "H2",
     rep("        IF NEW.closed_through IS NOT NULL THEN", "        IF false THEN")),
    ("M13", "no head for a new tenant (trigger origin-only)", "APPLY:a v5.4.2-22 guard is missing",
     rep("ALTER TABLE public.tenants ENABLE ALWAYS TRIGGER create_accounting_close_head;\n", "")),
    # ---- C: the close
    ("M14", "an operator may close", "C1",
     rep("IF v_user IS NULL OR NOT public.session_is_supervisor() THEN", "IF v_user IS NULL THEN")),
    ("M15", "after a close, periods close out of order", "C15d",
     rep("       OR (v_through IS NOT NULL AND v_through <> v_p.period_start - 1) THEN", "       OR false THEN")),
    ("M16", "a period closes before it has ended", "C5",
     rep("IF v_p.period_end >= (pg_catalog.now() AT TIME ZONE 'Etc/GMT+12')::date THEN", "IF v_p.period_end > (pg_catalog.now() AT TIME ZONE 'Etc/GMT+12')::date + 400 THEN")),
    ("M17", "the opening balance takes in the period's first day", "C9",
     rep("l.transaction_date < v_p.period_start AND l.created_at <= v_at;", "l.transaction_date <= v_p.period_start AND l.created_at <= v_at;")),
    ("M18", "the head does not move", "C8",
     rep("    UPDATE public.accounting_close_heads SET closed_through = v_p.period_end, updated_at = v_at WHERE tenant_id = v_tenant;\n", "")),
    ("M19", "the aging is taken at the period's first day", "C11",
     rep("receivables_aging_as_of(v_tenant, v_p.period_end, v_at, v_edges) a", "receivables_aging_as_of(v_tenant, v_p.period_start, v_at, v_edges) a")),
    ("M20", "the close runs at any isolation", "CR4",
     rep("    IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('close_accounting_period() runs",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('close_accounting_period() runs")),
    ("M21", "anyone may write a snapshot line", "C15c",
     rep("IF TG_OP = 'INSERT' AND current_user = 'tally_close' THEN", "IF TG_OP = 'INSERT' THEN")),
    # ---- R: recovery
    ("M22", "no sign check", "R4",
     rep("IF NOT (v_parent.amount < 0 AND NEW.amount > 0) THEN", "IF false THEN")),
    ("M23", "no cap", "R6",
     rep("         WHERE x.net < 0 OR x.net > -v_wo.amount\n", "         WHERE false\n")),
    ("M24", "another customer's write-off", "R3",
     rep("OR v_parent.tenant_id <> NEW.tenant_id OR v_parent.customer_id <> NEW.customer_id THEN", "OR v_parent.tenant_id <> NEW.tenant_id THEN")),
    ("M25", "the recovery takes no lock", "CR5",
     rep("        PERFORM pg_advisory_xact_lock(hashtextextended('write_off_recovery:' || v_wo_id::text, 0));\n", "")),
    # ---- W: aging
    ("M26", "the balance is aged oldest first", "W2",
     rep("ORDER BY o.transaction_date DESC, o.created_at DESC, o.id DESC", "ORDER BY o.transaction_date, o.created_at, o.id")),
    ("M27", "no netting of reversals", "W3",
     rep("         WHERE NOT EXISTS (SELECT 1 FROM l p WHERE p.id = r.reverses_ledger_entry_id AND p.customer_id = r.customer_id)\n        UNION ALL\n        SELECT c.id, t.root, c.customer_id\n          FROM l c JOIN tree t ON c.reverses_ledger_entry_id = t.id AND c.customer_id = t.customer_id",
         "        UNION ALL\n        SELECT c.id, t.root, c.customer_id\n          FROM l c JOIN tree t ON false")),
    ("M28", "a bucket's upper edge falls into the next", "W3",
     rep("WHERE e < (p_on - o.transaction_date)", "WHERE e <= (p_on - o.transaction_date)")),
    ("M29", "netting across customers", "W13",
     rep("SELECT c.id, t.root, c.customer_id\n          FROM l c JOIN tree t ON c.reverses_ledger_entry_id = t.id AND c.customer_id = t.customer_id",
         "SELECT c.id, t.root, c.customer_id\n          FROM l c JOIN tree t ON c.reverses_ledger_entry_id = t.id")),
    ("M30", "no aging bucket CHECK", "APPLY:a v5.4.2-22 constraint is missing",
     rep("ALTER TABLE public.tenants ADD CONSTRAINT tenants_receivables_aging_bucket_days_check\n    CHECK (public.aging_bucket_days_valid(receivables_aging_bucket_days));\n", "")),
    # ---- G: GL mapping
    ("M31", "no stated precedence: every key part weighs the same", "G6b",
     rep("8 * (m.charge_code IS NOT NULL)::integer + 4 * (m.customer_class IS NOT NULL)::integer\n             + 2 * (m.territory_place_id",
         "(m.charge_code IS NOT NULL)::integer + (m.customer_class IS NOT NULL)::integer\n             + (m.territory_place_id")),
    ("M32", "a close is known before it is recorded", "CR8",
     rep("                OR (m.closed_at IS NOT NULL AND m.closed_at > p_recorded_at))", "                OR false)")),
    ("M33", "no close floor", "G7b",
     rep("IF v_through IS NOT NULL AND NEW.effective_to <= v_through THEN", "IF false THEN")),
    ("M34", "no insert floor", "G4",
     rep("IF v_through IS NOT NULL AND (NEW.effective_from <= v_through OR NEW.effective_to <= v_through) THEN", "IF false THEN")),
    # ---- r2
    ("M39", "an adjustment may name a write-off", "R7",
     rep("    ELSIF FOUND AND v_parent.transaction_type = 'write_off' THEN", "    ELSIF false THEN")),
    ("M40", "no loop check", "R8",
     rep("    IF v_loop THEN", "    IF false THEN")),
    ("M41", "aging does not check every entry reaches an original", "W16",
     rep("    IF v_uncovered <> 0 THEN", "    IF false THEN")),
    ("M42", "a move between tenants is checked against the new tenant only", "F2e",
     rep("    IF TG_OP = 'UPDATE' AND OLD.tenant_id IS NOT DISTINCT FROM NEW.tenant_id THEN\n        v_old_through := v_through;", "    IF TG_OP = 'UPDATE' THEN\n        v_old_through := v_through;")),
    ("M43", "the validator takes any lower bound", "W1d",
     rep("       AND array_lower(p_days, 1) = 1\n", "")),
    ("M44", "a recorded value is not validated", "W10f",
     rep("    SELECT CASE\n        WHEN jsonb_typeof(p_value) IS DISTINCT FROM 'array' THEN false", "    SELECT CASE\n        WHEN true THEN true")),
    ("M51", "the history CHECK is dropped", "APPLY:a v5.4.2-22 constraint is missing",
     rep("ALTER TABLE public.tenant_configuration_history ADD CONSTRAINT tenant_configuration_history_aging_days_check\n    CHECK (config_key <> 'receivables_aging_bucket_days'::text OR public.aging_bucket_days_json_valid(new_value));",
         "")),
    ("M45", "the close freezes rows recorded after its instant", "C19",
     rep("                WHERE l.tenant_id = v_tenant AND l.transaction_date <= v_p.period_end AND l.created_at > v_at) THEN",
         "                WHERE false) THEN")),
    ("M46", "a mapping is recorded at the transaction start", "G1d",
     rep("        NEW.created_at := pg_catalog.clock_timestamp();", "        NEW.created_at := now();")),
    ("M47", "any open period may be withdrawn", "P9a",
     rep("                    WHERE p.tenant_id = OLD.tenant_id AND p.status <> 'withdrawn' AND p.period_start > OLD.period_start) THEN",
         "                    WHERE false) THEN")),
    ("M48", "a closed latest period may be withdrawn", "P9e",
     rep("    IF OLD.status = 'open' AND NEW.status = 'withdrawn'", "    IF NEW.status = 'withdrawn'")),
    ("M52", "a withdrawn period still holds its dates", "P9c",
     rep("SELECT max(p.period_end) INTO v_last FROM public.accounting_periods p WHERE p.tenant_id = NEW.tenant_id AND p.status <> 'withdrawn';",
         "SELECT max(p.period_end) INTO v_last FROM public.accounting_periods p WHERE p.tenant_id = NEW.tenant_id;")),
    ("M49", "aging takes no explicit edges: it ages by the tenant's live setting", "W12b",
     rep("    IF NOT EXISTS (SELECT 1 FROM public.accounting_close_heads h WHERE h.tenant_id = p_tenant_id) THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('receivables_aging_as_of: tenant %s is not visible",
         "    SELECT t.receivables_aging_bucket_days INTO v_edges FROM public.tenants t WHERE t.id = p_tenant_id;\n    IF NOT EXISTS (SELECT 1 FROM public.accounting_close_heads h WHERE h.tenant_id = p_tenant_id) THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('receivables_aging_as_of: tenant %s is not visible")),
    ("M50", "the threshold may be zero", "APPLY:a v5.4.2-22 constraint is missing",
     rep("    CHECK (write_off_threshold_days IS NULL OR write_off_threshold_days > 0);", "    CHECK (write_off_threshold_days IS NULL OR write_off_threshold_days >= 0);")),
    # ---- r3
    ("M53", "the write-off rule runs before the statement's later rows are in", "APPLY:a v5.4.2-22 guard is missing",
     rep("CREATE TRIGGER enforce_write_off_recovery AFTER INSERT ON public.account_ledger\n",
         "CREATE TRIGGER enforce_write_off_recovery BEFORE INSERT ON public.account_ledger\n")),
    ("M54", "the cap counts the write-off's direct rows only", "R10",
     rep("              FROM down d JOIN public.account_ledger l ON l.reverses_ledger_entry_id = d.id\n",
         "              FROM down d JOIN public.account_ledger l ON false\n")),
    ("M55", "the cap has no floor", "R10b",
     rep("WHERE x.net < 0 OR x.net > -v_wo.amount", "WHERE x.net > -v_wo.amount")),
    ("M56", "only a row naming the write-off directly is capped", "R10",
     rep("             WHERE u.mine AND u.depth < c_max\n",
         "             WHERE false\n")),
    ("M62", "the cap counts another customer's row naming into the tree", "R10f",
     rep("SELECT array_agg(d.id) INTO v_tree FROM down d WHERE d.mine;", "SELECT array_agg(d.id) INTO v_tree FROM down d;")),
    ("M63", "the cap's walk finds each step through the customer's ledger", "R10g",
     rep("             WHERE d.mine\n", "             WHERE d.mine AND l.tenant_id = v_wo.tenant_id AND l.customer_id = v_wo.customer_id\n")),
    ("M64", "a row under a write-off may be dated before the entry it names", "R12b",
     rep("        IF NEW.transaction_date < v_parent.transaction_date THEN", "        IF false THEN")),
    ("M65", "the cap holds only at the end, not at every date", "R12",
     rep("sum(l.amount) OVER (ORDER BY l.transaction_date) AS net", "sum(l.amount) OVER () AS net")),
    ("M66", "a row may be recorded before a row already in its tree", "R12e",
     rep("AND l.created_at > NEW.created_at", "AND false")),
    ("M67", "a change of the aging edges does not wait for the close", "CR13",
     rep("        PERFORM 1 FROM public.accounting_close_heads h WHERE h.tenant_id = NEW.id FOR SHARE;\n",
         "        PERFORM 1 FROM public.accounting_close_heads h WHERE h.tenant_id = NEW.id;\n")),
    ("M68", "the cap's walks are planned by the statistics", "APPLY:lost its plan settings",
     rep("CREATE OR REPLACE FUNCTION public.enforce_write_off_recovery() RETURNS trigger\n    LANGUAGE plpgsql\n    SET search_path = public, pg_temp\n    SET enable_seqscan = off\n    SET enable_hashjoin = off\n    SET enable_mergejoin = off\n",
         "CREATE OR REPLACE FUNCTION public.enforce_write_off_recovery() RETURNS trigger\n    LANGUAGE plpgsql\n    SET search_path = public, pg_temp\n")),
    ("M69", "a row under a write-off may be recorded in the future", "R12g",
     rep("        IF v_future THEN\n", "        IF false THEN\n")),
    ("M70", "a write-off may be recorded in the future", "R12f",
     rep("    IF NEW.transaction_type = 'write_off' AND v_future THEN", "    IF false THEN")),
    ("M71", "rows of one date are netted one by one, not together", "R10f",
     rep("sum(l.amount) OVER (ORDER BY l.transaction_date) AS net", "sum(l.amount) OVER (ORDER BY l.transaction_date ROWS UNBOUNDED PRECEDING) AS net")),
    ("M72", "the trigger does not fire for a write-off", "APPLY:a v5.4.2-22 guard is missing",
     rep("FOR EACH ROW WHEN (NEW.reverses_ledger_entry_id IS NOT NULL OR NEW.transaction_type = 'write_off') EXECUTE FUNCTION public.enforce_write_off_recovery();",
         "FOR EACH ROW WHEN (NEW.reverses_ledger_entry_id IS NOT NULL) EXECUTE FUNCTION public.enforce_write_off_recovery();")),
    ("M57", "the lineage walk does not fail closed at its bound", "R11",
     rep("    IF v_long THEN", "    IF false THEN")),
    ("M58", "a withdrawal need not name its user", "P9f",
     rep("        IF NEW.withdrawn_by IS NULL THEN", "        IF false THEN")),
    ("M59", "a withdrawn period is reported as closed", "C13b",
     rep("    IF v_p.status = 'withdrawn' THEN", "    IF false THEN")),
    ("M60", "the close ages by fixed edges, not the tenant's setting at its instant", "C16b",
     rep("    SELECT t.receivables_aging_bucket_days INTO v_edges FROM public.tenants t WHERE t.id = v_tenant;",
         "    v_edges := '{30,60,90,120}';")),
    ("M61", "the history's known-key CHECK is dropped", "APPLY:a v5.4.2-22 constraint is missing",
     tail("ALTER TABLE public.tenant_configuration_history DROP CONSTRAINT tenant_configuration_history_key_known_check;")),
    # ---- the seal
    ("M35", "tally_close is granted more", "APPLY:tally_close holds other privileges",
     tail("GRANT INSERT ON public.account_ledger TO tally_close;")),
    ("M36", "the application may move the head", "APPLY:writable outside close_accounting_period()",
     tail("GRANT UPDATE (closed_through) ON public.accounting_close_heads TO tally_app;")),
    ("M37", "the close is not owned by tally_close", "APPLY:no longer owns",
     rep("ALTER FUNCTION public.close_accounting_period(uuid, numeric, text) OWNER TO tally_close;\n", "")),
]


def sh(cmd: list[str], inp: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, input=inp, capture_output=True, text=True)


def sh_ordered(cmd: list[str], inp: str | None = None) -> subprocess.CompletedProcess:
    """stdout and stderr in one stream, in the order written."""
    return subprocess.run(cmd, input=inp, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)


def runner(check: str) -> tuple[list[str], str | None]:
    if re.fullmatch(r"CR\d+", check):
        return [str(HERE / "races/close-22.sh"), DB], None
    # A mutation that loops must report, not hang: a timeout is a MISS (ERROR before the named FAIL).
    return ["docker", "exec", "-i", "-e", "PGOPTIONS=-c statement_timeout=300s", "tally-pg", "psql", "-U", "tally", "-d", DB, "-v", "ON_ERROR_STOP=1", "-q", "-o", "/dev/null", "-f", "-"], \
        (HERE / "battery-22.sql").read_text()


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
        # planner believes empty (r4: R10g took 30 s there, not on a fresh clone).
        v = sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", DB, "-v", "ON_ERROR_STOP=1", "-qc", "VACUUM public.account_ledger"])
        if v.returncode:
            print(f"{mid} SETUP-ERROR: {v.stderr.strip()[:140]}")
            missed += 1
            continue
        cmd, inp = runner(check)
        out = sh_ordered(cmd, inp)
        text = out.stdout
        first = next((l for l in text.splitlines() if "FAIL" in l or "ERROR" in l), "")
        first = re.sub(r"^psql:[^:]+:\d+: ", "", first)[:140]
        # The first line that reports any failure, infrastructure errors included, must be the named check's.
        fails = [re.sub(r"^.*?(FAIL )", r"\1", l) for l in text.splitlines() if re.search(r"\bFAIL\b|ERROR|FATAL|PANIC", l)]
        if fails and re.match(rf"FAIL {re.escape(check)}[:\s]", fails[0]):
            print(f"{mid} caught at {check}: {what}")
        else:
            print(f"{mid} MISSED ({check}): {what}  [first: {first}]")
            missed += 1
    print(f"{ran - missed}/{ran} caught")
    sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-qc", f"DROP DATABASE IF EXISTS {DB}"])
    return 1 if missed else 0


if __name__ == "__main__":
    sys.exit(main())
