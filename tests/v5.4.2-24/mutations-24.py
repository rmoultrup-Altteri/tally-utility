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


def refill(patch: str) -> str:
    """r2: recompute the invariant's body md5s, as a deliberate edit would,
    so the named behavioural check (not the body check) meets the mutation."""
    import hashlib

    def body(name: str) -> str:
        m = re.search(r"CREATE OR REPLACE FUNCTION public\." + re.escape(name) + r"\(.*?\bAS (\$[a-z]*\$)(.*?)\1", patch, re.S)
        return m.group(2) if m else ""

    return re.sub(r"'([a-z_]+\([^']*\)) @([0-9a-f]{32})'",
                  lambda m: f"'{m.group(1)} @{hashlib.md5(body(m.group(1).split('(')[0]).encode()).hexdigest()}'", patch)


def rep(old: str, new: str) -> Callable[[str], str]:
    def m(s: str) -> str:
        assert s.count(old) == 1, f"mutation anchor not unique/found ({s.count(old)}): {old[:90]!r}"
        return s.replace(old, new, 1)
    return m


def both(*ms: Callable[[str], str]) -> Callable[[str], str]:
    def m(x: str) -> str:
        for f in ms:
            x = f(x)
        return x
    return m


def unpin(conname: str) -> Callable[[str], str]:
    """r2: drop the constraint's entry from the invariant's list too, as a
    deliberate edit would, so the behavioural check meets the mutation."""
    def m(x: str) -> str:
        lines = x.split("\n")
        hit = [i for i, l in enumerate(lines) if (f" {conname} " in l) and l.lstrip().startswith(("'", "E'"))]
        assert len(hit) == 1, f"pinned constraint {conname}: {len(hit)} entries"
        del lines[hit[0]]
        out = "\n".join(lines)
        return out.replace(",\n        ];", "];").replace("ARRAY[\n        ,", "ARRAY[\n        ")
    return m


def lock(kind: str, var: str) -> str:
    return f"    PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('{kind}', {var}));\n"


MUTATIONS = [
    # ---- the receipt
    ("M01", "a receipt with no evidence is admitted", "U2",
     both(rep("               OR agency_id IS NOT NULL)\n);", "               OR agency_id IS NOT NULL OR true)\n);"),
          unpin("suspense_receipts_evidence_check"))),
    ("M02", "a receipt may be dated after today", "U4",
     rep("    IF NEW.received_on > public.suspense_today_latest() THEN", "    IF false THEN")),
    ("M03", "a receipt does not check the provider transaction", "U8",
     rep("    PERFORM public.check_provider_transaction_once(NEW.tenant_id, NEW.source_system, NEW.provider_transaction_id, NEW.amount, NEW.id, true);\n    RETURN NEW;\nEND;\n$$;\nCREATE TRIGGER enforce_suspense_receipt",
         "    RETURN NEW;\nEND;\n$$;\nCREATE TRIGGER enforce_suspense_receipt")),
    ("M04", "a payment does not check the provider transaction", "U8b",
     rep("    -- second payment of it is -19's payments_provider_transaction_once).\n    PERFORM public.check_provider_transaction_once(NEW.tenant_id, NEW.source_system, NEW.provider_transaction_id, NEW.amount, NEW.id, false);\n",
         "    -- second payment of it is -19's payments_provider_transaction_once).\n")),
    ("M05", "the provider check reads only receipts", "U8c",
     rep("       OR (p_self_is_receipt AND EXISTS (SELECT 1 FROM public.payments p", "       OR (false AND EXISTS (SELECT 1 FROM public.payments p")),
    ("M06", "the provider check of payments ignores the source system", "U8d",
     rep("WHERE p.tenant_id = p_tenant AND p.source_system = p_source AND p.provider_transaction_id = p_txn", "WHERE p.tenant_id = p_tenant AND p.provider_transaction_id = p_txn")),
    ("M06b", "the provider check of receipts ignores the source system", "U8e",
     rep("WHERE r.tenant_id = p_tenant AND r.source_system = p_source AND r.provider_transaction_id = p_txn", "WHERE r.tenant_id = p_tenant AND r.provider_transaction_id = p_txn")),
    # ---- payments from a receipt
    ("M07", "a resolution needs no reason", "P3",
     both(rep("        CHECK ((suspense_receipt_id IS NULL) = (suspense_resolution_reason IS NULL)\n", "        CHECK (true\n"),
          unpin("payments_suspense_resolution_check"))),
    ("M08", "a payment from a receipt may be dated before the money came", "P4",
     rep("        IF NEW.payment_date < r.received_on THEN", "        IF false THEN")),
    ("M09", "a payment from a receipt may be effective after the money came", "P4b",
     rep("        IF NEW.effective_date IS NOT NULL AND NEW.effective_date > r.received_on THEN", "        IF false THEN")),
    ("M10", "the effective date written at posting is not checked", "P4c",
     rep("            IF NEW.effective_date > r.received_on THEN", "            IF false THEN")),
    ("M11", "a payment need not carry the receipt's instrument", "P5",
     rep("\n        IF NEW.channel IS DISTINCT FROM r.channel OR NEW.source_system IS DISTINCT FROM r.source_system\n           OR NEW.reference_number IS DISTINCT FROM r.reference_number OR NEW.check_number IS DISTINCT FROM r.check_number",
         "\n        IF NEW.channel IS DISTINCT FROM r.channel OR NEW.source_system IS DISTINCT FROM r.source_system\n           OR NEW.reference_number IS DISTINCT FROM r.reference_number")),
    ("M12", "a payment from a receipt may carry its own provider id", "P5c",
     both(rep("               AND (suspense_receipt_id IS NULL OR (payment_method <> 'refund' AND amount > 0 AND provider_transaction_id IS NULL)));",
         "               AND (suspense_receipt_id IS NULL OR (payment_method <> 'refund' AND amount > 0)));"),
          unpin("payments_suspense_resolution_check"))),
    ("M13", "the receipt's cap is not checked for a payment", "P2",
     rep("    PERFORM public.check_suspense_receipt_cap(NEW.suspense_receipt_id);\n    RETURN NULL;\nEND;\n$$;\nCREATE TRIGGER enforce_payment_suspense_cap",
         "    RETURN NULL;\nEND;\n$$;\nCREATE TRIGGER enforce_payment_suspense_cap")),
    ("M14", "the cap counts a voided payment", "P8b",
     rep("                            AND p.status <> 'voided'), 0)", "                            AND true), 0)")),
    ("M15", "the cap gives a reversed payment's share back by itself (r1's rule; the below-zero cap meets it)", "P9b6",
     rep("                            AND p.status <> 'voided'), 0)", "                            AND p.status NOT IN ('voided', 'reversed')), 0)")),
    ("M16", "the cap reads dispositions on every date at once (an undo hides the worst day)", "P9c2",
     rep("                          WHERE x.suspense_receipt_id = p_receipt_id AND x.disposed_on <= e.d), 0) AS o", "                          WHERE x.suspense_receipt_id = p_receipt_id), 0) AS o")),
    ("M17", "the payment's cap check takes no lock on the receipt", "SU1",
     rep(lock('suspense_receipt', 'NEW.suspense_receipt_id') + "    PERFORM public.check_suspense_recorded_order(NEW.suspense_receipt_id, NEW.id, true, NEW.created_at, 'a payment from a receipt');\n",
         "    PERFORM public.check_suspense_recorded_order(NEW.suspense_receipt_id, NEW.id, true, NEW.created_at, 'a payment from a receipt');\n")),
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
    ("M22", "the cap is not checked for a disposition", "P12d",
     rep("    PERFORM public.check_suspense_receipt_cap(NEW.suspense_receipt_id);\n    RETURN NULL;\nEND;\n$$;\nCOMMENT ON FUNCTION public.enforce_suspense_disposition()",
         "    RETURN NULL;\nEND;\n$$;\nCOMMENT ON FUNCTION public.enforce_suspense_disposition()")),
    ("M23", "a return names no instrument", "X3",
     both(rep("                 WHEN 'returned_to_sender' THEN coalesce(instrument_reference ~ '[[:alnum:]]', false) AND return_code IS NULL",
         "                 WHEN 'returned_to_sender' THEN return_code IS NULL"),
          unpin("suspense_receipt_dispositions_kind_check"))),
    ("M24", "an escheat names no report", "X3b",
     both(rep("                 WHEN 'escheated' THEN coalesce(jurisdiction ~ '^[A-Z]{2}$', false) AND coalesce(report_reference ~ '[[:alnum:]]', false) AND return_code IS NULL",
         "                 WHEN 'escheated' THEN coalesce(jurisdiction ~ '^[A-Z]{2}$', false) AND return_code IS NULL"),
          unpin("suspense_receipt_dispositions_kind_check"))),
    ("M25", "a disposition need not say why", "X3d",
     both(rep("    CONSTRAINT suspense_receipt_dispositions_reason_check CHECK (coalesce(reason ~ '[[:alnum:]]', false))", "    CONSTRAINT suspense_receipt_dispositions_reason_check CHECK (true)"),
          unpin("suspense_receipt_dispositions_reason_check"))),
    ("M26", "a disposition may precede the money", "X4",
     rep("    IF NEW.disposed_on < r.received_on THEN", "    IF false THEN")),
    ("M27", "a disposition may be dated after today", "X4b",
     rep("    IF NEW.disposed_on > public.suspense_today_latest() THEN", "    IF false THEN")),
    ("M28", "an undo may precede what it undoes", "X6",
     rep("        IF NEW.disposed_on < u.disposed_on THEN", "        IF false THEN")),
    ("M29", "undos may exceed what they undo", "X6b",
     rep("        IF v_undos > u.amount THEN", "        IF false THEN")),
    ("M30", "an undo may be undone", "X6g",
     rep("        IF NOT FOUND OR u.suspense_receipt_id <> NEW.suspense_receipt_id OR u.kind IN ('undo', 'misposting_returned') THEN", "        IF NOT FOUND OR u.suspense_receipt_id <> NEW.suspense_receipt_id OR u.kind IN ('misposting_returned') THEN")),
    ("M30b", "a misposting return may be undone", "P9b10",
     rep("        IF NOT FOUND OR u.suspense_receipt_id <> NEW.suspense_receipt_id OR u.kind IN ('undo', 'misposting_returned') THEN", "        IF NOT FOUND OR u.suspense_receipt_id <> NEW.suspense_receipt_id OR u.kind IN ('undo') THEN")),
    ("M31", "the reader gives a reversed payment's share back by itself", "P9b",
     rep("                         AND NOT (p.status = 'voided' AND p.status_recorded_at <= p_recorded_at)), 0) AS pays,",
         "                         AND NOT (p.status IN ('voided', 'reversed') AND p.status_recorded_at <= p_recorded_at)), 0) AS pays,")),
    ("M32", "the reader ignores a disposition's date", "P9b7",
     rep("                       WHERE d.suspense_receipt_id = r.id AND d.disposed_on <= p_on AND d.created_at <= p_recorded_at), 0) AS disp) x",
         "                       WHERE d.suspense_receipt_id = r.id AND d.created_at <= p_recorded_at), 0) AS disp) x")),
    # ---- agencies and agreements
    ("M34", "a retired agency may be brought back", "L17d",
     rep("    IF OLD.status <> 'active' OR NEW.status <> 'retired'", "    IF NEW.status NOT IN ('retired', 'active')")),
    ("M35", "a withdrawn agreement is still chosen", "A4c",
     rep("             WHERE g.agency_id = p_agency_id AND g.effective_from <= p_on AND g.withdrawn_at IS NULL", "             WHERE g.agency_id = p_agency_id AND g.effective_from <= p_on")),
    ("M36", "the earliest agreement is chosen, not the latest", "L2b",
     rep("             ORDER BY g.effective_from DESC LIMIT 1);", "             ORDER BY g.effective_from LIMIT 1);")),
    ("M37", "a withdrawal may be undone", "A4d",
     rep("    IF OLD.withdrawn_at IS NOT NULL OR NEW.withdrawn_by IS NULL", "    IF false")),
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
    ("M46", "a payment naming a pledge takes no lock on it", "SU3",
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
    ("M56", "a refund's payee is not checked against whose money it is (Codex S2)", "G1",
     rep("        IF v_agency IS DISTINCT FROM NEW.agency_id THEN", "        IF false THEN")),
    ("M57", "a refund of the customer's money may name an agency", "G3",
     rep("            RAISE EXCEPTION USING\n                MESSAGE = format('refund %s: the money is the customer''s own", "            RETURN NEW;\n            RAISE EXCEPTION USING\n                MESSAGE = format('refund %s: the money is the customer''s own")),
    ("M58", "the trace does not follow an overpayment credit to its payment", "G4",
     rep("        IF c.origin_type = 'overpayment' AND c.source_payment_id IS NOT NULL THEN", "        IF false THEN")),
    ("M59", "the trace does not follow a reissue to its refund", "G5",
     rep("        ELSIF c.origin_type = 'refund_reissue' AND c.reissues_refund_id IS NOT NULL THEN", "        ELSIF false THEN")),
    ("M60", "an agency's payment need not name its agency", "L7",
     both(rep("        CHECK (payment_method = 'refund' OR (payer_class = 'agency') = (agency_id IS NOT NULL)),", "        CHECK (payment_method = 'refund' OR payer_class = 'agency' OR agency_id IS NULL),"),
          unpin("payments_agency_check"))),
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
     rep("        OR (jsonb_typeof(p_value) = 'number' AND (p_value #>> '{}') ~ '^[1-9][0-9]{0,3}$')", "        OR (jsonb_typeof(p_value) = 'number' AND (p_value #>> '{}') ~ '^[0-9][0-9]{0,3}$')")),
    # ---- the retired program type, the freeze, the invariants
    ("M66", "an agency_pledge enrollment is taken", "Y1",
     rep("    IF NEW.program_type = 'agency_pledge' THEN", "    IF false THEN")),
    ("M67", "the freeze trigger on receipts is dropped", "APPLY:a v5.4.2-24 guard is missing",
     rep("ALTER TABLE public.suspense_receipts ENABLE ALWAYS TRIGGER a_enforce_accounting_freeze;\n", "DROP TRIGGER a_enforce_accounting_freeze ON public.suspense_receipts;\n")),
    ("M68", "a key from payments to a new table loses its tenant", "APPLY:does not carry tenant_id",
     both(rep("    ADD CONSTRAINT payments_agency_pledge_fkey FOREIGN KEY (agency_pledge_id, tenant_id) REFERENCES public.agency_pledges (id, tenant_id),",
         "    ADD CONSTRAINT payments_agency_pledge_fkey FOREIGN KEY (agency_pledge_id) REFERENCES public.agency_pledges (id),"),
          unpin("payments_agency_pledge_fkey"))),
    ("M69", "the payments guard is not ENABLE ALWAYS", "APPLY:a v5.4.2-24 guard is missing",
     rep("ALTER TABLE public.payments ENABLE ALWAYS TRIGGER enforce_payment_suspense_pledge;\n", "")),
    ("M70", "the app may update a receipt", "APPLY:suspense_receipts: tally_app may only",
     rep("GRANT UPDATE (status, retired_by, retired_reason) ON public.assistance_agencies TO tally_app;", "GRANT UPDATE (status, retired_by, retired_reason) ON public.assistance_agencies TO tally_app;\nGRANT UPDATE (notes) ON public.suspense_receipts TO tally_app;")),
    # ---- r2
    ("M71", "a bank's take-back recorded as reversed may come back to the receipt", "P12b",
     rep("        IF v_pay.status <> 'reversed' OR v_pay.return_code IS NOT NULL THEN", "        IF v_pay.status <> 'reversed' THEN")),
    ("M72", "a payment not reversed may be returned to suspense", "P9b5",
     rep("        IF v_pay.status <> 'reversed' OR v_pay.return_code IS NOT NULL THEN", "        IF v_pay.return_code IS NOT NULL THEN")),
    ("M73", "a misposting return may exceed its payment", "P9b3",
     rep("        IF -NEW.amount <> v_misposted THEN", "        IF false THEN")),
    # M74 removed (r6, Codex r6 S1): r5's check of the reversal's date was
    # always beaten by the tree-date rule (M112, P9b2 and P14h), and is gone.
    ("M75", "a misposting return may name another receipt's payment", "P9b4",
     rep("        IF NOT FOUND OR v_pay.suspense_receipt_id IS DISTINCT FROM NEW.suspense_receipt_id THEN", "        IF NOT FOUND THEN")),
    ("M76", "a payment may be returned to suspense twice", "APPLY:a v5.4.2-24 unique index is missing",
     rep("CREATE UNIQUE INDEX suspense_receipt_dispositions_one_return_per_payment\n    ON", "CREATE INDEX suspense_receipt_dispositions_one_return_per_payment\n    ON")),
    ("M77", "a payment returned to suspense may take a return code", "P9b9",
     rep("                IF EXISTS (SELECT 1 FROM public.suspense_receipt_dispositions d WHERE d.returned_payment_id = NEW.id) THEN", "                IF false THEN")),
    ("M78", "a receipt's payment may drift from its instrument after insert", "P5e",
     both(rep("            IF NEW.channel IS DISTINCT FROM r.channel OR NEW.source_system IS DISTINCT FROM r.source_system\n               OR", "            IF false AND (NEW.channel IS DISTINCT FROM r.channel OR NEW.source_system IS DISTINCT FROM r.source_system\n               OR"),
          rep("OR NEW.check_bank_name IS DISTINCT FROM r.check_bank_name THEN\n                RAISE EXCEPTION USING\n                    MESSAGE = format('payment %s carries the receipt''s instrument: channel, source system, reference, check number, date and bank as receipt %s records them, at insert and after",
              "OR NEW.check_bank_name IS DISTINCT FROM r.check_bank_name) THEN\n                RAISE EXCEPTION USING\n                    MESSAGE = format('payment %s carries the receipt''s instrument: channel, source system, reference, check number, date and bank as receipt %s records them, at insert and after"))),
    ("M79", "a provider id written later is not checked", "U8h",
     rep("        IF OLD.provider_transaction_id IS NULL AND NEW.provider_transaction_id IS NOT NULL THEN", "        IF false THEN")),
    ("M80", "the provider check excludes a row of the other table with the same uuid (r1)", "U8f",
     rep("                  AND NOT (p_self_is_receipt AND r.id = p_self))", "                  AND r.id IS DISTINCT FROM p_self)")),
    ("M81", "the provider check is not pinned to READ COMMITTED", "SU8",
     rep("    PERFORM public.suspense_require_read_committed('a provider transaction id');\n", "")),
    ("M82", "a payment may be recorded before a row of its receipt", "O1",
     rep("    PERFORM public.check_suspense_recorded_order(NEW.suspense_receipt_id, NEW.id, true, NEW.created_at, 'a payment from a receipt');\n", "")),
    ("M83", "a disposition may be recorded before a row of its receipt", "O1b",
     rep("    PERFORM public.check_suspense_recorded_order(NEW.suspense_receipt_id, NEW.id, false, NEW.created_at, 'a disposition');\n", "")),
    ("M84", "a writer begun before a committed row is not told to retry", "SU10",
     rep("        IF p_at = pg_catalog.now() THEN", "        IF false THEN")),
    ("M85", "a row may be recorded in the future", "O2b",
     rep("    IF NEW.created_at IS NULL OR NOT pg_catalog.isfinite(NEW.created_at) OR NEW.created_at > pg_catalog.clock_timestamp() THEN", "    IF NEW.created_at IS NULL OR NOT pg_catalog.isfinite(NEW.created_at) THEN")),
    ("M86", "a row may be recorded at -infinity", "O2e",
     rep("    IF NEW.created_at IS NULL OR NOT pg_catalog.isfinite(NEW.created_at) OR NEW.created_at > pg_catalog.clock_timestamp() THEN", "    IF NEW.created_at IS NULL OR NEW.created_at > pg_catalog.clock_timestamp() THEN")),
    ("M87", "a pledge toward a bill may be paid unrestricted", "L18",
     rep("        IF l.toward_invoice_id IS NOT NULL AND NEW.restricted_to_invoice_id IS DISTINCT FROM l.toward_invoice_id THEN", "        IF false THEN")),
    ("M88", "a pledge may be for another tenant's customer", "O3",
     rep("    IF NOT EXISTS (SELECT 1 FROM public.customers c WHERE c.id = NEW.customer_id AND c.tenant_id = NEW.tenant_id) THEN", "    IF false THEN")),
    ("M89", "the invariant checks no constraint", "I8",
     rep("      FROM unnest(c_constraints) d", "      FROM unnest(ARRAY[]::text[]) d")),
    ("M90", "the invariant checks no unique index", "I8d",
     rep("      FROM unnest(c_indexes) d", "      FROM unnest(ARRAY[]::text[]) d")),
    ("M91", "the invariant checks no function body", "I8f",
     rep("      FROM unnest(c_bodies) d", "      FROM unnest(ARRAY[]::text[]) d")),
    ("M92", "the invariant requires no stamp grant", "I8e",
     rep("    IF NOT has_column_privilege('tally_app', 'public.assistance_agencies', 'status', 'UPDATE')", "    IF false AND NOT has_column_privilege('tally_app', 'public.assistance_agencies', 'status', 'UPDATE')")),
    ("M93", "the invariant does not check the recorded-at guard", "I8g",
     rep("                format('CREATE TRIGGER b_enforce_recorded_at BEFORE INSERT ON public.%s FOR EACH ROW EXECUTE FUNCTION enforce_suspense_recorded_at()', t),\n", "")),
    ("M94", "a value written straight into the history is read unchecked", "S5b",
     both(rep("           OR public.suspense_days_setting_valid(new_value));", "           OR true);"),
          unpin("tenant_configuration_history_suspense_days_check"))),
    # ---- r3
    ("M95", "a release is not ordered after what it releases", "O1f",
     rep("    PERFORM public.check_suspense_recorded_order(NEW.suspense_receipt_id, NEW.id, false, NEW.created_at, 'a disposition');\n",
         "    IF NEW.amount > 0 THEN PERFORM public.check_suspense_recorded_order(NEW.suspense_receipt_id, NEW.id, false, NEW.created_at, 'a disposition'); END IF;\n")),
    ("M96", "the order check does not read a reversal's recorded time", "O1g",
     rep("         WHERE p.suspense_receipt_id = p_receipt_id AND p.status IN ('voided', 'reversed') AND NOT", "         WHERE p.suspense_receipt_id = p_receipt_id AND p.status IN ('voided') AND NOT")),
    ("M97", "the order check excludes a disposition that shares the payment's uuid", "O1e",
     rep("         WHERE d.suspense_receipt_id = p_receipt_id AND NOT (NOT p_self_is_payment AND d.id = p_self)", "         WHERE d.suspense_receipt_id = p_receipt_id AND d.id <> p_self")),
    ("M98", "a misposting return counts what the bank took back", "P13",
     rep("SELECT l.id, l.amount FROM e JOIN public.account_ledger l ON l.reverses_ledger_entry_id = e.id AND NOT (l.transaction_type = 'nsf' AND l.amount > 0)", "SELECT l.id, l.amount FROM e JOIN public.account_ledger l ON l.reverses_ledger_entry_id = e.id")),
    ("M99", "a receipt of NaN is taken", "U3b",
     both(rep("    CONSTRAINT suspense_receipts_amount_check CHECK (amount > 0 AND amount <> 'NaN'::numeric),", "    CONSTRAINT suspense_receipts_amount_check CHECK (amount > 0),"),
          unpin("suspense_receipts_amount_check"))),
    ("M100", "a disposition does not check its receipt's tenant", "O3b",
     rep("    SELECT * INTO r FROM public.suspense_receipts x WHERE x.id = NEW.suspense_receipt_id AND x.tenant_id = NEW.tenant_id;\n    -- r3 (Opus r2 N)",
         "    SELECT * INTO r FROM public.suspense_receipts x WHERE x.id = NEW.suspense_receipt_id;\n    -- r3 (Opus r2 N)")),
    ("M101", "a pledge event does not check its pledge's tenant", "O3c",
     rep("\n    SELECT * INTO l FROM public.agency_pledges x WHERE x.id = NEW.agency_pledge_id AND x.tenant_id = NEW.tenant_id;\n    IF NOT FOUND", "\n    SELECT * INTO l FROM public.agency_pledges x WHERE x.id = NEW.agency_pledge_id;\n    IF NOT FOUND")),
    ("M102", "the invariant checks no function attribute", "I9b",
     rep("      FROM unnest(c_attrs) d", "      FROM unnest(ARRAY[]::text[]) d")),
    ("M103", "the invariant checks no NOT NULL", "I9e",
     rep("      FROM unnest(c_notnull) d", "      FROM unnest(ARRAY[]::text[]) d")),
    ("M104", "the invariant requires no helper EXECUTE", "I9d",
     rep("      FROM unnest(c_app_exec) d", "      FROM unnest(ARRAY[]::text[]) d")),
    ("M105", "the READ COMMITTED pin does nothing (Opus r2 S1)", "SU7",
     rep("BEGIN\n    IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN", "BEGIN\n    RETURN;\n    IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN")),
    # ---- r4
    ("M106", "a reversal's own reversal is not netted in the misposted share (r3; r6: the bound at the payment cannot be reached under -23's caps, r6 plan item 3)", "P14b",
     rep("SELECT l.id, l.amount FROM down d JOIN public.account_ledger l ON l.reverses_ledger_entry_id = d.id AND NOT (l.transaction_type = 'nsf' AND l.amount > 0)", "SELECT l.id, l.amount FROM down d JOIN public.account_ledger l ON l.reverses_ledger_entry_id = d.id AND false")),
    ("M107", "the order check excludes no payment's own void (r3)", "O4",
     rep("p.status IN ('voided', 'reversed') AND NOT (p_self_is_payment AND p.id = p_self)) x", "p.status IN ('voided', 'reversed')) x")),
    ("M108", "a payment of NaN may name a pledge", "L7f",
     both(rep("NOT is_deposit AND amount > 0 AND amount <> 'NaN'::numeric)),", "NOT is_deposit AND amount > 0)),"),
          unpin("payments_agency_pledge_check"))),
    # ---- r5
    ("M109", "an nsf row below a reversal counts as misposted (r4; Fable r4 B1)", "P14c",
     rep("SELECT l.id, l.amount FROM down d JOIN public.account_ledger l ON l.reverses_ledger_entry_id = d.id AND NOT (l.transaction_type = 'nsf' AND l.amount > 0)", "SELECT l.id, l.amount FROM down d JOIN public.account_ledger l ON l.reverses_ledger_entry_id = d.id")),
    ("M110", "a misposting return may be dated before its payment (Opus r4 S1)", "P9b11",
     rep("        IF NEW.disposed_on < v_pay.payment_date THEN", "        IF false THEN")),
    # ---- r6
    ("M112", "a misposting return may be dated before the last row under its posting entry (r6; Codex r5 B1; first met at P9b2, the reversal's own date, since r6 removed that separate check)", "P9b2",
     rep("        IF NEW.disposed_on < v_tree_last THEN", "        IF false THEN")),
    ("M113", "a misposting return may be recorded before a row under its posting entry (r6; Codex r6 B1)", "P14i",
     rep("        IF NEW.created_at < v_tree_recorded THEN", "        IF false THEN")),
    ("M114", "the invariant passes over a missing helper its guards call (r6; Codex r6 S2)", "I9d2",
     rep("     WHERE NOT coalesce(has_function_privilege('tally_app', pg_catalog.to_regprocedure('public.' || d), 'EXECUTE'), false);",
         "     WHERE NOT has_function_privilege('tally_app', pg_catalog.to_regprocedure('public.' || d), 'EXECUTE');")),
    ("M115", "a misposting return may be short of the share (r7; Opus r6 S1)", "P9b3b",
     rep("        IF -NEW.amount <> v_misposted THEN", "        IF -NEW.amount > v_misposted THEN")),
    ("M116", "a chosen time before a row under the posting entry is admitted (r7; Opus r6 S2)", "P14i4",
     rep("            RAISE EXCEPTION USING\n                MESSAGE = format('a misposting return of payment %s is recorded at %s, before a row under its posting entry",
         "            RETURN NULL;\n            RAISE EXCEPTION USING\n                MESSAGE = format('a misposting return of payment %s is recorded at %s, before a row under its posting entry")),
    ("M117", "the returns-due reader lists a payment whose share has come back (r8; Opus r7 S1)", "S8b",
     rep("WHERE d.returned_payment_id = p.id AND d.disposed_on <= p_on", "WHERE false AND d.returned_payment_id = p.id AND d.disposed_on <= p_on")),
    ("M118", "the returns-due reader lists a payment with no share (r8)", "S8c",
     rep("       AND s.owed > 0\n", "")),
    ("M119", "the returns-due reader lists a payment before its reversal's date (r8)", "S8d",
     rep("       AND l.transaction_date <= p_on\n", "")),
    ("M111", "an nsf row giving money back is left out of the misposted share (r5; Opus r5 B1)", "P14e",
     rep("SELECT l.id, l.amount FROM down d JOIN public.account_ledger l ON l.reverses_ledger_entry_id = d.id AND NOT (l.transaction_type = 'nsf' AND l.amount > 0)", "SELECT l.id, l.amount FROM down d JOIN public.account_ledger l ON l.reverses_ledger_entry_id = d.id AND l.transaction_type <> 'nsf'")),
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
            patched = refill(mut(base))
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
