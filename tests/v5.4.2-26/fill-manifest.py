#!/usr/bin/env python3
"""v5.4.2-26 — fill assert_collections_guard_invariants()'s lists from the catalogue.

Applies the patch, with its lists emptied, to a fresh clone of BASE (default
ci_pre26: -25 applied, -26 not), reads back the catalogue's own text of every
object -26 builds, and writes it into the patch between each list's markers:

    ARRAY[ -- @@TRIGGERS@@ <entries> ]   (likewise CONSTRAINTS, INDEXES, TABLES, FUNCS)

Run after any change to a pinned object, then the battery, mutations and ci.sh.

    python3 tests/v5.4.2-26/fill-manifest.py [BASE]
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATCH = ROOT / "sql/v5.4.2-26-collections-decisions.sql"
BASE = sys.argv[1] if len(sys.argv) > 1 else "ci_pre26"
DB = "fill26"
LISTS = ["TRIGGERS", "CONSTRAINTS", "INDEXES", "TABLES", "FUNCS"]

NEW_TABLES = ["collections_conditions", "collections_decisions", "service_order_field_visits", "service_order_field_approvals"]
TRIGGERS_ON_OLD = ["b_enforce_dunning_event", "z_dunning_move_stage", "a_enforce_dunning_stage_projection",
                   "a_enforce_adhoc_charge_decision", "a_enforce_late_fee_line", "a_enforce_disconnect_order",
                   "a_enforce_do_not_disconnect_projection", "enrollment_recompute_dnd"]
CONSTRAINTS_ON_OLD = ["dunning_events_invoice_id_fkey", "dunning_events_decision_fkey", "adhoc_charges_decision_fkey",
                      "service_orders_decision_fkey"]
UNIQUE_INDEXES = ["dunning_events_one_per_decision", "adhoc_charges_one_per_decision", "service_orders_one_per_decision",
                  "service_order_field_visits_one_executed", "service_order_field_visits_one_per_decision"]


def psql(db: str, sql: str, *, stdin: str | None = None, opts: str | None = None) -> str:
    cmd = ["docker", "exec", "-i"]
    if opts:
        cmd += ["-e", f"PGOPTIONS={opts}"]
    cmd += ["tally-pg", "psql", "-U", "tally", "-d", db, "-v", "ON_ERROR_STOP=1", "-qAt"]
    if sql:
        cmd += ["-c", sql]
    r = subprocess.run(cmd, input=stdin, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"psql failed on {db}: {r.stderr.strip()}")
    return r.stdout


def emptied(text: str) -> str:
    for name in LISTS:
        text, n = re.subn(r"ARRAY\[\n\s*-- @@%s@@\n.*?\s*\];" % name, "'{}'::text[];", text, flags=re.S)
        assert n == 1, f"list {name} not found once"
    return text


def lit(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def main() -> None:
    text = PATCH.read_text()
    psql("postgres", f"DROP DATABASE IF EXISTS {DB}")
    psql("postgres", f"CREATE DATABASE {DB} TEMPLATE {BASE}")
    psql(DB, f"REVOKE TEMP ON DATABASE {DB} FROM PUBLIC, tally_app, tally_core")
    psql(DB, "", stdin=emptied(text), opts="-c search_path= -c check_function_bodies=on")
    arr = lambda xs: "ARRAY[" + ",".join(lit(x) for x in xs) + "]"
    funcs = re.findall(r"CREATE OR REPLACE FUNCTION public\.(\w+)\(", text)
    funcs = sorted(set(f for f in funcs if f != "assert_collections_guard_invariants"))
    q = {
        "TRIGGERS": f"""SELECT pg_get_triggerdef(t.oid) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
                         WHERE NOT t.tgisinternal AND c.relnamespace = 'public'::regnamespace
                           AND (c.relname = ANY ({arr(NEW_TABLES)}) OR t.tgname = ANY ({arr(TRIGGERS_ON_OLD)}))
                         ORDER BY 1""",
        "CONSTRAINTS": f"""SELECT k.conrelid::regclass::text || ' ' || k.conname || ' ' || pg_get_constraintdef(k.oid)
                            FROM pg_constraint k JOIN pg_class c ON c.oid = k.conrelid
                           WHERE c.relnamespace = 'public'::regnamespace
                             AND (c.relname = ANY ({arr(NEW_TABLES)}) OR k.conname = ANY ({arr(CONSTRAINTS_ON_OLD)}))
                           ORDER BY 1""",
        "INDEXES": f"""SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND indexname = ANY ({arr(UNIQUE_INDEXES)}) ORDER BY 1""",
        "TABLES": f"""SELECT c.relname || ' | ' || coalesce(c.relacl::text, '-') || ' | ' || c.relrowsecurity::text || ' | ' || c.relforcerowsecurity::text
                       FROM pg_class c WHERE c.relnamespace = 'public'::regnamespace AND c.relname = ANY ({arr(NEW_TABLES + ['collections_record_seq'])})
                      ORDER BY 1""",
        "FUNCS": f"""SELECT p.oid::regprocedure::text || ' | ' || p.prosecdef::text || ' | ' || coalesce(array_to_string(p.proconfig, ';'), '-')
                            || ' | ' || coalesce(p.proacl::text, '-') || ' | ' || md5(p.prosrc)
                       FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = ANY ({arr(funcs)})
                      ORDER BY 1""",
    }
    for name in LISTS:
        rows = [r for r in psql(DB, q[name]).split("\n") if r]
        if name == "FUNCS":
            missing = set(funcs) - {r.split("(")[0] for r in rows}
            assert not missing, f"functions not found: {missing}"
        body = ",\n".join("        " + lit(r) for r in rows)
        text, n = re.subn(r"(ARRAY\[\n\s*-- @@%s@@\n).*?\s*\];" % name,
                          lambda m: m.group(1) + body + "\n    ];", text, flags=re.S)
        assert n == 1, name
        print(f"{name}: {len(rows)}")
    PATCH.write_text(text)
    psql("postgres", f"DROP DATABASE {DB}")


if __name__ == "__main__":
    main()
