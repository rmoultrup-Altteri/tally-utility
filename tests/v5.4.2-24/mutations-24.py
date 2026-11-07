#!/usr/bin/env python3
"""v5.4.2-24 — prove the -24 checks CATCH drift, not merely pass.

Each mutation alters a copy of the patch, applies it (strict: search_path ''
and function-body checking on) to a fresh clone of `tally` with TEMP revoked,
and runs the script that owns the named check:

  battery check (U C P X A L G S Y D T I)  battery-24.sql
  SU1-SU7                                  races/suspense-24.sh
  APPLY:<phrase>                           the patch itself must refuse (its
                                           tail runs the invariants), with that
                                           phrase

CAUGHT only when the FIRST failure printed is the named check's (the -21
rule). A mutation an EARLIER check catches is reported as missed: its named
check is wrong, or a guard is redundant: fix the name or remove the
duplicate, never loosen the rule.

    python3 -u tests/v5.4.2-24/mutations-24.py [M01 M12 ...]
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[2]
PATCH = ROOT / "sql/v5.4.2-24-unmatched-cash-and-pledges.sql"
HERE = ROOT / "tests/v5.4.2-24"
DB = "m24"


def rep(old: str, new: str) -> Callable[[str], str]:
    def m(s: str) -> str:
        assert s.count(old) == 1, f"mutation anchor not unique/found ({s.count(old)}): {old[:90]!r}"
        return s.replace(old, new, 1)
    return m


def lock(kind: str, var: str) -> str:
    return f"    PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('{kind}', {var}));\n"


MUTATIONS = [
    # ---- the receipt
    ("M01", "a receipt with no evidence is admitted", "U2",
     rep("               OR agency_id IS NOT NULL)\n);", "               OR agency_id IS NOT NULL OR true)\n);")),
    ("M02", "a receipt may be dated after today", "U4",
     rep("    IF NEW.received_on > public.suspense_today_latest() THEN", "    IF false THEN")),
    ("M03", "a receipt does not check the provider transaction", "U8",
     rep("    PERFORM public.check_provider_transaction_once(NEW.tenant_id, NEW.source_system, NEW.provider_transaction_id, NEW.amount, NEW.id, true);\n    RETURN NEW;\nEND;\n$$;\nCREATE TRIGGER enforce_suspense_receipt",
         "    RETURN NEW;\nEND;\n$$;\nCREATE TRIGGER enforce_suspense_receipt")),
    ("M04", "a payment does not check the provider transaction", "U8b",
     rep("    PERFORM public.check_provider_transaction_once(NEW.tenant_id, NEW.source_system, NEW.provider_transaction_id, NEW.amount, NEW.id, false);\n", "")),
    ("M05", "the provider check reads only receipts", "U8c",
     rep("       OR (p_self_is_receipt AND EXISTS (SELECT 1 FROM public.payments p", "       OR (false AND EXISTS (SELECT 1 FROM public.payments p")),
    ("M06", "the provider check ignores the source system", "U8d",
     rep("WHERE r.tenant_id = p_tenant AND r.source_system = p_source AND r.provider_transaction_id = p_txn", "WHERE r.tenant_id = p_tenant AND r.provider_transaction_id = p_txn")),
    # ---- payments from a receipt
    ("M07", "a resolution needs no reason", "P3",
     rep("        CHECK ((suspense_receipt_id IS NULL) = (suspense_resolution_reason IS NULL)\n", "        CHECK (true\n")),
    ("M08", "a payment from a receipt may be dated before the money came", "P4",
     rep("        IF NEW.payment_date < r.received_on THEN", "        IF false THEN")),
    ("M09", "a payment from a receipt may be effective after the money came", "P4b",
     rep("        IF NEW.effective_date IS NOT NULL AND NEW.effective_date > r.received_on THEN", "        IF false THEN")),
    ("M10", "the effective date written at posting is not checked", "P4c",
     rep("            IF NEW.effective_date > r.received_on THEN", "            IF false THEN")),
    ("M11", "a payment need not carry the receipt's instrument", "P5",
     rep("        IF NEW.channel IS DISTINCT FROM r.channel OR NEW.source_system IS DISTINCT FROM r.source_system\n           OR NEW.reference_number IS DISTINCT FROM r.reference_number OR NEW.check_number IS DISTINCT FROM r.check_number",
         "        IF NEW.channel IS DISTINCT FROM r.channel OR NEW.source_system IS DISTINCT FROM r.source_system\n           OR NEW.reference_number IS DISTINCT FROM r.reference_number")),
    ("M12", "a payment from a receipt may carry its own provider id", "P5c",
     rep("               AND (suspense_receipt_id IS NULL OR (payment_method <> 'refund' AND amount > 0 AND provider_transaction_id IS NULL)));",
         "               AND (suspense_receipt_id IS NULL OR (payment_method <> 'refund' AND amount > 0)));")),
    ("M13", "the receipt's cap is not checked for a payment", "P2",
     rep("    PERFORM public.check_suspense_receipt_cap(NEW.suspense_receipt_id);\n    RETURN NULL;\nEND;\n$$;\nCREATE TRIGGER enforce_payment_suspense_cap",
         "    RETURN NULL;\nEND;\n$$;\nCREATE TRIGGER enforce_payment_suspense_cap")),
    ("M14", "the cap counts a voided payment", "X7b",
     rep("                            AND p.status NOT IN ('voided', 'reversed')), 0)", "                            AND p.status NOT IN ('reversed')), 0)")),
    ("M15", "the cap counts a reversed payment", "P9c",
     rep("                            AND p.status NOT IN ('voided', 'reversed')), 0)", "                            AND p.status NOT IN ('voided')), 0)")),
    ("M16", "the cap reads dispositions on every date at once (an undo hides the worst day)", "X7",
     rep("                          WHERE x.suspense_receipt_id = p_receipt_id AND x.disposed_on <= e.d), 0) AS o", "                          WHERE x.suspense_receipt_id = p_receipt_id), 0) AS o")),
    ("M17", "the payment's cap check takes no lock on the receipt", "SU1",
     rep(lock('suspense_receipt', 'NEW.suspense_receipt_id') + "    PERFORM public.check_suspense_receipt_cap(NEW.suspense_receipt_id);\n    RETURN NULL;",
         "    PERFORM public.check_suspense_receipt_cap(NEW.suspense_receipt_id);\n    RETURN NULL;")),
    ("M18", "a payment from a receipt is not pinned to READ COMMITTED", "SU7",
     rep("        PERFORM public.suspense_require_read_committed('a payment from a suspense receipt');\n", "")),
    ("M19", "a payment from an agency's receipt may be the customer's", "A6",
     rep("        IF r.agency_id IS NOT NULL AND NEW.agency_id IS DISTINCT FROM r.agency_id THEN", "        IF false THEN")),
    ("M20", "the receipt and pledge columns may be rewritten", "P7",
     rep("        IF cardinality(v_changed) > 0 THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('payment %s: %s is written once, at insert (v5.4.2-24)",
         "        IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('payment %s: %s is written once, at insert (v5.4.2-24)")),
    # ---- dispositions
    ("M21", "a disposition takes no lock on the receipt", "SU2",
     rep("    PERFORM public.suspense_require_read_committed('a suspense disposition');\n" + lock('suspense_receipt', 'NEW.suspense_receipt_id'),
         "    PERFORM public.suspense_require_read_committed('a suspense disposition');\n")),
    ("M22", "the cap is not checked for a disposition", "X2",
     rep("    PERFORM public.check_suspense_receipt_cap(NEW.suspense_receipt_id);\n    RETURN NULL;\nEND;\n$$;\nCOMMENT ON FUNCTION public.enforce_suspense_disposition()",
         "    RETURN NULL;\nEND;\n$$;\nCOMMENT ON FUNCTION public.enforce_suspense_disposition()")),
    ("M23", "a return names no instrument", "X3",
     rep("                 WHEN 'returned_to_sender' THEN coalesce(instrument_reference ~ '[[:alnum:]]', false) AND return_code IS NULL",
         "                 WHEN 'returned_to_sender' THEN return_code IS NULL")),
    ("M24", "an escheat names no report", "X3b",
     rep("                 WHEN 'escheated' THEN coalesce(jurisdiction ~ '^[A-Z]{2}$', false) AND coalesce(report_reference ~ '[[:alnum:]]', false) AND return_code IS NULL",
         "                 WHEN 'escheated' THEN coalesce(jurisdiction ~ '^[A-Z]{2}$', false) AND return_code IS NULL")),
    ("M25", "a disposition need not say why", "X3d",
     rep("    CONSTRAINT suspense_receipt_dispositions_reason_check CHECK (coalesce(reason ~ '[[:alnum:]]', false))", "    CONSTRAINT suspense_receipt_dispositions_reason_check CHECK (true)")),
    ("M26", "a disposition may precede the money", "X4",
     rep("    IF NEW.disposed_on < r.received_on THEN", "    IF false THEN")),
    ("M27", "a disposition may be dated after today", "X4b",
     rep("    IF NEW.disposed_on > public.suspense_today_latest() THEN", "    IF false THEN")),
    ("M28", "an undo may precede what it undoes", "X6",
     rep("        IF NEW.disposed_on < u.disposed_on THEN", "        IF false THEN")),
    ("M29", "undos may exceed what they undo", "X6b",
     rep("        IF v_undos > u.amount THEN", "        IF false THEN")),
    ("M30", "an undo may be undone", "X6g",
     rep("        IF NOT FOUND OR u.suspense_receipt_id <> NEW.suspense_receipt_id OR u.kind = 'undo' THEN", "        IF NOT FOUND OR u.suspense_receipt_id <> NEW.suspense_receipt_id THEN")),
    ("M31", "the reader counts a reversed payment against the receipt", "P9b",
     rep("                         AND NOT (p.status IN ('voided', 'reversed') AND p.status_recorded_at <= p_recorded_at)), 0) AS pays,",
         "                         AND NOT (p.status IN ('voided') AND p.status_recorded_at <= p_recorded_at)), 0) AS pays,")),
    ("M32", "the reader ignores a disposition's date", "X1c",
     rep("                       WHERE d.suspense_receipt_id = r.id AND d.disposed_on <= p_on AND d.created_at <= p_recorded_at), 0) AS disp) x",
         "                       WHERE d.suspense_receipt_id = r.id AND d.created_at <= p_recorded_at), 0) AS disp) x")),
    ("M33", "the reader reads a reversal recorded after the instant", "SU6",
     rep("                         AND NOT (p.status IN ('voided', 'reversed') AND p.status_recorded_at <= p_recorded_at)), 0) AS pays,",
         "                         AND NOT (p.status IN ('voided', 'reversed'))), 0) AS pays,")),
    # ---- agencies and agreements
    ("M34", "a retired agency may be brought back", "L17d",
     rep("    IF OLD.status <> 'active' OR NEW.status <> 'retired'", "    IF NEW.status <> 'retired'")),
    ("M35", "a withdrawn agreement is still chosen", "A4c",
     rep("             WHERE g.agency_id = p_agency_id AND g.effective_from <= p_on AND g.withdrawn_at IS NULL", "             WHERE g.agency_id = p_agency_id AND g.effective_from <= p_on")),
    ("M36", "the earliest agreement is chosen, not the latest", "L2b",
     rep("             ORDER BY g.effective_from DESC LIMIT 1);", "             ORDER BY g.effective_from LIMIT 1);")),
    ("M37", "a withdrawal may be undone", "A4d",
     rep("    IF OLD.withdrawn_at IS NOT NULL OR NEW.withdrawn_by IS NULL", "    IF NEW.withdrawn_by IS NULL")),
    # ---- pledges
    ("M38", "pay_by is a day late", "L1b",
     rep("        NEW.pay_by := NEW.pledged_on + v_days;", "        NEW.pay_by := NEW.pledged_on + v_days + 1;")),
    ("M39", "the app may choose pay_by", "L3",
     rep("    IF NEW.agreement_id IS NOT NULL OR NEW.pay_by IS NOT NULL THEN", "    IF NEW.agreement_id IS NOT NULL THEN")),
    ("M40", "a pledge may be dated after today", "L6b",
     rep("    IF NEW.pledged_on > public.suspense_today_latest() THEN", "    IF false THEN")),
    ("M41", "a retired agency takes a pledge", "L17b",
     rep("    IF NOT EXISTS (SELECT 1 FROM public.assistance_agencies a WHERE a.id = NEW.agency_id AND a.tenant_id = NEW.tenant_id AND a.status = 'active') THEN",
         "    IF NOT EXISTS (SELECT 1 FROM public.assistance_agencies a WHERE a.id = NEW.agency_id AND a.tenant_id = NEW.tenant_id) THEN")),
    ("M42", "a pledge takes no lock on its agency", "SU4",
     rep("    PERFORM public.suspense_require_read_committed('a pledge');\n" + lock('agency', 'NEW.agency_id'), "    PERFORM public.suspense_require_read_committed('a pledge');\n")),
    ("M43", "a pledge may be paid by another agency", "L7c",
     rep("        IF l.agency_id IS DISTINCT FROM NEW.agency_id OR l.customer_id IS DISTINCT FROM NEW.customer_id THEN", "        IF l.customer_id IS DISTINCT FROM NEW.customer_id THEN")),
    ("M44", "a pledge may be paid for another customer", "L7d",
     rep("        IF l.agency_id IS DISTINCT FROM NEW.agency_id OR l.customer_id IS DISTINCT FROM NEW.customer_id THEN", "        IF l.agency_id IS DISTINCT FROM NEW.agency_id THEN")),
    ("M45", "a payment may name a pledge recorded in error", "L14c",
     rep("        IF EXISTS (SELECT 1 FROM public.agency_pledge_events e WHERE e.agency_pledge_id = l.id AND e.event = 'recorded_in_error') THEN", "        IF false THEN")),
    ("M46", "a payment naming a pledge takes no lock on it", "SU3b",
     rep("        PERFORM public.suspense_require_read_committed('a payment naming a pledge');\n    " + lock('agency_pledge', 'NEW.agency_pledge_id'),
         "        PERFORM public.suspense_require_read_committed('a payment naming a pledge');\n")),
    ("M47", "a pledge event takes no lock on the pledge", "SU3",
     rep("    PERFORM public.suspense_require_read_committed('a pledge event');\n" + lock('agency_pledge', 'NEW.agency_pledge_id'), "    PERFORM public.suspense_require_read_committed('a pledge event');\n")),
    ("M48", "a pledge a payment names may be recorded in error", "L12e",
     rep("        IF EXISTS (SELECT 1 FROM public.payments p WHERE p.agency_pledge_id = l.id AND p.status <> 'voided') THEN", "        IF false THEN")),
    ("M49", "a paid pledge may be withdrawn", "L12c",
     rep("    IF v_paid >= l.amount THEN", "    IF false THEN")),
    ("M50", "a lapse may be dated on pay_by", "L10b",
     rep("        IF NEW.event_on <= l.pay_by THEN", "        IF NEW.event_on < l.pay_by THEN")),
    ("M51", "a lapse need not wait for pay_by to pass everywhere", "L10a",
     rep("        IF l.pay_by >= public.suspense_today_earliest() THEN", "        IF false THEN")),
    ("M52", "an event may be dated before the pledge", "L13d",
     rep("    IF NEW.event_on IS NOT NULL AND (NEW.event_on < l.pledged_on OR NEW.event_on > public.suspense_today_latest()) THEN",
         "    IF NEW.event_on IS NOT NULL AND (NEW.event_on > public.suspense_today_latest()) THEN")),
    ("M53", "the reader never says overdue", "L1d",
     rep("                WHEN p_on > l.pay_by THEN 'overdue'", "                WHEN p_on > l.pay_by + 10000 THEN 'overdue'")),
    ("M54", "an event outranks being paid in full", "L11e",
     rep("                WHEN x.paid >= l.amount THEN 'paid'\n                WHEN e.event IS NOT NULL AND e.event_on <= p_on THEN e.event\n",
         "                WHEN e.event IS NOT NULL AND e.event_on <= p_on THEN e.event\n                WHEN x.paid >= l.amount THEN 'paid'\n")),
    ("M55", "an event counts before its date", "L11b",
     rep("                WHEN e.event IS NOT NULL AND e.event_on <= p_on THEN e.event\n", "                WHEN e.event IS NOT NULL THEN e.event\n")),
    # ---- where a refund goes
    ("M56", "a refund of an agency's money may go to the customer", "G1",
     rep("            IF v_agency IS NOT NULL THEN\n                RAISE EXCEPTION USING", "            IF false THEN\n                RAISE EXCEPTION USING")),
    ("M57", "a refund of the customer's money may name an agency", "G3",
     rep("            RAISE EXCEPTION USING\n                MESSAGE = format('refund %s: the money is the customer''s own", "            RETURN NEW;\n            RAISE EXCEPTION USING\n                MESSAGE = format('refund %s: the money is the customer''s own")),
    ("M58", "the trace does not follow an overpayment credit to its payment", "G4",
     rep("        IF c.origin_type = 'overpayment' AND c.source_payment_id IS NOT NULL THEN", "        IF false THEN")),
    ("M59", "the trace does not follow a reissue to its refund", "G5",
     rep("        ELSIF c.origin_type = 'refund_reissue' AND c.reissues_refund_id IS NOT NULL THEN", "        ELSIF false THEN")),
    ("M60", "an agency's payment need not name its agency", "L7",
     rep("        CHECK (payment_method = 'refund' OR (payer_class = 'agency') = (agency_id IS NOT NULL)),", "        CHECK (payment_method = 'refund' OR payer_class = 'agency' OR agency_id IS NULL),")),
    # ---- settings and the aged reader
    ("M61", "an unset service level reads as none aged", "S1",
     rep("    IF v_level IS NULL THEN\n        RAISE EXCEPTION USING", "    IF v_level IS NULL THEN\n        RETURN;\n        RAISE EXCEPTION USING")),
    ("M62", "a receipt is aged on the service level's last day", "S3",
     rep("     WHERE r.tenant_id = p_tenant_id AND x.held > 0 AND x.age_days > v_level", "     WHERE r.tenant_id = p_tenant_id AND x.held > 0 AND x.age_days >= v_level")),
    ("M63", "retention is past on its last day", "S3c",
     rep("           CASE WHEN v_retention IS NULL THEN NULL ELSE x.age_days > v_retention END,", "           CASE WHEN v_retention IS NULL THEN NULL ELSE x.age_days >= v_retention END,")),
    ("M64", "a receipt holding nothing is aged", "S3b",
     rep("     WHERE r.tenant_id = p_tenant_id AND x.held > 0 AND x.age_days > v_level", "     WHERE r.tenant_id = p_tenant_id AND x.age_days > v_level")),
    ("M65", "a setting of 0 days is taken", "S6",
     rep("        OR (jsonb_typeof(p_value) = 'number' AND (p_value #>> '{}') ~ '^[1-9][0-9]{0,4}$')", "        OR (jsonb_typeof(p_value) = 'number' AND (p_value #>> '{}') ~ '^[0-9][0-9]{0,4}$')")),
    # ---- the retired program type, the freeze, the invariants
    ("M66", "an agency_pledge enrollment is taken", "Y1",
     rep("    IF NEW.program_type = 'agency_pledge' THEN", "    IF false THEN")),
    ("M67", "the freeze trigger on receipts is dropped", "APPLY:a_enforce_accounting_freeze BEFORE INSERT ON public.suspense_receipts",
     rep("ALTER TABLE public.suspense_receipts ENABLE ALWAYS TRIGGER a_enforce_accounting_freeze;\n", "DROP TRIGGER a_enforce_accounting_freeze ON public.suspense_receipts;\n")),
    ("M68", "a key from payments to a new table loses its tenant", "APPLY:does not carry tenant_id",
     rep("    ADD CONSTRAINT payments_agency_pledge_fkey FOREIGN KEY (agency_pledge_id, tenant_id) REFERENCES public.agency_pledges (id, tenant_id),",
         "    ADD CONSTRAINT payments_agency_pledge_fkey FOREIGN KEY (agency_pledge_id) REFERENCES public.agency_pledges (id),")),
    ("M69", "the payments guard is not ENABLE ALWAYS", "APPLY:enforce_payment_suspense_pledge",
     rep("ALTER TABLE public.payments ENABLE ALWAYS TRIGGER enforce_payment_suspense_pledge;\n", "")),
    ("M70", "the app may update a receipt", "APPLY:suspense_receipts: tally_app may only",
     rep("GRANT UPDATE (status, retired_by, retired_reason) ON public.assistance_agencies TO tally_app;", "GRANT UPDATE (status, retired_by, retired_reason) ON public.assistance_agencies TO tally_app;\nGRANT UPDATE (notes) ON public.suspense_receipts TO tally_app;")),
]

def sh(cmd: list[str], inp: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, input=inp, capture_output=True, text=True)


def sh_ordered(cmd: list[str], inp: str | None = None) -> subprocess.CompletedProcess:
    """stdout and stderr in one stream, in the order written."""
    return subprocess.run(cmd, input=inp, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)


def runner(check: str) -> tuple[list[str], str | None, str]:
    """The command, its input, and the check's bare name."""
    if re.fullmatch(r"SU\d+[a-z]?", check):
        return [str(HERE / "races/suspense-24.sh"), DB], None, check
    battery, name = HERE / "battery-24.sql", check
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
            # r7 (Codex S2): the first error the apply printed, as the
            # behavioral branch takes the first failure.
            first_err = next((l for l in a.stderr.splitlines() if "ERROR" in l), "")
            if phrase is not None and phrase in first_err:
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
        # Fresh statistics for the walks' plans, as tests/ci.sh gives the
        # battery: autovacuum can leave "pages present, 0 rows", which slows
        # the deep lines badly (R21). -22 r4; r8 (Fable S1) added the cash
        # tables the reissue line's walks read; r10 (Codex S1) corrected this
        # comment, which called the vacuumed state the worst.
        v = sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", DB, "-v", "ON_ERROR_STOP=1", "-qc", "VACUUM public.account_ledger, public.payments, public.customer_credits"])
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
