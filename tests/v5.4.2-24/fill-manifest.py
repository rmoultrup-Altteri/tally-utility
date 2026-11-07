#!/usr/bin/env python3
"""Regenerate the exact lists in assert_suspense_pledge_guard_invariants.

c_constraints, c_attrs and c_notnull are PostgreSQL 16's own renderings, so
they are read from a build: the lists are emptied, the patch is applied to a
fresh clone of `tally` (db fm24), the catalog is read, the lists are written
back, and the body md5s are filled (fill-body-md5.py). Run after any change
to a listed constraint, column or function:
    python3 tests/v5.4.2-24/fill-manifest.py
"""
import re, subprocess, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
P = ROOT / "sql/v5.4.2-24-unmatched-cash-and-pledges.sql"
TABLES = ["assistance_agencies", "assistance_agency_agreements", "suspense_receipts", "suspense_receipt_candidates",
          "suspense_receipt_dispositions", "agency_pledges", "agency_pledge_events"]
PAY = ["payments_agency_fkey", "payments_agency_pledge_fkey", "payments_suspense_receipt_fkey", "payments_suspense_resolved_by_fkey",
       "payments_agency_check", "payments_agency_pledge_check", "payments_suspense_resolution_check"]
OTHER = ["tenants_suspense_days_check", "tenant_configuration_history_suspense_days_check"]
DB = "fm24"

def setlist(s: str, name: str, items):
    i = s.index(f"    {name} CONSTANT text[] := ARRAY[")
    j = s.index("];\n", i) + 3
    if items is None:
        body = f"    {name} CONSTANT text[] := ARRAY[]::text[];\n"
    else:
        def lit(x):
            if "\n" in x or "\\" in x:
                return "E'" + x.replace("\\", "\\\\").replace("'", "''").replace("\n", "\\n") + "'"
            return "'" + x.replace("'", "''") + "'"
        body = f"    {name} CONSTANT text[] := ARRAY[\n        " + ",\n        ".join(lit(x) for x in items) + "];\n"
    return s[:i] + body + s[j:]

def psql(db, sql, sep="<<RS>>"):
    r = subprocess.run(["docker", "exec", "-i", "tally-pg", "psql", "-U", "tally", "-d", db, "-At", "-R", sep, "-v", "ON_ERROR_STOP=1"], input=sql, capture_output=True, text=True)
    if r.returncode:
        sys.exit(r.stderr)
    return [x.strip("\n") for x in r.stdout.split(sep) if x.strip()]

def fill_md5():
    subprocess.run([sys.executable, str(ROOT / "tests/v5.4.2-24/fill-body-md5.py")], check=True)

s = P.read_text()
for n in ("c_constraints", "c_attrs", "c_notnull"):
    s = setlist(s, n, None)
P.write_text(s)
fill_md5()
for q in (f"DROP DATABASE IF EXISTS {DB}", f"CREATE DATABASE {DB} TEMPLATE tally"):
    psql("postgres", q)
psql(DB, f"REVOKE TEMP ON DATABASE {DB} FROM PUBLIC, tally_app, tally_core")
r = subprocess.run(["docker", "exec", "-i", "-e", "PGOPTIONS=-c search_path= -c check_function_bodies=on", "tally-pg", "psql", "-U", "tally", "-d", DB,
                    "-v", "ON_ERROR_STOP=1", "-q", "-o", "/dev/null", "-f", "-"], input=P.read_text(), capture_output=True, text=True)
if r.returncode:
    sys.exit("apply failed: " + r.stderr[-800:])
tl = ",".join(f"'{t}'" for t in TABLES)
cons = psql(DB, f"""select k.conrelid::regclass::text || ' ' || k.conname || ' ' || pg_get_constraintdef(k.oid) from pg_constraint k
 where k.conrelid::regclass::text in ({tl}) or (k.conrelid = 'payments'::regclass and k.conname in ({",".join(f"'{c}'" for c in PAY)}))
    or k.conname in ({",".join(f"'{c}'" for c in OTHER)}) order by 1""")
s = P.read_text()
sigs = re.findall(r"'([a-z_]+\([^']*\)) @[0-9a-f]{32}'", s)
attrs = psql(DB, "select x from (values " + ",".join(f"('{g}')" for g in sigs) + """) v(g)
 cross join lateral (select g || ' | ' || f.provolatile::text || ' | ' || f.prosecdef::text || ' | ' || coalesce(array_to_string(f.proconfig, ';'), '-') as x
   from pg_proc f where f.oid = to_regprocedure('public.' || g)) z order by 1""")
notnull = psql(DB, f"""select c.relname || '.' || a.attname from pg_attribute a join pg_class c on c.oid = a.attrelid
 where c.relnamespace = 'public'::regnamespace and c.relname in ({tl}) and a.attnum > 0 and a.attnotnull and not a.attisdropped order by 1""")
assert len(attrs) == len(sigs), (len(attrs), len(sigs))
s = setlist(s, "c_constraints", cons)
s = setlist(s, "c_attrs", attrs)
s = setlist(s, "c_notnull", notnull)
P.write_text(s)
fill_md5()
psql("postgres", f"DROP DATABASE IF EXISTS {DB}")
print(f"constraints {len(cons)}, attrs {len(attrs)}, notnull {len(notnull)}")
