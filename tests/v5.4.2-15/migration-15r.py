#!/usr/bin/env python3
"""v5.4.2-15 (rewrite) — the migration itself, on clones of a PRE-15 base (default `tally`, the -18 build):

  P0  the patch applies strictly to the base as it is (no deposit data): search_path empty, function bodies checked
  P1  a base holding carried deposits (basis legacy_unknown, as -06's backfill made them): after the patch every row of
      the four old tables is unchanged in every column it had; a carried deposit cites no law row and still returns only
      with a stated reason; no accrual can be written on it
  P2  a second application changes nothing; P2b, once real data exists, it still says so
  P3  a real (non-legacy) deposit stops the patch, naming it; the database is untouched
  P4  a waiver determination stops the patch likewise
  P5  a utility's own interest rate row stops it likewise
  P6  the -06 Texas law is gone (functions and the refund-due view), and the first draft's child tables never appeared

P3-P5 are the standing precondition (Ryan, 2026-09-28: nothing is live; the patch will not invent the law row, state and
service the core never recorded). Only the carried legacy deposits, which cite no law row, go through.

PATCH15=<path> python3 ... runs a different patch text (the mutation runner does).

    python3 tests/v5.4.2-15/migration-15r.py [base-db]
"""
from __future__ import annotations

import atexit
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATCH = Path(os.environ.get("PATCH15") or ROOT / "sql/v5.4.2-15-deposits-law-to-core.sql")
BASE = sys.argv[1] if len(sys.argv) > 1 else "tally"
STRICT = "-c search_path= -c check_function_bodies=on"
RUN = str(os.getpid())
fails = 0

T1 = "00000000-0000-4000-8000-0000000015a1"
T2 = "00000000-0000-4000-8000-0000000015a2"
U1 = "00000000-0000-4000-8000-0000000015b1"
C1 = "00000000-0000-4000-8000-0000000015c1"
C2 = "00000000-0000-4000-8000-0000000015c2"
DEP = "00000000-0000-4000-8000-0000000015ee"
DEP2 = "00000000-0000-4000-8000-0000000015ef"
DEP3 = "00000000-0000-4000-8000-0000000015f0"


def sh(cmd: list[str], inp: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, input=inp, capture_output=True, text=True)


def _cleanup() -> None:
    """Drop every clone this run made, however it ends (a crash must not leave databases behind)."""
    names = sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-Atc",
                f"SELECT datname FROM pg_database WHERE datname ~ '^m15_[a-z]_{RUN}$'"]).stdout.split()
    for n in names:
        sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-qc", f"DROP DATABASE IF EXISTS {n}"])


atexit.register(_cleanup)


def nm(name: str) -> str:
    return name if (not name.startswith("m15_") or name.endswith("_" + RUN)) else f"{name}_{RUN}"


def psql(db: str, sql: str, check: bool = True, role: str | None = None, user: str | None = None) -> subprocess.CompletedProcess:
    pre = ""
    if user:
        pre += f"SELECT set_config('app.user_id', '{user}', false);\n"
    if role:
        pre += f"SET ROLE {role};\n"
    r = sh(["docker", "exec", "-i", "tally-pg", "psql", "-U", "tally", "-d", nm(db), "-v", "ON_ERROR_STOP=1", "-q", "-At", "-f", "-"], pre + sql)
    if check and r.returncode != 0:
        raise RuntimeError(r.stderr.strip())
    return r


def one(db: str, sql: str) -> str:
    return psql(db, sql).stdout.strip()


def probe(db: str, sql: str) -> str:
    """A yes/no query whose failure (a column the patch should have added is missing) is a failed check, not a crash."""
    try:
        return one(db, sql)
    except RuntimeError as exc:
        return f"error: {str(exc)[:120]}"


def clone(name: str) -> None:
    name = nm(name)
    sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-qc", f"DROP DATABASE IF EXISTS {name}", "-qc", f"CREATE DATABASE {name} TEMPLATE {BASE}"])
    psql(name, f"REVOKE TEMP ON DATABASE {name} FROM PUBLIC; REVOKE TEMP ON DATABASE {name} FROM tally_app; REVOKE TEMP ON DATABASE {name} FROM tally_core;")


def apply(db: str) -> subprocess.CompletedProcess:
    sh(["docker", "cp", str(PATCH), f"tally-pg:/tmp/m15_{RUN}.sql"])
    return sh(["docker", "exec", "-e", f"PGOPTIONS={STRICT}", "tally-pg", "psql", "-U", "tally", "-d", nm(db), "-v", "ON_ERROR_STOP=1", "-q", "-f", f"/tmp/m15_{RUN}.sql"])


def report(label: str, ok: bool, detail: str = "") -> None:
    global fails
    print(("PASS " if ok else "FAIL ") + label + (f": {detail}" if detail and not ok else ""))
    if not ok:
        fails += 1


OLD_TABLES = ["deposits", "deposit_events", "deposit_interest_rates", "deposit_waiver_determinations"]
DUMP = "SELECT coalesce(jsonb_object_agg(t, rows), '{}') FROM (" + " UNION ALL ".join(
    f"SELECT '{t}' AS t, coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id), '[]') AS rows FROM public.{t} x" for t in OLD_TABLES) + ") q"


def plant(db: str, waiver: bool = False, rate: bool = False, real_deposit: bool = False) -> None:
    """A utility with two carried deposits (as -06's backfill made them) and, when asked, what the patch refuses to run over."""
    psql(db, f"""
INSERT INTO public.tenants (id, name, slug) VALUES ('{T1}', 'M15 Gasco', 'm15-t1');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES ('{U1}', '{T1}', 'Op1', 'op1@m15.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES
  ('{C1}', '{T1}', 'M15-C1', 'residential'), ('{C2}', '{T1}', 'M15-C2', 'residential');
ALTER TABLE public.deposits DISABLE TRIGGER a_enforce_deposit;
INSERT INTO public.deposits (id, tenant_id, customer_id, basis, instrument, principal, posted_on, legacy_interest_earned) VALUES
  ('{DEP}', '{T1}', '{C2}', 'legacy_unknown', 'cash', 80, DATE '2024-01-01', 3.10),
  ('{DEP2}', '{T1}', '{C1}', 'legacy_unknown', 'letter_of_credit', 500, DATE '2023-05-01', NULL);
ALTER TABLE public.deposits ENABLE ALWAYS TRIGGER a_enforce_deposit;
""".replace("'letter_of_credit', 500, DATE '2023-05-01', NULL)", "'cash', 500, DATE '2023-05-01', NULL)"))
    if real_deposit:
        psql(db, f"""
ALTER TABLE public.deposits DISABLE TRIGGER a_enforce_deposit;
INSERT INTO public.deposits (id, tenant_id, customer_id, basis, instrument, principal, posted_on)
VALUES ('{DEP3}', '{T1}', '{C1}', 'credit_evaluation', 'cash', 100, DATE '2026-01-15');
ALTER TABLE public.deposits ENABLE ALWAYS TRIGGER a_enforce_deposit;
""")
    if waiver:
        psql(db, f"""INSERT INTO public.deposit_waiver_determinations (tenant_id, customer_id, waiver_class, determined_on)
                    VALUES ('{T1}', '{C1}', 'good_payment_history', DATE '2025-03-01');""")
    if rate:
        psql(db, f"""INSERT INTO public.deposit_interest_rates (tenant_id, effective_date, annual_rate, source_reference)
                    VALUES ('{T1}', DATE '2024-06-01', 0.05, 'tariff 4.2');""")


def unchanged(db: str, dump: dict, label: str) -> None:
    """Every row of the old tables is still there, with every column it had unchanged."""
    post = json.loads(one(db, DUMP))
    bad = []
    for t in OLD_TABLES:
        byid = {r["id"]: r for r in post[t]}
        if len(post[t]) != len(dump[t]):
            bad.append(f"{t}: {len(dump[t])} rows before, {len(post[t])} after")
        for row in dump[t]:
            now = byid.get(row["id"])
            if now is None:
                bad.append(f"{t} {row['id']} vanished")
                continue
            for k, v in row.items():
                if now.get(k) != v:
                    bad.append(f"{t} {row['id']}: {k} {v!r} -> {now.get(k)!r}")
    report(label, not bad, "; ".join(bad[:3]))


def untouched(db: str, label: str) -> None:
    """The patch aborted: nothing of it is in the database."""
    q = """SELECT NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.deposit_interest_rates'::regclass AND attname = 'state_code' AND NOT attisdropped)
         AND to_regclass('public.deposit_rules') IS NULL AND to_regclass('public.deposit_tariffs') IS NULL
         AND to_regclass('public.deposit_customer_classes') IS NULL
         AND NOT EXISTS (SELECT 1 FROM public.rule_term_schemas WHERE terms_kind IN ('deposit', 'deposit_tariff'))
         AND to_regprocedure('public.deposit_accrual_amount(numeric,numeric,date,date)') IS NOT NULL
         AND to_regclass('public.deposits_refund_due') IS NOT NULL"""
    report(label, probe(db, q) == "t", "the database was changed although the patch aborted")


# ---- the base must be a pre-15 build with the rule-terms template
if one(BASE, "SELECT to_regclass('public.rule_tables') IS NOT NULL AND to_regclass('public.deposit_rules') IS NULL "
             "AND to_regprocedure('public.deposit_accrual_amount(numeric,numeric,date,date)') IS NOT NULL") != "t":
    print(f"{BASE} is not a pre-15 build with the -17/-18 template: this script needs one")
    sys.exit(2)

# ---- P0: the base as it is
clone("m15_z")
r = apply("m15_z")
report("P0: the patch applies strictly to a base with no deposit data", r.returncode == 0, r.stderr.strip()[-300:])

# ---- P1, P2
clone("m15_a")
plant("m15_a")
dump = json.loads(one("m15_a", DUMP))
r = apply("m15_a")
report("P1a: the patch applies strictly to a base holding two carried deposits", r.returncode == 0, r.stderr.strip()[-300:])
unchanged("m15_a", dump, "P1b: every row of the four old tables is still there with every column it had")
legacy = probe("m15_a", f"""SELECT count(*) = 2 AND bool_and(basis = 'legacy_unknown' AND rule_id IS NULL AND tariff_id IS NULL AND state_code IS NULL AND customer_class IS NULL)
     FROM public.deposits WHERE id IN ('{DEP}', '{DEP2}')""")
report("P1c: the carried deposits cite no law row, no tariff row, no class: nobody decided them under any", legacy == "t", legacy)
r = psql("m15_a", f"""INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on)
                     VALUES ('{T1}', '{DEP}', 'refunded', 80, DATE '2026-03-01')""", check=False, role="tally_app", user=U1)
report("P1d: a carried deposit still cannot be returned without a stated reason", r.returncode != 0, "a return with no reason was accepted")
r = psql("m15_a", f"""INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, reason)
                     VALUES ('{T1}', '{DEP}', 'refunded', 80, DATE '2026-03-01', 'legacy interest 3.10 paid by cheque 2026-03-01')""", check=False, role="tally_app", user=U1)
report("P1e: … and returns with one", r.returncode == 0, r.stderr.strip()[-200:])
r = psql("m15_a", f"""INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, period_start, period_end, rate_applied, principal_basis, calculated_by)
                     VALUES ('{T1}', '{DEP2}', 'interest_accrued', 0.2, DATE '2026-02-01', DATE '2026-01-01', DATE '2026-01-31', 0.05, 500, 'core-m15')""", check=False, role="tally_app", user=U1)
report("P1f: no interest accrues on a carried deposit here (it cites no law row and no rate row)", r.returncode != 0, "an accrual on a carried deposit was accepted")

snap = "SELECT md5(" + " || ".join(f"coalesce((SELECT string_agg(to_jsonb(x)::text, '|' ORDER BY x.id) FROM public.{t} x), '')" for t in OLD_TABLES + ["deposit_rules"]) + ")"
snap_a = one("m15_a", snap)
r = apply("m15_a")
snap_b = one("m15_a", snap)
report("P2: a second application changes nothing and says so", r.returncode == 0 and "nothing to do" in r.stderr and snap_a == snap_b, r.stderr.strip()[-200:])

# a re-run on a database that has since gained a waiver determination (real data) still finds the tables registered
# and says so; it does not run its precondition over the new data
psql("m15_a", f"""INSERT INTO public.deposit_waiver_determinations (tenant_id, customer_id, waiver_class, determined_on)
                 VALUES ('{T1}', '{C1}', 'good_payment_history', DATE '2026-03-01');""")
r = apply("m15_a")
report("P2b: … and once the database holds real data a re-run still says there is nothing to do", r.returncode == 0 and "nothing to do" in r.stderr, r.stderr.strip()[-200:])

# ---- P3-P5: what the patch will not run over
for tag, label, kwargs, word in [
        ("c", "P3", {"real_deposit": True}, "deposit"),
        ("d", "P4", {"waiver": True}, "waiver determination"),
        ("e", "P5", {"rate": True}, "utility rate row")]:
    clone(f"m15_{tag}")
    plant(f"m15_{tag}", **kwargs)
    r = apply(f"m15_{tag}")
    report(f"{label}a: a {word} stops the patch, saying what it found and that the core must write the backfill",
           r.returncode != 0 and word in r.stderr and "backfill" in r.stderr, r.stderr.strip()[-300:])
    untouched(f"m15_{tag}", f"{label}b: … and the database is exactly as it was")

# ---- P6: the first draft and -06
gone = probe("m15_a", """SELECT to_regprocedure('public.deposit_accrual_amount(numeric,numeric,date,date)') IS NULL
         AND to_regprocedure('public.deposit_interest_rate_as_of(uuid,date)') IS NULL
         AND to_regprocedure('public.deposit_refund_trigger_state(uuid)') IS NULL
         AND to_regclass('public.deposits_refund_due') IS NULL
         AND to_regclass('public.deposit_rule_cap_parts') IS NULL AND to_regclass('public.deposit_rule_waiver_reach') IS NULL""")
report("P6: the -06 Texas law (its functions and the refund-due view) is gone, and the first draft's child tables never appeared", gone == "t", gone)

print(f"{fails} failure(s)")
sys.exit(1 if fails else 0)
