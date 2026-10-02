#!/usr/bin/env python3
"""v5.4.2-15 — prove battery-15 (and X1, R1) CATCH drift, not merely pass.

Each mutation alters a copy of the patch, applies it (strict) to a fresh clone
of `tally`, which must be a -14 BASE (tu.sql 26,049 lines, 9139367a…), and
runs the check that must catch it: a battery check (A-Z), X1
(evidence-txn-15.sh) or R1/R2 (races/due-mutex-15.sh). CAUGHT when that check
reports FAIL, or the run errors without reporting it as PASS.

    python3 tests/v5.4.2-15/mutations-15.py [M07 M12 ...]
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATCH = ROOT / "sql/v5.4.2-15-deposits-law-to-core.sql"
BATTERY = ROOT / "tests/v5.4.2-15/battery-15.sql"
XTXN = ROOT / "tests/v5.4.2-15/evidence-txn-15.sh"
RACE = ROOT / "tests/v5.4.2-15/races/due-mutex-15.sh"
DB = "m15"


def rep(old, new):
    def m(s):
        assert s.count(old) == 1, f"mutation anchor not unique/found: {old[:80]!r}"
        return s.replace(old, new, 1)
    return m


def cut(start, end):
    """Remove from `start` up to (not including) `end`, searching after start."""
    def m(s):
        i = s.index(start)
        j = s.index(end, i + len(start))
        return s[:i] + s[j:]
    return m


RAISE_END = "        END IF;\n"

MUTATIONS = [
    # ---- deposits (section 5)
    # No M01: the "rule_id IS NULL" refusal in enforce_deposit() is reached by
    # the rule-key comparison too (a deposit's basis is never NULL, a missing
    # rule's is), so removing it changes the message, not the outcome.
    ("M02", "the decision CHECK admits a NULL core version", "C2",
     rep("AND (decided_by IS NOT NULL) AND (decided_by ~ '[[:alnum:]]'::text))));", "AND (decided_by ~ '[[:alnum:]]'::text))));")),
    ("M03", "the rule's key is not compared with the deposit's", "C3",
     rep("        IF v_rule.state_code IS DISTINCT FROM NEW.state_code OR v_rule.service_type IS DISTINCT FROM NEW.service_type\n           OR v_rule.customer_class IS DISTINCT FROM NEW.customer_class OR v_rule.basis IS DISTINCT FROM NEW.basis THEN",
         "        IF false THEN")),
    ("M04", "the rule need not be in force on the posting date", "C4",
     rep("IF NOT (daterange(v_rule.effective_from, v_rule.effective_to, '[)') @> NEW.posted_on) THEN", "IF false THEN")),
    ("M05", "a cap is allowed under a rule with none", "C5",
     rep("            IF NEW.cap_amount IS NOT NULL OR NEW.cap_basis_kind IS NOT NULL OR NEW.cap_basis_amount IS NOT NULL OR NEW.cap_binding THEN",
         "            IF false THEN")),
    ("M06", "a capped rule needs no cap", "C5",
     rep("        ELSIF NEW.cap_amount IS NULL OR NEW.cap_basis_kind IS DISTINCT FROM v_rule.cap_kind\n              OR ((NEW.cap_basis_amount IS NULL) <> (v_rule.cap_kind = 'fixed_amount')) THEN",
         "        ELSIF false THEN")),
    ("M07", "the insertable flag is not read", "C7",
     rep("        IF v_insertable IS NOT TRUE THEN", "        IF false THEN")),
    ("M08", "rule_id not frozen", "C9",
     rep("OR OLD.rule_id IS DISTINCT FROM NEW.rule_id", "")),
    ("M09", "decided_by not frozen", "C9",
     rep("       OR OLD.decided_by IS DISTINCT FROM NEW.decided_by\n", "")),
    ("M10", "cap_basis_amount not frozen", "C9",
     rep("       OR OLD.cap_basis_amount IS DISTINCT FROM NEW.cap_basis_amount\n", "")),
    # ---- the law tables (sections 2-3)
    ("M11", "a rule row may be deleted", "A5",
     rep("    IF TG_OP = 'DELETE' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit rule %s: law rows are never deleted",
         "    IF TG_OP = 'DELETE' THEN\n        RETURN OLD;\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit rule %s: law rows are never deleted")),
    ("M12", "a close may carry another change", "A6",
     rep("    IF OLD.effective_to IS NOT NULL OR NEW.effective_to IS NULL\n       OR (to_jsonb(NEW) - c_close_cols) <> (to_jsonb(OLD) - c_close_cols) THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit rule %s: law rows are never edited",
         "    IF OLD.effective_to IS NOT NULL OR NEW.effective_to IS NULL THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit rule %s: law rows are never edited")),
    ("M13", "no close floor", "Z5",
     rep("    IF v_latest IS NOT NULL AND NEW.effective_to <= v_latest THEN", "    IF false THEN")),
    ("M14", "the close is not stamped", "Z6",
     rep("    NEW.closed_at := now();\n    NEW.closed_by := session_user;\n    RETURN NEW;\nEND;\n$$;\nCOMMENT ON FUNCTION public.enforce_deposit_rule_history()",
         "    RETURN NEW;\nEND;\n$$;\nCOMMENT ON FUNCTION public.enforce_deposit_rule_history()")),
    ("M15", "return reasons left editable", "A7",
     rep("'deposit_waiver_classes', 'deposit_return_reasons'] LOOP", "'deposit_waiver_classes'] LOOP")),
    ("M16", "a rule row may overlap another for its key", "A8",
     rep(",\n    CONSTRAINT deposit_rules_no_overlap\n        EXCLUDE USING gist (state_code WITH =, service_type WITH =, customer_class WITH =, basis WITH =,\n                            daterange(effective_from, effective_to, '[)'::text) WITH &&)", "")),
    ("M17", "a fraction cap without its divisor (NULL leg)", "A9",
     rep("AND (cap_divisor IS NOT NULL) AND (cap_divisor > 0)", "AND (cap_divisor > 0)")),
    ("M18", "a minimum hold without retroactivity", "A9",
     rep("                 AND ((interest_min_hold_days IS NULL) = (interest_retroactive IS NULL))\n", "")),
    ("M19", "refund fields on no mandatory return", "A9",
     rep("                 AND (refund_after_count IS NULL) AND (refund_measure IS NULL) AND (refund_max_delinquencies IS NULL)\n                 AND (refund_disqualify_on_disconnect IS NULL)",
         "                 AND (refund_disqualify_on_disconnect IS NULL)")),
    ("M20", "the application may write rules", "A3",
     rep("REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.deposit_rules FROM tally_app;\nGRANT SELECT ON public.deposit_rules TO tally_app;",
         "GRANT SELECT, INSERT, UPDATE ON public.deposit_rules TO tally_app;")),
    # ---- rates (section 4)
    ("M21", "a published rate may be edited", "B3",
     rep("    IF OLD.effective_to IS NOT NULL OR NEW.effective_to IS NULL\n       OR (to_jsonb(NEW) - c_close_cols) <> (to_jsonb(OLD) - c_close_cols) THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit_interest_rate_law %s: published rates are never edited",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit_interest_rate_law %s: published rates are never edited")),
    ("M22", "the report lists equal rates as differing", "B5",
     rep("       AND u.annual_rate <> l.annual_rate\n", "\n")),
    ("M23", "the report omits the no_utility_rate gap", "B5",
     rep("       AND (f.first_date IS NULL OR l.effective_from < f.first_date);", "       AND false;")),
    ("M24", "the backdating guard is per tenant, not per state and service", "E17",
     rep("     WHERE e.event_type = 'interest_accrued' AND r.tenant_id = NEW.tenant_id\n       AND r.state_code = NEW.state_code AND r.service_type = NEW.service_type;",
         "     WHERE e.event_type = 'interest_accrued' AND r.tenant_id = NEW.tenant_id;")),
    # ---- waivers (section 6)
    ("M25", "a certified class needs no reference", "D1",
     rep("    IF v_cert AND (NEW.certification_reference IS NULL OR NEW.certification_reference !~ '[[:alnum:]]') THEN", "    IF false THEN")),
    # ---- events (section 8)
    ("M26", "an accrual may cite another rule", "E1",
     rep("        IF d.rule_id IS NULL OR NEW.rule_id IS DISTINCT FROM d.rule_id THEN", "        IF d.rule_id IS NULL THEN")),
    ("M27", "an accrual may cite another state's rate", "E2",
     rep("        IF v_rate.tenant_id IS DISTINCT FROM d.tenant_id OR v_rate.state_code IS DISTINCT FROM d.state_code\n           OR v_rate.service_type IS DISTINCT FROM d.service_type THEN",
         "        IF v_rate.tenant_id IS DISTINCT FROM d.tenant_id THEN")),
    ("M28", "a rate may apply before it takes effect", "E3",
     rep("        IF v_rate.effective_date > NEW.period_start THEN", "        IF false THEN")),
    ("M29", "rate_applied need not be the row's", "E4",
     rep("        IF NEW.rate_applied <> v_rate.annual_rate THEN", "        IF false THEN")),
    ("M30", "a period may start before posting", "E5",
     rep("        IF NEW.period_start < d.posted_on THEN", "        IF false THEN")),
    ("M31", "the accrual CHECK admits a NULL core version", "E7",
     rep("AND (calculated_by IS NOT NULL) AND (calculated_by ~ '[[:alnum:]]'::text))", "AND (calculated_by ~ '[[:alnum:]]'::text))")),
    ("M32", "a return may leave accrued interest uncredited", "E10",
     rep("        IF b.interest_credited <> b.interest_accrued THEN", "        IF false THEN")),
    ("M33", "a legacy return needs no reason", "E18",
     rep("        IF d.rule_id IS NULL AND b.interest_accrued = 0 AND (NEW.reason IS NULL OR NEW.reason !~ '[[:alnum:]]') THEN", "        IF false THEN")),
    ("M34", "a return may cite a withdrawn or foreign due row", "F11",
     rep("    IF NEW.return_due_id IS NOT NULL AND NOT EXISTS (", "    IF false AND NOT EXISTS (")),
    # ---- the return-due record (section 7)
    ("M35", "a due row may cite another rule", "F5",
     rep("    IF d.rule_id IS DISTINCT FROM NEW.rule_id THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit return due: it cites rule",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit return due: it cites rule")),
    ("M36", "the mandatory-return attributes are not read", "F4",
     rep("    IF v_rule.refund_mandatory IS NOT TRUE\n       OR NOT coalesce(d.instrument = ANY (v_rule.return_mandatory_instruments), false) THEN",
         "    IF v_rule.refund_mandatory IS NOT TRUE THEN")),
    ("M37", "a due row on a refunded deposit", "F12",
     rep("    IF d.status IN ('refunded', 'released') THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit return due: deposit %s is already %s",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit return due: deposit %s is already %s")),
    ("M38", "a return due before posting", "F6",
     rep("    IF NEW.due_on < d.posted_on THEN", "    IF false THEN")),
    ("M39", "two live due rows", "F3",
     rep("    IF v_live IS NOT NULL THEN", "    IF false THEN")),
    ("M40", "a due row may supersede a live row", "F13",
     rep("    IF NEW.supersedes_due_id IS NOT NULL AND NOT EXISTS (", "    IF false AND NOT EXISTS (")),
    ("M41", "a row may be superseded twice", "F15",
     rep("    CONSTRAINT deposit_return_due_supersedes_key UNIQUE (supersedes_due_id),\n", "")),
    ("M42", "a due row needs no evidence", "F1",
     rep("    IF NOT EXISTS (SELECT 1 FROM public.deposit_return_due_evidence e WHERE e.due_id = NEW.id) THEN", "    IF false THEN")),
    ("M43", "evidence of the wrong kind", "F8",
     rep("    IF (v_kind = 'invoice') <> (NEW.invoice_id IS NOT NULL) THEN", "    IF false THEN")),
    ("M44", "evidence from another customer's bill", "F9",
     rep("SELECT 1 FROM public.invoices i WHERE i.id = NEW.invoice_id AND i.customer_id = v_due.customer_id AND i.invoice_date >= v_due.posted_on) THEN",
         "SELECT 1 FROM public.invoices i WHERE i.id = NEW.invoice_id) THEN")),
    ("M45", "evidence from another customer's state change", "F9",
     rep("SELECT 1 FROM public.customer_state_events s WHERE s.id = NEW.customer_state_event_id AND s.customer_id = v_due.customer_id) THEN",
         "SELECT 1 FROM public.customer_state_events s WHERE s.id = NEW.customer_state_event_id) THEN")),
    ("M46", "evidence after its due row's transaction", "X1",
     rep("    IF v_due.recorded_txid IS DISTINCT FROM txid_current() THEN", "    IF false THEN")),
    ("M47", "the due row takes no lock on the deposit", "R1",
     rep("SELECT * INTO d FROM public.deposits x WHERE x.id = NEW.deposit_id AND x.tenant_id = NEW.tenant_id FOR UPDATE;",
         "SELECT * INTO d FROM public.deposits x WHERE x.id = NEW.deposit_id AND x.tenant_id = NEW.tenant_id;")),
    ("M48", "the owed list keeps withdrawn rows", "F14",
     rep("     WHERE NOT EXISTS (SELECT 1 FROM public.deposit_return_due_withdrawals w WHERE w.due_id = r.id)\n       AND d.status IN ('held', 'partial_applied', 'applied');",
         "     WHERE d.status IN ('held', 'partial_applied', 'applied');")),
    ("M49", "the owed list keeps started and finished returns", "F12",
     rep("     WHERE NOT EXISTS (SELECT 1 FROM public.deposit_return_due_withdrawals w WHERE w.due_id = r.id)\n       AND d.status IN ('held', 'partial_applied', 'applied');",
         "     WHERE NOT EXISTS (SELECT 1 FROM public.deposit_return_due_withdrawals w WHERE w.due_id = r.id);")),
    # The patch's own AC-32 tail refuses this one at apply time.
    ("M50", "due rows have no tenant policy", "APPLY",
     rep("CREATE POLICY tenant_isolation ON public.deposit_return_due USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));",
         "CREATE POLICY tenant_isolation ON public.deposit_return_due USING (true);")),
    ("M51", "evidence is not append-only", "F16",
     rep("    FOREACH t IN ARRAY ARRAY['deposit_return_due', 'deposit_return_due_evidence', 'deposit_return_due_withdrawals'] LOOP",
         "    FOREACH t IN ARRAY ARRAY['deposit_return_due', 'deposit_return_due_withdrawals'] LOOP")),
    # ---- the drops (section 9)
    ("M52", "the Texas interest formula survives", "L4",
     rep("DROP FUNCTION IF EXISTS public.deposit_accrual_amount(numeric, numeric, date, date);\n", "")),
]


def sh(cmd, inp=None):
    return subprocess.run(cmd, input=inp, capture_output=True, text=True)


def psql(db, sql, single=False):
    cmd = ["docker", "exec", "-i", "tally-pg", "psql", "-U", "tally", "-d", db, "-v", "ON_ERROR_STOP=1", "-q"]
    if single:
        cmd.append("-1")
    return sh(cmd + ["-f", "-"], sql)


def run_check(check):
    if check == "X1":
        out = sh([str(XTXN), DB])
    elif check in ("R1", "R2"):
        out = sh([str(RACE), DB])
    else:
        out = psql(DB, BATTERY.read_text())
    return out.stdout + out.stderr


def main():
    base = PATCH.read_text()
    only = set(sys.argv[1:])
    missed = 0
    ran = 0
    for mid, what, check, mut in MUTATIONS:
        if only and mid not in only:
            continue
        ran += 1
        for q in (f"DROP DATABASE IF EXISTS {DB}", f"CREATE DATABASE {DB} TEMPLATE tally"):
            sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-qc", q])
        a = psql(DB, "SET search_path = ''; SET check_function_bodies = on;\n" + mut(base), single=True)
        if a.returncode:
            if check == "APPLY":
                print(f"{mid} caught at apply: {what} ({a.stderr.strip().splitlines()[-1][:90]})")
                continue
            print(f"{mid} APPLY-ERROR ({what}): {a.stderr.strip().splitlines()[-1]}")
            missed += 1
            continue
        if check == "APPLY":
            print(f"{mid} MISSED (applied cleanly): {what}")
            missed += 1
            continue
        text = run_check(check)
        # Where the run stopped: the first FAIL or ERROR line, so a catch by an
        # unrelated earlier check is visible rather than silently counted.
        first = next((l for l in text.splitlines() if "FAIL" in l or "ERROR" in l), "")
        first = re.sub(r"^psql:<stdin>:\d+: ", "", first)[:110]
        if re.search(rf"FAIL {check}[a-z]?:", text) or ("ERROR" in text and not re.search(rf"PASS {check}:", text)):
            print(f"{mid} caught at {check}: {what}  [{first}]")
        else:
            print(f"{mid} MISSED ({check} still passes): {what}")
            missed += 1
    sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-qc", f"DROP DATABASE IF EXISTS {DB}"])
    print(f"{ran - missed}/{ran} caught")
    sys.exit(1 if missed else 0)


if __name__ == "__main__":
    main()
