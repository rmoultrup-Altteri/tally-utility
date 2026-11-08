#!/usr/bin/env python3
"""Regenerate the exact lists in assert_dispute_guard_invariants (v5.4.2-25 r2).

The lists are emptied, the patch is applied to a fresh clone of `tally`
(db fm25, TEMP revoked), the catalog is read, and the lists are written back.
Function bodies are hashed from the patch text (prosrc is the text between a
function's dollar quotes), so a mutation runner can re-fill them with
refill(). Run after any change to a listed object:
    python3 tests/v5.4.2-25/fill-manifest.py
"""
import hashlib, re, subprocess, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
P = ROOT / "sql/v5.4.2-25-disputes.sql"
DB = "fm25"
LISTS = ("c_triggers", "c_constraints", "c_indexes", "c_bodies", "c_attrs", "c_notnull", "c_tables", "c_policies", "c_func_acls", "c_col_acls")

def lit(x):
    if "\n" in x or "\\" in x:
        return "E'" + x.replace("\\", "\\\\").replace("'", "''").replace("\n", "\\n") + "'"
    return "'" + x.replace("'", "''") + "'"

def setlist(s, name, items):
    i = s.index(f"    {name} CONSTANT text[] := ARRAY[")
    j = s.index("];\n", i) + 3
    body = (f"    {name} CONSTANT text[] := ARRAY[]::text[];\n" if not items else
            f"    {name} CONSTANT text[] := ARRAY[\n        " + ",\n        ".join(lit(x) for x in items) + "];\n")
    return s[:i] + body + s[j:]

def functions(s):
    names = sorted(set(re.findall(r"CREATE OR REPLACE FUNCTION public\.([a-z_0-9]+)\(", s)) - {"assert_dispute_guard_invariants"})
    return names

def body(s, name):
    m = re.search(r"CREATE OR REPLACE FUNCTION public\." + re.escape(name) + r"\(.*?\bAS (\$[a-z]*\$)(.*?)\1", s, re.S)
    return m.group(2) if m else None

def refill(s):
    """Recompute c_bodies' md5s from the text (for mutation runners)."""
    def f(m):
        sig = m.group(1); b = body(s, sig.split("(")[0])
        return f"'{sig} @{hashlib.md5(b.encode()).hexdigest() if b is not None else '0' * 32}'"
    return re.sub(r"'([a-z_0-9]+\([^']*\)) @([0-9a-f]{32})'", f, s)

def psql(db, sql, sep="<<RS>>"):
    r = subprocess.run(["docker", "exec", "-i", "tally-pg", "psql", "-U", "tally", "-d", db, "-At", "-R", sep, "-v", "ON_ERROR_STOP=1"],
                       input=sql, capture_output=True, text=True)
    if r.returncode:
        sys.exit(r.stderr)
    return [x.strip("\n") for x in r.stdout.split(sep) if x.strip()]

if __name__ == "__main__":
    s = P.read_text()
    for n in LISTS:
        s = setlist(s, n, None)
    P.write_text(s)
    tables = sorted(set(re.findall(r"CREATE TABLE public\.([a-z_0-9]+) \(", s)))
    funcs = functions(s)
    for q in (f"DROP DATABASE IF EXISTS {DB}", f"CREATE DATABASE {DB} TEMPLATE tally"):
        psql("postgres", q)
    psql(DB, f"REVOKE TEMP ON DATABASE {DB} FROM PUBLIC, tally_app, tally_core")
    r = subprocess.run(["docker", "exec", "-i", "-e", "PGOPTIONS=-c search_path= -c check_function_bodies=on", "tally-pg", "psql", "-U", "tally",
                        "-d", DB, "-v", "ON_ERROR_STOP=1", "-q", "-o", "/dev/null", "-f", "-"], input=s, capture_output=True, text=True)
    if r.returncode:
        sys.exit("apply failed: " + r.stderr[-800:])
    tl = ",".join(f"'{t}'" for t in tables)
    fl = ",".join(f"'{f}'" for f in funcs)
    triggers = psql(DB, f"""select pg_get_triggerdef(g.oid) from pg_trigger g join pg_proc f on f.oid = g.tgfoid
      where not g.tgisinternal and (g.tgrelid::regclass::text in ({tl}) or f.proname in ({fl})) order by 1""")
    cons = psql(DB, f"""select k.conrelid::regclass::text || ' ' || k.conname || ' ' || pg_get_constraintdef(k.oid) from pg_constraint k
      where k.conrelid::regclass::text in ({tl}) order by 1""")
    idx = psql(DB, f"""select indexdef from pg_indexes where schemaname = 'public' and tablename in ({tl}) and indexdef like 'CREATE UNIQUE%' order by 1""")
    sigs = psql(DB, f"""select p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' from pg_proc p
      where p.pronamespace = 'public'::regnamespace and p.proname in ({fl}) order by 1""")
    sigs = [re.sub(r"\b[a-z_0-9]+ (uuid|text|date|numeric|jsonb|boolean|integer|bigint|timestamp with time zone|text\[\]|uuid\[\])", r"\1", x).replace(", ", ",") for x in sigs]
    attrs = psql(DB, "select x from (values " + ",".join(f"('{g}')" for g in sigs) + """) v(g)
      cross join lateral (select g || ' | ' || f.provolatile::text || ' | ' || f.prosecdef::text || ' | ' || pg_get_userbyid(f.proowner) || ' | '
        || coalesce(array_to_string(f.proconfig, ';'), '-') as x from pg_proc f where f.oid = to_regprocedure('public.' || g)) z order by 1""")
    acls = psql(DB, "select x from (values " + ",".join(f"('{g}')" for g in sigs) + """) v(g)
      cross join lateral (select g || ' | ' || coalesce(f.proacl::text, '-') as x from pg_proc f where f.oid = to_regprocedure('public.' || g)) z order by 1""")
    assert len(attrs) == len(sigs) == len(acls), (len(attrs), len(sigs), len(acls))
    notnull = psql(DB, f"""select c.relname || '.' || a.attname from pg_attribute a join pg_class c on c.oid = a.attrelid
      where c.relnamespace = 'public'::regnamespace and c.relname in ({tl}) and a.attnum > 0 and a.attnotnull and not a.attisdropped order by 1""")
    tabs = psql(DB, f"""select c.relname || ' | ' || coalesce(c.relacl::text, '-') || ' | ' || c.relrowsecurity::text || ' | ' || c.relforcerowsecurity::text
      from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname in ({tl}) order by 1""")
    pols = psql(DB, f"""select p.tablename || ' | ' || p.policyname || ' | ' || p.cmd || ' | ' || p.permissive || ' | ' || p.roles::text || ' | '
      || coalesce(p.qual, '-') || ' | ' || coalesce(p.with_check, '-') from pg_policies p where p.schemaname = 'public' and p.tablename in ({tl}) order by 1""")
    colacls = psql(DB, f"""select c.relname || '.' || a.attname || ' | ' || a.attacl::text from pg_attribute a join pg_class c on c.oid = a.attrelid
      where c.relnamespace = 'public'::regnamespace and c.relname in ({tl}) and a.attnum > 0 and not a.attisdropped and a.attacl is not null order by 1""")
    s = P.read_text()
    for n, items in (("c_col_acls", colacls), ("c_triggers", triggers), ("c_constraints", cons), ("c_indexes", idx), ("c_attrs", attrs), ("c_notnull", notnull),
                     ("c_tables", tabs), ("c_policies", pols), ("c_func_acls", acls),
                     ("c_bodies", [f"{g} @{'0' * 32}" for g in sigs])):
        s = setlist(s, n, items)
    s = refill(s)
    P.write_text(s)
    psql("postgres", f"DROP DATABASE IF EXISTS {DB}")
    print(f"tables {len(tables)}, triggers {len(triggers)}, constraints {len(cons)}, indexes {len(idx)}, functions {len(sigs)}, notnull {len(notnull)}, policies {len(pols)}")
