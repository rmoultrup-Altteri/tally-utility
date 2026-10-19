#!/usr/bin/env python3
"""v5.4.2-26 — the migration itself, on clones of a base that has -25 (default `ci_base`, as tests/ci.sh builds it):

  P0  the patch applies strictly to the base as it is (search_path empty, function bodies checked)
  P1  a second application succeeds, changes nothing, and says "nothing to do"
  P2  a dunning event stops the patch, naming it (its stage and decision would have to be invented); the database is
      untouched (no decision table appears)
  P3  a bill past dunning stage 'current' stops it likewise (the database moves the stage from now on)
  P4  a bill with a late fee recorded on it (late_fee_assessed / late_fee_amount, both dropped) stops it likewise
  P5  a late-fee charge stops it likewise (it cites no decision)
  P6  a disconnect order stops it likewise (it cites no decision)
  P7  a customer whose do_not_disconnect disagrees with their enrollments stops it likewise

P2-P7 are the standing precondition (Ryan, 2026-09-28: nothing is live); the patch never reinterprets history.

PATCH26=<path> python3 ... runs a different patch text (the mutation runner does).

    python3 tests/v5.4.2-26/migration-26.py [base-db]
"""
from __future__ import annotations

import atexit
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATCH = Path(os.environ.get("PATCH26") or ROOT / "sql/v5.4.2-26-collections-decisions.sql")
BASE = sys.argv[1] if len(sys.argv) > 1 else "ci_base"
STRICT = "-c search_path= -c check_function_bodies=on"
RUN = str(os.getpid())
fails = 0

T = "00000000-0000-4000-8000-0000000026a9"
C = "00000000-0000-4000-8000-0000000026c9"
LOC = "00000000-0000-4000-8000-0000000026d9"
INV = "00000000-0000-4000-8000-000000002699"
EV = "00000000-0000-4000-8000-00000000269a"
CHG = "00000000-0000-4000-8000-00000000269b"
SO = "00000000-0000-4000-8000-00000000269c"


def sh(cmd: list[str], inp: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, input=inp, capture_output=True, text=True)


def nm(name: str) -> str:
    return f"{name}_{RUN}"


def _cleanup() -> None:
    names = sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-Atc",
                f"SELECT datname FROM pg_database WHERE datname ~ '^m26_[a-z0-9]+_{RUN}$'"]).stdout.split()
    for n in names:
        sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-qc", f"DROP DATABASE IF EXISTS {n}"])


atexit.register(_cleanup)


def psql(db: str, sql: str, check: bool = True) -> subprocess.CompletedProcess:
    r = sh(["docker", "exec", "-i", "tally-pg", "psql", "-U", "tally", "-d", db, "-v", "ON_ERROR_STOP=1", "-q", "-At", "-f", "-"], sql)
    if check and r.returncode != 0:
        raise RuntimeError(r.stderr.strip())
    return r


def one(db: str, sql: str) -> str:
    return psql(db, sql).stdout.strip()


def clone(name: str) -> str:
    db = nm(name)
    for stmt in (f"DROP DATABASE IF EXISTS {db}", f"CREATE DATABASE {db} TEMPLATE {BASE}"):
        r = sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-qc", stmt])
        if r.returncode != 0:
            raise RuntimeError(r.stderr.strip())
    # CREATE DATABASE … TEMPLATE does not copy the database ACL (memory: template clone drops ACL).
    for role in ("PUBLIC", "tally_app", "tally_core"):
        psql(db, f"REVOKE TEMP ON DATABASE {db} FROM {role};")
    return db


def apply(db: str) -> subprocess.CompletedProcess:
    sh(["docker", "cp", str(PATCH), "tally-pg:/tmp/patch26.sql"])
    return sh(["docker", "exec", "-e", f"PGOPTIONS={STRICT}", "tally-pg", "psql", "-U", "tally", "-d", db,
               "-v", "ON_ERROR_STOP=1", "-q", "-f", "/tmp/patch26.sql"])


def ok(label: str, cond: bool, detail: str = "") -> None:
    global fails
    if cond:
        print(f"PASS {label}")
    else:
        fails += 1
        print(f"FAIL {label}{': ' + detail if detail else ''}")


FIXTURE = f"""
INSERT INTO public.tenants (id, name, slug) VALUES ('{T}', 'M26', 'm26');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES ('{C}', '{T}', 'M26-C', 'residential');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip)
VALUES ('{LOC}', '{T}', '{C}', 'L', '1 Main', 'Austin', 'TX', '78701');
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date)
VALUES ('{INV}', '{T}', 'M26-I', '{C}', '{LOC}', DATE '2026-03-01', '2026-02', DATE '2026-02-01', DATE '2026-02-28', DATE '2026-03-20');
"""


def stops_naming(name: str, label: str, plant: str, needle: str) -> None:
    db = clone(name)
    psql(db, "BEGIN;\n" + FIXTURE + plant + "\nCOMMIT;")
    r = apply(db)
    ok(f"{label}: the patch stops", r.returncode != 0, r.stdout[-300:])
    ok(f"{label}: … naming the row", needle in r.stderr, r.stderr.strip()[-300:])
    ok(f"{label}: … and the database is untouched", one(db, "SELECT to_regclass('public.collections_decisions') IS NULL") == "t")


def main() -> int:
    if not PATCH.exists():
        ok("P0 the patch file exists", False, f"{PATCH.relative_to(ROOT)} (expected until the patch is written)")
        return 1
    db = clone("m26_p0")
    r = apply(db)
    ok("P0 the patch applies strictly to the base", r.returncode == 0, r.stderr.strip()[-400:])
    if r.returncode != 0:
        return 1
    count = ("SELECT (SELECT count(*) FROM public.collections_conditions) || '/' || (SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal) || '/' || "
             "(SELECT count(*) FROM pg_constraint) || '/' || (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public')")
    before = one(db, count)
    r = apply(db)
    ok("P1 a second application succeeds", r.returncode == 0, r.stderr.strip()[-400:])
    ok("P1b … and says nothing to do", "nothing to do" in (r.stdout + r.stderr), (r.stdout + r.stderr).strip()[-300:])
    after = one(db, count)
    ok("P1c … and changes nothing (conditions, triggers, constraints, columns)", before == after, f"{before} -> {after}")

    stops_naming("m26_p2", "P2 a dunning event",
                 f"INSERT INTO public.dunning_events (id, tenant_id, invoice_id, customer_id, event_type) VALUES ('{EV}', '{T}', '{INV}', '{C}', 'reminder_sent');", EV)
    stops_naming("m26_p3", "P3 a bill past stage current",
                 f"UPDATE public.invoices SET dunning_stage = 'reminder_sent' WHERE id = '{INV}';", INV)
    stops_naming("m26_p4", "P4 a bill with a late fee recorded on it",
                 f"UPDATE public.invoices SET late_fee_assessed = true, late_fee_amount = 5 WHERE id = '{INV}';", INV)
    stops_naming("m26_p5", "P5 a late-fee charge",
                 f"INSERT INTO public.adhoc_charges (id, tenant_id, charge_number, customer_id, charge_type, description, amount, regulatory_class) "
                 f"VALUES ('{CHG}', '{T}', 'M26-CH', '{C}', 'late_fee', 'late fee', 5, 'regulated');", CHG)
    stops_naming("m26_p6", "P6 a disconnect order",
                 f"INSERT INTO public.service_orders (id, tenant_id, order_number, order_type, description, customer_id, location_id) "
                 f"VALUES ('{SO}', '{T}', 'M26-SO', 'disconnect', 'x', '{C}', '{LOC}');", SO)
    stops_naming("m26_p7", "P7 a customer protected with no protective enrollment",
                 f"UPDATE public.customers SET do_not_disconnect = true WHERE id = '{C}';", C)
    print(f"{fails} failure(s)")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
