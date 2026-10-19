#!/usr/bin/env python3
"""v5.4.2-25 — the migration itself, on clones of a base that has -23 (default `ci_base`, as tests/ci.sh builds it):

  P0  the patch applies strictly to the base as it is (search_path empty, function bodies checked)
  P1  a second application succeeds, changes nothing, and says "nothing to do"
  P2  a reading that carries the old dispute notes (meter_readings.dispute_*) stops the patch, naming it; the
      database is untouched (no dispute table appears)
  P3  a reading in status 'disputed' stops it likewise (after -25 a disputed reading needs an open disputes row,
      which the patch will not invent)
  P4  a pending_dispute enrollment stops it likewise (-25 makes the type non-protective; an enrollment in it would
      silently lose its protection)

P2-P4 are the standing precondition (Ryan, 2026-09-28: nothing is live); the patch never converts old dispute state.

PATCH25=<path> python3 ... runs a different patch text (the mutation runner does).

    python3 tests/v5.4.2-25/migration-25.py [base-db]
"""
from __future__ import annotations

import atexit
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATCH = Path(os.environ.get("PATCH25") or ROOT / "sql/v5.4.2-25-disputes.sql")
BASE = sys.argv[1] if len(sys.argv) > 1 else "ci_base"
STRICT = "-c search_path= -c check_function_bodies=on"
RUN = str(os.getpid())
fails = 0

T = "00000000-0000-4000-8000-0000000025a9"
C = "00000000-0000-4000-8000-0000000025c9"
LOC = "00000000-0000-4000-8000-0000000025d9"
MTR = "00000000-0000-4000-8000-0000000025e9"
RD = "00000000-0000-4000-8000-000000002579"
ENR = "00000000-0000-4000-8000-00000000257a"


def sh(cmd: list[str], inp: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, input=inp, capture_output=True, text=True)


def nm(name: str) -> str:
    return f"{name}_{RUN}"


def _cleanup() -> None:
    names = sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-Atc",
                f"SELECT datname FROM pg_database WHERE datname ~ '^m25_[a-z0-9]+_{RUN}$'"]).stdout.split()
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
    sh(["docker", "cp", str(PATCH), "tally-pg:/tmp/patch25.sql"])
    return sh(["docker", "exec", "-e", f"PGOPTIONS={STRICT}", "tally-pg", "psql", "-U", "tally", "-d", db,
               "-v", "ON_ERROR_STOP=1", "-q", "-f", "/tmp/patch25.sql"])


def ok(label: str, cond: bool, detail: str = "") -> None:
    global fails
    if cond:
        print(f"PASS {label}")
    else:
        fails += 1
        print(f"FAIL {label}{': ' + detail if detail else ''}")


FIXTURE = f"""
INSERT INTO public.tenants (id, name, slug) VALUES ('{T}', 'M25', 'm25');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES ('{C}', '{T}', 'M25-C', 'residential');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip)
VALUES ('{LOC}', '{T}', '{C}', 'L', '1 Main', 'Austin', 'TX', '78701');
INSERT INTO public.meters (id, tenant_id, meter_number, location_id, service_type) VALUES ('{MTR}', '{T}', 'M25-M', '{LOC}', 'gas');
INSERT INTO public.meter_readings (id, tenant_id, meter_id, reading_date, reading_value) VALUES ('{RD}', '{T}', '{MTR}', DATE '2026-02-28', 50);
"""


def stops_naming(name: str, label: str, plant: str, needle: str) -> None:
    db = clone(name)
    psql(db, "BEGIN;\n" + FIXTURE + plant + "\nCOMMIT;")
    r = apply(db)
    ok(f"{label}: the patch stops", r.returncode != 0, r.stdout[-300:])
    ok(f"{label}: … naming the row", needle in r.stderr, r.stderr.strip()[-300:])
    ok(f"{label}: … and the database is untouched", one(db, "SELECT to_regclass('public.disputes') IS NULL") == "t")


def main() -> int:
    if not PATCH.exists():
        ok("P0 the patch file exists", False, f"{PATCH.relative_to(ROOT)} (expected until the patch is written)")
        return 1
    db = clone("m25_p0")
    r = apply(db)
    ok("P0 the patch applies strictly to the base", r.returncode == 0, r.stderr.strip()[-400:])
    if r.returncode != 0:
        return 1
    before = one(db, "SELECT (SELECT count(*) FROM public.dispute_rules) || '/' || (SELECT count(*) FROM public.rule_term_schemas) || '/' || "
                     "(SELECT count(*) FROM public.rule_tables) || '/' || (SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal)")
    r = apply(db)
    ok("P1 a second application succeeds", r.returncode == 0, r.stderr.strip()[-400:])
    ok("P1b … and says nothing to do", "nothing to do" in (r.stdout + r.stderr), (r.stdout + r.stderr).strip()[-300:])
    after = one(db, "SELECT (SELECT count(*) FROM public.dispute_rules) || '/' || (SELECT count(*) FROM public.rule_term_schemas) || '/' || "
                    "(SELECT count(*) FROM public.rule_tables) || '/' || (SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal)")
    ok("P1c … and changes nothing (law rows, kinds, registered tables, triggers)", before == after, f"{before} -> {after}")

    stops_naming("m25_p2", "P2 a reading with the old dispute notes",
                 f"UPDATE public.meter_readings SET dispute_reason = 'customer says misread', dispute_raised_at = now() WHERE id = '{RD}';", RD)
    stops_naming("m25_p3", "P3 a reading in status disputed",
                 f"UPDATE public.meter_readings SET status = 'disputed' WHERE id = '{RD}';", RD)
    stops_naming("m25_p4", "P4 a pending_dispute enrollment",
                 f"INSERT INTO public.customer_program_enrollments (id, tenant_id, customer_id, program_type, effective_start_date, status) "
                 f"VALUES ('{ENR}', '{T}', '{C}', 'pending_dispute', DATE '2026-03-01', 'active');", ENR)
    print(f"{fails} failure(s)")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
