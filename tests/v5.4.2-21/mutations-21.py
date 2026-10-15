#!/usr/bin/env python3
"""v5.4.2-21 — prove the -21 checks CATCH drift, not merely pass.

Each mutation alters a copy of the patch, applies it (strict: search_path ''
and function-body checking on) to a fresh clone of `tally` with TEMP revoked,
and runs the script that owns the named check:

  battery check (D L K A G V U N)  battery-21.sql
  LR1-LR5                          races/labels-21.sh
  APPLY:<phrase>               the patch itself must refuse (its tail runs the
                               invariants), with that phrase

CAUGHT only when the FIRST FAIL line printed is the named check's (r2,
Codex S4: the race script runs on after a failure, so the first one is the
one that counts). A mutation an EARLIER check catches is reported as missed:
its named check is wrong, or a guard is redundant — fix the name or remove
the duplicate, never loosen the rule.

    python3 tests/v5.4.2-21/mutations-21.py [M07 M12 ...]
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[2]
PATCH = ROOT / "sql/v5.4.2-21-wave1-lineage-arithmetic-retention.sql"
HERE = ROOT / "tests/v5.4.2-21"
DB = "m21"


def rep(old: str, new: str) -> Callable[[str], str]:
    def m(s: str) -> str:
        assert s.count(old) == 1, f"mutation anchor not unique/found ({s.count(old)}): {old[:90]!r}"
        return s.replace(old, new, 1)
    return m


def both(*fs: Callable[[str], str]) -> Callable[[str], str]:
    def m(s: str) -> str:
        for f in fs:
            s = f(s)
        return s
    return m


def tail(sql: str) -> Callable[[str], str]:
    """Append statements just before the patch's own invariant run."""
    return rep("DO $$ BEGIN\n    PERFORM public.assert_no_hard_delete_invariants();",
               sql + "\nDO $$ BEGIN\n    PERFORM public.assert_no_hard_delete_invariants();")


MUTATIONS = [
    # ---- D: retention
    ("M01", "alerts left out of the sixteen", "APPLY:a retention guard is missing",
     rep("                             'read_cycle_meters', 'alerts', 'service_location_acquisitions',\n                             'rate_item_dependencies', 'pga_monitoring_settings'] LOOP\n        EXECUTE format('DROP TRIGGER IF EXISTS no_hard_delete",
         "                             'read_cycle_meters', 'service_location_acquisitions',\n                             'rate_item_dependencies', 'pga_monitoring_settings'] LOOP\n        EXECUTE format('DROP TRIGGER IF EXISTS no_hard_delete")),
    ("M02", "the application keeps DELETE", "APPLY:tally_app may delete or truncate",
     rep("        EXECUTE format('REVOKE DELETE, TRUNCATE ON public.%I FROM tally_app', t);\n", "")),
    ("M03", "no_truncate left origin-only", "APPLY:a retention guard is missing",
     rep("        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER no_truncate', t);\n        EXECUTE format('REVOKE DELETE", "        EXECUTE format('REVOKE DELETE")),
    # ---- L: the labels
    ("M04", "the in-use guard takes no lock", "LR1",
     rep("        EXECUTE format('LOCK TABLE %s IN SHARE MODE', v_table);\n", "")),
    ("M05", "the in-use guard runs at any isolation", "LR3",
     rep("    IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s: a label",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s: a label")),
    ("M06", "a field label counts every tenant's rows", "L1f",
     rep("FROM %s e WHERE e.tenant_id = $1 AND e.metadata ? $2)", "FROM %s e WHERE $1 IS NOT NULL AND e.metadata ? $2)")),
    ("M07", "a location type counts every tenant's rows", "L2c",
     rep("                        WHERE l.tenant_id = OLD.tenant_id AND l.location_type = OLD.type_key)", "                        WHERE l.location_type = OLD.type_key)")),
    ("M08", "the in-use guard refuses nothing", "L1",
     rep("    IF v_in_use THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s: label", "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s: label")),
    ("M09", "the guard looks in a table with no metadata", "L1b",
     rep("        IF v_table IS NULL OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a\n                                           WHERE a.attrelid = v_table AND a.attname = 'metadata' AND NOT a.attisdropped) THEN",
         "        IF v_table IS NULL THEN")),
    ("M10", "the in-use guard left origin-only", "APPLY:a label guard is missing",
     rep("        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER a_enforce_custom_label_unused', t);\n", "")),
    # ---- K: dependencies retired
    ("M11", "a dependency may be born retired", "K2",
     rep("        IF NEW.retired_at IS NOT NULL OR NEW.retired_by IS NOT NULL OR NEW.retired_reason IS NOT NULL THEN", "        IF false THEN")),
    ("M12", "a live dependency is editable", "K3a2",
     rep("           IS DISTINCT FROM (OLD.id, OLD.tenant_id, OLD.rate_schedule_id, OLD.dependent_rate_item_id, OLD.base_rate_item_id, OLD.notes, OLD.created_at) THEN",
         "           IS DISTINCT FROM (OLD.id, OLD.tenant_id, OLD.rate_schedule_id, OLD.dependent_rate_item_id, OLD.base_rate_item_id, NEW.notes, OLD.created_at) THEN")),
    ("M13", "an update need not be a retirement", "K3b",
     rep("        IF NEW.retired_reason IS NULL THEN\n            RAISE EXCEPTION", "        IF false THEN\n            RAISE EXCEPTION")),
    ("M14", "the caller's retired_at is kept", "K3c",
     rep("        NEW.retired_at := now();\n", "        NEW.retired_at := coalesce(NEW.retired_at, now());\n")),
    ("M15", "a retirement skips the mutex", "K5a",
     rep("        -- removes an edge and cannot close a cycle.\n        UPDATE public.rate_schedules s SET updated_at = now() WHERE s.id = NEW.rate_schedule_id;\n", "        -- removes an edge and cannot close a cycle.\n")),
    ("M16", "a retired row's retirement can be rewritten", "K3d2",
     rep("        IF OLD.retired_at IS NOT NULL THEN\n            RAISE EXCEPTION", "        IF false THEN\n            RAISE EXCEPTION")),
    ("M17", "the cycle walk counts retired edges", "K5",
     rep("           AND d.retired_at IS NULL\n", "")),
    ("M18", "uniqueness counts retired rows", "K4",
     rep("    ON public.rate_item_dependencies (rate_schedule_id, dependent_rate_item_id, base_rate_item_id)\n    WHERE retired_at IS NULL;",
         "    ON public.rate_item_dependencies (rate_schedule_id, dependent_rate_item_id, base_rate_item_id);")),
    ("M19", "a blank retirement reason", "K1",
     rep("        CHECK (retired_reason IS NULL OR retired_reason ~ '[[:alnum:]]');", "        CHECK (true);")),
    # ---- A: arithmetic
    ("M20", "a gas usage line need not carry the gas figures", "A2b",
     rep("        IF p_line.service_type = 'gas' THEN\n            IF p_line.gas_meter_factor", "        IF false THEN\n            IF p_line.gas_meter_factor")),
    ("M21", "a blank unit passes", "A2d",
     rep("        IF coalesce(p_line.usage_unit !~ '[[:alnum:]]', true) THEN", "        IF p_line.usage_unit IS NULL THEN")),
    ("M22", "coverage need not be all or none", "A3b",
     rep("NOT IN (0, 5) THEN", "NOT IN (0, 1, 2, 3, 4, 5) THEN")),
    ("M23", "a surcharge need not name its item", "A4a",
     rep("        IF p_line.rate_item_id IS NULL THEN\n            RETURN 'rate_item_id (a surcharge names its rate item)';", "        IF p_line.rate_item_id IS NULL THEN\n            RETURN NULL;")),
    ("M24", "a tiered surcharge is not per unit", "A4d",
     rep("v_per_unit := v_calc IN ('per_unit_usage', 'tiered_usage');", "v_per_unit := v_calc IN ('per_unit_usage');")),
    ("M25", "a held bill's discard is checked as an issuance", "V2c",
     rep("    IF TG_OP = 'UPDATE' AND NEW.status = 'void' THEN\n        RETURN NULL;\n    END IF;\n    -- r2 (Codex B2)",
         "    -- r2 (Codex B2)")),
    ("M25b", "the arithmetic check never fires", "A2a",
     rep("        IF v_gap IS NOT NULL THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('invoice %s cannot be issued: line %s (%s, %s) does not carry",
         "        IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('invoice %s cannot be issued: line %s (%s, %s) does not carry")),
    # ---- G: lineage
    ("M28", "a correction may name nothing", "G1",
     rep("        CHECK (invoice_type <> 'correction' OR replaces_invoice_id IS NOT NULL);", "        CHECK (true);")),
    ("M29", "a void_reversal needs no reason", "G2b",
     rep("               OR (reverses_ledger_entry_id IS NOT NULL AND coalesce(reversal_reason ~ '[[:alnum:]]', false)));", "               OR reverses_ledger_entry_id IS NOT NULL);")),
    ("M30", "the reversal link is not tenant-bound", "G3",
     rep("        FOREIGN KEY (reverses_ledger_entry_id, tenant_id) REFERENCES public.account_ledger (id, tenant_id);", "        FOREIGN KEY (reverses_ledger_entry_id) REFERENCES public.account_ledger (id);")),
    ("M31", "a refund need name no source", "G4a",
     rep("        CHECK (payment_method <> 'refund' OR num_nonnulls(refunds_payment_id, refunds_customer_credit_id) = 1);", "        CHECK (num_nonnulls(refunds_payment_id, refunds_customer_credit_id) <= 1);")),
    ("M32", "a credit link on any payment", "G4d",
     rep("        CHECK ((refunds_payment_id IS NULL AND refunds_customer_credit_id IS NULL)\n               OR (payment_method = 'refund' AND amount < 0)),", "        CHECK (refunds_payment_id IS NULL OR (payment_method = 'refund' AND amount < 0)),")),
    ("M33", "the credit link is not frozen", "G4g",
     rep("        IF NEW.refunds_customer_credit_id  IS DISTINCT FROM OLD.refunds_customer_credit_id  THEN v_changed := v_changed || ARRAY['refunds_customer_credit_id']; END IF;  -- v5.4.2-21\n", "")),
    ("M34", "a charge may be born with a void's pointer", "G6",
     rep("    IF NEW.voided_from_invoice_id IS NOT NULL\n       AND NOT", "    IF false\n       AND NOT")),
    ("M34b", "no superuser history load", "G6b",
     rep("    IF NEW.voided_from_invoice_id IS NOT NULL\n       AND NOT (SELECT r.rolsuper FROM pg_catalog.pg_roles r WHERE r.rolname = current_user) THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('adhoc_charges: charge",
         "    IF NEW.voided_from_invoice_id IS NOT NULL THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('adhoc_charges: charge")),
    ("M35", "a lineage column unindexed", "G7",
     rep("CREATE INDEX IF NOT EXISTS idx_payments_nsf_original ON public.payments (nsf_original_payment_id) WHERE nsf_original_payment_id IS NOT NULL;\n", "")),
    # ---- V: the void
    ("M36", "a posted bill voids with no charge to name", "V1c",
     rep("        IF NOT FOUND THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('invoice %s was posted but has no charge entry",
         "        IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('invoice %s was posted but has no charge entry")),
    ("M37", "a held bill's void posts a reversal", "V2",
     rep("    IF v_invoice.first_issued_at IS NOT NULL THEN\n        v_reversal_amount", "    IF true THEN\n        v_reversal_amount")),
    # ---- U: identity
    ("M39", "a Cognito binding can change", "U1d",
     rep("    IF OLD.cognito_sub IS NOT NULL AND NEW.cognito_sub IS DISTINCT FROM OLD.cognito_sub", "    IF false AND NEW.cognito_sub IS DISTINCT FROM OLD.cognito_sub")),
    ("M40", "a Cognito identity bound to two users", "U1a",
     rep("    ADD CONSTRAINT users_cognito_sub_key UNIQUE (cognito_sub),\n", "")),
    ("M41", "any text as a subject", "U1b",
     rep("CHECK (cognito_sub ~ '^[0-9A-Za-z_-]{1,128}$')", "CHECK (true)")),
    ("M42", "a deactivated user keeps a tenant", "U2b",
     rep("WHERE id = current_setting('app.user_id', true)::uuid AND is_active\n", "WHERE id = current_setting('app.user_id', true)::uuid\n")),
    ("M42b", "a deactivated administrator stays one", "U2c",
     rep("AND role = 'platform_admin' AND is_active)", "AND role = 'platform_admin')")),
    # ---- r2: the round-1 findings
    ("M45", "an unclassifiable surcharge needs nothing", "A4g",
     rep("        IF v_calc IS NULL THEN\n            RETURN format('a classification", "        IF false THEN\n            RETURN format('a classification")),
    ("M46", "the arithmetic is read at the period end", "A7",
     rep("v_gap := public.invoice_line_arithmetic_gap(v_line, v_snap.valid_at, now());", "v_gap := public.invoice_line_arithmetic_gap(v_line, NEW.period_end, now());")),
    ("M46b", "the arithmetic is read at the snapshot's knowledge instant", "AR1",
     rep("v_gap := public.invoice_line_arithmetic_gap(v_line, v_snap.valid_at, now());", "v_gap := public.invoice_line_arithmetic_gap(v_line, v_snap.valid_at, v_snap.recorded_at);")),
    ("M47", "a gas rider must carry the commodity rate", "A4j",
     rep("IF p_line.charge_type = 'usage_charge' AND p_line.gas_commodity_rate IS NULL THEN", "IF p_line.gas_commodity_rate IS NULL THEN")),
    ("M48", "a label's key can be renamed", "L6a",
     rep("    IF v_moved THEN\n", "    IF false THEN\n")),
    ("M48b", "the key freeze left origin-only", "APPLY:a label guard is missing",
     rep("        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER a_enforce_custom_label_key_frozen', t);\n", "")),
    ("M49", "an operator binds an identity", "U3a",
     rep("    ELSIF NOT public.session_is_supervisor() THEN", "    ELSIF false THEN")),
    ("M49c", "any supervisor binds or switches a platform administrator", "U3h",
     rep("    IF NEW.role = 'platform_admin' OR (TG_OP = 'UPDATE' AND OLD.role = 'platform_admin') THEN", "    IF false THEN")),
    ("M49b", "switching a user on or off is unguarded", "U3c",
     rep(" OR NEW.is_active IS DISTINCT FROM OLD.is_active\n", "\n")),
    ("M50", "the void names another customer's charge", "V1e",
     rep("           AND l.customer_id      = v_invoice.customer_id   -- r2 (Opus S1)\n", "")),
    ("M50b", "the void names another tenant's charge", "V1g",
     rep("         WHERE l.tenant_id        = v_invoice.tenant_id\n           AND l.customer_id", "         WHERE true\n           AND l.customer_id")),
    ("M51", "the void's reversal filed under another name", "G2e",
     rep("        CHECK (coalesce(reference_type = 'invoice_void', false) = (transaction_type = 'void_reversal'));", "        CHECK (true);")),
    ("M52", "an entry reversed twice", "G2g",
     rep("CREATE UNIQUE INDEX account_ledger_one_void_reversal_per_entry", "CREATE INDEX account_ledger_one_void_reversal_per_entry")),
    ("M53", "the label lock waits without limit", "LR6",
     rep("        PERFORM pg_catalog.set_config('lock_timeout', c_lock_wait, true);\n        EXECUTE format('LOCK TABLE", "        EXECUTE format('LOCK TABLE")),
    ("M49d", "a demotion is unguarded", "U3k",
     rep("\n                                      OR (OLD.role IN ('tenant_admin', 'platform_admin') AND NEW.role IS DISTINCT FROM OLD.role)))) THEN",
         "))) THEN")),
    ("M53b", "the location-type lock waits without limit", "LR7",
     rep("        PERFORM pg_catalog.set_config('lock_timeout', c_lock_wait, true);\n        LOCK TABLE public.service_locations", "        LOCK TABLE public.service_locations")),
    ("M60", "the field branch leaves its 5 s lock wait behind", "L7a",
     rep("        EXECUTE format('LOCK TABLE %s IN SHARE MODE', v_table);\n        PERFORM pg_catalog.set_config('lock_timeout', v_saved, true);", "        EXECUTE format('LOCK TABLE %s IN SHARE MODE', v_table);")),
    ("M60b", "the location branch leaves its 5 s lock wait behind", "L7b",
     rep("        LOCK TABLE public.service_locations IN SHARE MODE;\n        PERFORM pg_catalog.set_config('lock_timeout', v_saved, true);", "        LOCK TABLE public.service_locations IN SHARE MODE;")),
    ("M54", "retired_by is the caller's choice", "K3e",
     rep("        NEW.retired_by := NULLIF(pg_catalog.current_setting('app.user_id', true), '')::uuid;\n", "")),
    ("M55", "a refund's credit is not bound to its customer", "G4c",
     rep("        FOREIGN KEY (refunds_customer_credit_id, tenant_id, customer_id) REFERENCES public.customer_credits (id, tenant_id, customer_id);",
         "        FOREIGN KEY (refunds_customer_credit_id) REFERENCES public.customer_credits (id);")),
    ("M56", "the arithmetic check left origin-only", "APPLY:a wave-1 guard is missing",
     rep("ALTER TABLE public.invoices ENABLE ALWAYS TRIGGER enforce_invoice_line_arithmetic;\n", "")),
    ("M57", "the born-unvoided guard left origin-only", "APPLY:a wave-1 guard is missing",
     rep("ALTER TABLE public.adhoc_charges ENABLE ALWAYS TRIGGER a_enforce_adhoc_charge_born_unvoided;\n", "")),
    ("M58", "the supervisor guard left origin-only", "APPLY:a wave-1 guard is missing",
     rep("ALTER TABLE public.users ENABLE ALWAYS TRIGGER a_enforce_user_binding_by_supervisor;\n", "")),
    ("M59", "the labels' no_truncate left origin-only", "APPLY:a label guard is missing",
     rep("        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER no_truncate', t);\n        EXECUTE format('REVOKE TRUNCATE", "        EXECUTE format('REVOKE TRUNCATE")),
    # ---- N: the -20 notes
    ("M43", "the PUBLIC clause says table again", "N2",
     rep("PUBLIC holds a privilege on relation %s (or a column of it)", "PUBLIC holds a table or column privilege on %s")),
    ("M44", "the rendering note is dropped", "N3",
     rep("    -- v5.4.2-21 (-20 note): these strings are PostgreSQL 16's rendering by\n", "")),
]


def sh(cmd: list[str], inp: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, input=inp, capture_output=True, text=True)


def sh_ordered(cmd: list[str], inp: str | None = None) -> subprocess.CompletedProcess:
    """stdout and stderr in one stream, in the order written (r3, Codex S3)."""
    return subprocess.run(cmd, input=inp, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)


def runner(check: str) -> tuple[list[str], str | None]:
    if re.fullmatch(r"(LR|AR)\d", check):
        return [str(HERE / "races/labels-21.sh"), DB], None
    return ["docker", "exec", "-i", "tally-pg", "psql", "-U", "tally", "-d", DB, "-v", "ON_ERROR_STOP=1", "-q", "-o", "/dev/null", "-f", "-"], \
        (HERE / "battery-21.sql").read_text()


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
        cmd, inp = runner(check)
        out = sh_ordered(cmd, inp)
        text = out.stdout
        first = next((l for l in text.splitlines() if "FAIL" in l or "ERROR" in l), "")
        first = re.sub(r"^psql:[^:]+:\d+: ", "", first)[:140]
        # The first line that reports any failure, infrastructure errors included, must be the named check's.
        fails = [re.sub(r"^.*?(FAIL )", r"\1", l) for l in text.splitlines() if re.search(r"\bFAIL\b|ERROR|FATAL|PANIC", l)]  # r3 Codex: any failure word
        if fails and re.match(rf"FAIL {re.escape(check)}[a-z]?[:\s]", fails[0]):
            print(f"{mid} caught at {check}: {what}")
        else:
            print(f"{mid} MISSED ({check}): {what}  [first: {first}]")
            missed += 1
    print(f"{ran - missed}/{ran} caught")
    sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-qc", f"DROP DATABASE IF EXISTS {DB}"])
    return 1 if missed else 0


if __name__ == "__main__":
    sys.exit(main())
