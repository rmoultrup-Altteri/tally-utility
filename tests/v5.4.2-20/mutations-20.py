#!/usr/bin/env python3
"""v5.4.2-20 — prove the -20 checks CATCH drift, not merely pass.

Each mutation alters a copy of the patch, applies it (strict: search_path ''
and function-body checking on) to a fresh clone of `tally` with TEMP revoked,
and runs the script that owns the named check:

  battery check (G S V)        battery-20.sql
  RC1-RC5, T1-T4               races/seal-20.sh
  APPLY:<phrase>               the patch itself must refuse (its tail runs the
                               invariants), with that phrase

CAUGHT only when the FIRST FAIL line printed is the named check's (r2,
Codex S4: the race script runs on after a failure, so the first one is the
one that counts). A mutation an EARLIER check catches is reported as missed:
its named check is wrong, or a guard is redundant — fix the name or remove
the duplicate, never loosen the rule.

    python3 tests/v5.4.2-20/mutations-20.py [M07 M12 ...]
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[2]
PATCH = ROOT / "sql/v5.4.2-20-seal-version-check-and-void.sql"
HERE = ROOT / "tests/v5.4.2-20"
DB = "m20"


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
    return rep("DO $$ BEGIN\n    PERFORM public.assert_seal_role_invariants();",
               sql + "\nDO $$ BEGIN\n    PERFORM public.assert_seal_role_invariants();")


MUTATIONS = [
    # ---- the version check and its receipt
    ("M01", "the check writes no receipt", "S5",
     rep("    INSERT INTO public.reference_version_receipts (header_table, entity_id, version, tenant_id)\n    VALUES (p_table, p_id, v_new, v_tenant);\n", "")),
    ("M02", "the receipt is stamped a second early", "S5",
     rep("    NEW.at := pg_catalog.now();", "    NEW.at := pg_catalog.now() - interval '1 second';")),
    ("M03", "the receipt test ignores the start time", "S13a",
     rep("                      AND r.at = pg_catalog.now());", "                      );")),
    ("M04", "the receipt test ignores the transaction", "S13b",
     rep("                    WHERE r.xact = v_xact\n                      AND r.header_table", "                    WHERE true\n                      AND r.header_table")),
    ("M05", "the receipt test ignores the version", "S13c",
     rep("                      AND r.version = v_version\n", "")),
    ("M06", "the receipt test ignores the entity", "S13d",
     rep("                      AND r.entity_id = p_id\n", "")),
    ("M07", "the version guard admits everything", "S2",
     rep("    IF NOT public.reference_version_receipt_held(TG_ARGV[0], v_id) THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s: a version of",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s: a version of")),
    ("M08", "the zone versions carry no guard", "APPLY:a seal guard is missing, changed, or not ENABLE ALWAYS",
     both(rep("CREATE TRIGGER a0_enforce_reference_version_receipt BEFORE INSERT OR UPDATE ON public.wna_zone_versions\n    FOR EACH ROW EXECUTE FUNCTION public.enforce_reference_version_receipt('wna_zones', 'wna_zone_id');\n", ""),
          rep("ALTER TABLE public.wna_zone_versions ENABLE ALWAYS TRIGGER a0_enforce_reference_version_receipt;\n", ""))),
    ("M09", "the guard fires on INSERT only (a close needs no check)", "APPLY:a seal guard is missing, changed, or not ENABLE ALWAYS",
     rep("CREATE TRIGGER a0_enforce_reference_version_receipt BEFORE INSERT OR UPDATE ON public.rate_schedule_versions\n",
         "CREATE TRIGGER a0_enforce_reference_version_receipt BEFORE INSERT ON public.rate_schedule_versions\n")),
    ("M09b", "the version guard admits a close (the shape check aside)", "T5",
     rep("    IF NOT public.reference_version_receipt_held(TG_ARGV[0], v_id) THEN\n", "    IF TG_OP = 'INSERT' AND NOT public.reference_version_receipt_held(TG_ARGV[0], v_id) THEN\n")),
    ("M10", "tally_app keeps table-level UPDATE on the headers", "APPLY:writable outside assert_reference_version",
     rep("REVOKE UPDATE ON public.rate_schedules, public.rate_items, public.wna_zones FROM tally_app;\n", "")),
    ("M11", "the version column is granted back", "APPLY:writable outside assert_reference_version",
     rep("GRANT UPDATE (status, updated_at) ON public.rate_items, public.wna_zones TO tally_app;",
         "GRANT UPDATE (status, updated_at, version) ON public.rate_items, public.wna_zones TO tally_app;")),
    ("M12", "an entity the caller cannot see is a stale token", "S4",
     rep("    IF v_tenant IS NULL THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s %s not found (CI-011)'",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s %s not found (CI-011)'")),
    ("M13", "the check is not a definer", "APPLY:not one of its pinned SECURITY DEFINER",
     rep("CREATE OR REPLACE FUNCTION public.assert_reference_version(p_table text, p_id uuid, p_expected_version integer) RETURNS integer\n    LANGUAGE plpgsql\n    SECURITY DEFINER",
         "CREATE OR REPLACE FUNCTION public.assert_reference_version(p_table text, p_id uuid, p_expected_version integer) RETURNS integer\n    LANGUAGE plpgsql")),
    ("M14", "the core keeps EXECUTE on the check", "APPLY:tally_core can execute SECURITY DEFINER",
     rep("REVOKE ALL ON FUNCTION public.assert_reference_version(text, uuid, integer) FROM PUBLIC, tally_app, tally_core;",
         "REVOKE ALL ON FUNCTION public.assert_reference_version(text, uuid, integer) FROM PUBLIC, tally_app;")),
    ("M15", "the receipts keep the default grant to tally_app", "APPLY:reachable by tally_app",
     rep("REVOKE ALL ON public.reference_version_receipts FROM PUBLIC, tally_app, tally_core;\n", "")),
    ("M16", "a receipt may be edited", "S10e",
     rep("    IF TG_OP <> 'INSERT' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = 'reference_version_receipts is append-only",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = 'reference_version_receipts is append-only")),
    ("M17", "a lifecycle move needs no check", "S3a",
     rep("       AND NOT public.reference_version_receipt_held(TG_TABLE_NAME, (v_new ->> 'id')::uuid) THEN",
         "       AND false THEN")),
    ("M18", "an updated_at touch counts as a lifecycle move", "S3b",
     rep("    IF (v_old - 'version' - 'updated_at') IS DISTINCT FROM (v_new - 'version' - 'updated_at')",
         "    IF (v_old - 'version') IS DISTINCT FROM (v_new - 'version')")),
    ("M19", "a header may be born at any version", "S12a",
     rep("    IF NEW.version IS DISTINCT FROM 1 THEN", "    IF false THEN")),
    ("M20", "the receipt test is executable by PUBLIC (and so by the core)", "APPLY:tally_core can execute SECURITY DEFINER",
     tail("GRANT EXECUTE ON FUNCTION public.reference_version_receipt_held(text, uuid) TO PUBLIC;")),
    ("M21", "the check's role may log in", "APPLY:is NOLOGIN",
     tail("ALTER ROLE tally_seal LOGIN;")),
    # ---- the void
    ("M22", "the read guard admits any caller's release", "V2a",
     rep("    v_is_void_operation := current_user = 'tally_void';", "    v_is_void_operation := true;")),
    ("M23", "a read naming no bill may be released", "V8",
     rep("                         AND NEW.validation_status = 'void_released'\n                         AND OLD.locked_by_invoice_id IS NOT NULL;",
         "                         AND NEW.validation_status = 'void_released';")),
    ("M24", "the charge guard admits any caller's disposition", "V2b",
     rep("    v_void_op boolean := current_user = 'tally_void';", "    v_void_op boolean := true;")),
    ("M25", "the void's disposition is not checked exactly", "V9a",
     rep("    IF v_void_disposition\n       AND NOT (OLD.billed_on_invoice_id IS NOT NULL", "    IF false\n       AND NOT (OLD.billed_on_invoice_id IS NOT NULL")),
    ("M26", "voided_from_invoice_id may be written outside a void", "V3b",
     rep("    IF NEW.voided_from_invoice_id IS DISTINCT FROM OLD.voided_from_invoice_id AND NOT v_void_disposition THEN",
         "    IF false THEN")),
    ("M27", "any caller may write void", "V2c",
     rep("       AND NOT (TG_OP = 'UPDATE' AND current_user = 'tally_void')\n", "       AND NOT (TG_OP = 'UPDATE')\n")),
    ("M28", "any caller may insert a bill born void", "V2d",
     rep("       AND NOT (TG_OP = 'INSERT' AND (SELECT r.rolsuper FROM pg_catalog.pg_roles r WHERE r.rolname = current_user)) THEN",
         "       AND NOT (TG_OP = 'INSERT') THEN")),
    ("M29", "the attach guard admits a void bill", "V4a",
     rep("    IF v_status = 'void' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s: %s names a void invoice",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s: %s names a void invoice")),
    ("M30", "the attach guard takes no lock", "RC3",
     rep("    SELECT i.status, i.tenant_id INTO v_status, v_tenant FROM public.invoices i WHERE i.id = v_invoice FOR SHARE;",
         "    SELECT i.status, i.tenant_id INTO v_status, v_tenant FROM public.invoices i WHERE i.id = v_invoice;")),
    ("M31", "the attach guard does not fire on a charge inserted billed", "APPLY:a seal guard is missing, changed, or not ENABLE ALWAYS",
     rep("CREATE TRIGGER a_enforce_attach_to_live_invoice BEFORE INSERT OR UPDATE OF billed_on_invoice_id ON public.adhoc_charges\n",
         "CREATE TRIGGER a_enforce_attach_to_live_invoice BEFORE UPDATE OF billed_on_invoice_id ON public.adhoc_charges\n")),
    ("M31b", "the attach guard skips an INSERT (the shape check aside)", "V4d",
     rep("    IF v_invoice IS NULL\n       OR (TG_OP = 'UPDATE'", "    IF v_invoice IS NULL OR TG_OP = 'INSERT'\n       OR (TG_OP = 'UPDATE'")),
    ("M32", "the void does not lock the bill (an attach it waited for is stranded)", "RC4",
     rep("    WHERE id = p_invoice_id\n    FOR UPDATE;", "    WHERE id = p_invoice_id;")),
    ("M33", "the void stays the superuser's", "APPLY:no longer owns",
     rep("ALTER FUNCTION public.void_invoice(uuid, uuid, text, text, boolean) OWNER TO tally_void;\n", "")),
    ("M34", "the void's role bypasses RLS", "APPLY:holds no SUPERUSER, BYPASSRLS",
     tail("ALTER ROLE tally_void BYPASSRLS;")),
    ("M35", "the application can become the void's role", "APPLY:has members",
     tail("GRANT tally_void TO tally_app;")),
    ("M36", "a guard reads the old caller-settable setting again", "APPLY:reads the caller-settable void setting",
     rep("    v_is_void_operation := current_user = 'tally_void';",
         "    v_is_void_operation := current_user = 'tally_void' OR coalesce(current_setting('app.void_operation', true) = 'true', false);")),
    ("M37", "the void's role cannot write the ledger", "V1",
     both(rep("GRANT INSERT ON public.account_ledger, public.invoice_events TO tally_void;",
              "GRANT INSERT ON public.invoice_events TO tally_void;"),
          rep('"table public.account_ledger INSERT", ', ""))),
    ("M38", "the void's role cannot release reads", "V1",
     both(rep("GRANT UPDATE (voided_from_invoice_id, locked_by_invoice_id, validation_status) ON public.meter_readings TO tally_void;\n", ""),
          rep('"column public.meter_readings.locked_by_invoice_id UPDATE", "column public.meter_readings.validation_status UPDATE", "column public.meter_readings.voided_from_invoice_id UPDATE", ', ""))),
    # ---- r2
    ("M39", "the attach guard admits a bill the caller cannot see", "V4e",
     rep("    IF NOT FOUND OR v_tenant IS DISTINCT FROM NEW.tenant_id THEN", "    IF FOUND AND v_tenant IS DISTINCT FROM NEW.tenant_id THEN")),
    ("M40", "the attach guard admits another tenant's bill", "V4f",
     rep("    IF NOT FOUND OR v_tenant IS DISTINCT FROM NEW.tenant_id THEN", "    IF NOT FOUND THEN")),
    ("M41", "a pending charge may carry a bill pointer (the CHECK is never made)", "APPLY:adhoc_charges_billed_names_its_bill is missing",
     rep("ALTER TABLE public.adhoc_charges ADD CONSTRAINT adhoc_charges_billed_names_its_bill\n    CHECK ((status = 'billed') = (billed_on_invoice_id IS NOT NULL));\n", "")),
    ("M42", "the void runs at any isolation level", "T7",
     rep("    IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN", "    IF false THEN")),
    ("M43", "the attach guard on charges is origin-only", "APPLY:a seal guard is missing, changed, or not ENABLE ALWAYS",
     rep("ALTER TABLE public.adhoc_charges ENABLE ALWAYS TRIGGER a_enforce_attach_to_live_invoice;\n", "")),
    ("M44", "the void's role may write users", "APPLY:holds other privileges than it is granted",
     tail("GRANT UPDATE (display_name) ON public.users TO tally_void;")),
    ("M45", "the check's role may void", "APPLY:holds other privileges than it is granted",
     tail("GRANT EXECUTE ON FUNCTION public.void_invoice(uuid, uuid, text, text, boolean) TO tally_seal;")),
    ("M46", "the application holds a column grant on the receipts", "APPLY:reachable by tally_app",
     tail("GRANT INSERT (header_table) ON public.reference_version_receipts TO tally_app;")),
    ("M47", "a definer named like an RLS helper, elsewhere, is the core's", "APPLY:tally_core can execute SECURITY DEFINER",
     tail("CREATE SCHEMA m47; CREATE FUNCTION m47.is_platform_admin() RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = '' AS 'SELECT true'; GRANT USAGE ON SCHEMA m47 TO tally_core; GRANT EXECUTE ON FUNCTION m47.is_platform_admin() TO tally_core;")),
    # ---- r3
    ("M50", "a version table's bitemporal guard is disabled", "APPLY:a seal guard is missing, changed, or not ENABLE ALWAYS",
     tail("ALTER TABLE public.wna_zone_versions DISABLE TRIGGER a_enforce_bitemporal_assertion;")),
    ("M51", "the void's role may pass its grant on", "APPLY:holds other privileges than it is granted",
     tail("GRANT SELECT ON public.invoices TO tally_void WITH GRANT OPTION;")),
    ("M52", "PUBLIC holds a column privilege every role inherits", "APPLY:PUBLIC holds a table or column privilege",
     tail("GRANT UPDATE (display_name) ON public.users TO PUBLIC;")),
    ("M48", "the check's role owns an overload of its function", "APPLY:which is not one of its pinned SECURITY DEFINER",
     tail("CREATE FUNCTION public.assert_reference_version(p_table text, p_id uuid) RETURNS integer LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS 'SELECT 1'; ALTER FUNCTION public.assert_reference_version(text, uuid) OWNER TO tally_seal; REVOKE ALL ON FUNCTION public.assert_reference_version(text, uuid) FROM PUBLIC, tally_app;")),
]


def sh(cmd: list[str], inp: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, input=inp, capture_output=True, text=True)


def sh_ordered(cmd: list[str], inp: str | None = None) -> subprocess.CompletedProcess:
    """stdout and stderr in one stream, in the order written (r3, Codex S3)."""
    return subprocess.run(cmd, input=inp, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)


def runner(check: str) -> tuple[list[str], str | None]:
    if re.fullmatch(r"(RC\d|T\d)", check):
        return [str(HERE / "races/seal-20.sh"), DB], None
    return ["docker", "exec", "-i", "tally-pg", "psql", "-U", "tally", "-d", DB, "-v", "ON_ERROR_STOP=1", "-q", "-o", "/dev/null", "-f", "-"], \
        (HERE / "battery-20.sql").read_text()


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
        fails = [re.sub(r"^.*?(FAIL )", r"\1", l) for l in text.splitlines() if re.search(r"FAIL [A-Z]+\d|ERROR|SETUP FAIL", l)]
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
