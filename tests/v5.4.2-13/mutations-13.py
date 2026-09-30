#!/usr/bin/env python3
"""v5.4.2-13 (parity) — prove the battery CATCHES drift, not merely passes.

Each mutation disables one guard in a copy of the patch, applies it to a fresh
clone of `tally` (the -12 build), and runs the battery (or the two-transaction
script). The mutation is CAUGHT when the named check reports FAIL or errors.
A mutation that leaves the named check passing is a hole in the battery.

    python3 tests/v5.4.2-13/mutations-13.py           # all
    python3 tests/v5.4.2-13/mutations-13.py M05 M09   # some
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATCH = ROOT / "sql/v5.4.2-13-backbilling-caps.sql"
BATTERY = ROOT / "tests/v5.4.2-13/battery-13.sql"
TXN = ROOT / "tests/v5.4.2-13/evidence-txn-13.sh"
DB = "a2pm"


def first_stmt(fn):
    """Insert a bypass as the first statement of a trigger function body."""
    def m(s):
        head = f"CREATE OR REPLACE FUNCTION public.{fn}() RETURNS trigger"
        i = s.index(head)
        j = s.index("BEGIN\n", i) + len("BEGIN\n")
        return s[:j] + "    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF; RETURN NEW;\n" + s[j:]
    return m


def rep(old, new):
    def m(s):
        assert old in s, f"mutation anchor not found: {old[:70]!r}"
        return s.replace(old, new, 1)
    return m


# (id, what it disables, the check that must catch it, mutation, runner)
MUTATIONS = [
    ("M01", "rule rows editable (history trigger bypassed)", "C3",
     first_stmt("enforce_backbilling_rule_history"), "battery"),
    ("M02", "overlapping law rows allowed", "C7",
     rep("CONSTRAINT backbilling_rules_no_overlap\n        EXCLUDE USING gist (state_code WITH =, service_type WITH =, customer_class WITH =, cause WITH =,\n                            daterange(effective_from, effective_to, '[)'::text) WITH &&)",
         "CONSTRAINT backbilling_rules_no_overlap CHECK (true)"), "battery"),
    ("M03", "rule class not tied to the state's classes", "C8",
     rep("CONSTRAINT backbilling_rules_class_fkey\n        FOREIGN KEY (state_code, service_type, customer_class)\n        REFERENCES public.backbilling_customer_classes(state_code, service_type, class_code),",
         ""), "battery"),
    ("M04", "rule basis and qualifying outcomes decoupled", "C14",
     rep("    IF v_on_test IS NOT NULL AND v_on_test <> (NEW.qualifying_test_outcomes IS NOT NULL) THEN",
         "    IF false THEN"), "battery"),
    ("M05", "the application may write the law", "C2",
     rep("REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.backbilling_rule_window_terms FROM tally_app;",
         "GRANT INSERT, UPDATE, DELETE ON public.backbilling_rule_window_terms TO tally_app;"), "battery"),
    ("M06", "case record guard bypassed", "E1",
     first_stmt("enforce_meter_correction_case_record"), "battery"),
    # Other guards also refuse editing a frozen case (the freeze and stamp
    # checks); what only this branch does is let a real unfreeze clear its
    # stamps — so the mutation surfaces at H7.
    ("M07", "the frozen-case branch removed", "H7",
     rep("        IF OLD.status = 'frozen' THEN\n            -- Only an unfreeze",
         "        IF OLD.status = 'frozen' AND false THEN\n            -- Only an unfreeze"), "battery"),
    ("M08", "freeze accepts an evaluation of another cause", "H1",
     rep("               OR v_eval.cause IS DISTINCT FROM NEW.cause\n", "\n"), "battery"),
    ("M09", "a withdrawn case may change", "H8",
     rep("        IF OLD.status = 'withdrawn' THEN", "        IF OLD.status = 'withdrawn' AND false THEN"), "battery"),
    ("M10", "a cause change needs no reason", "E7",
     rep("    IF NEW.cause IS DISTINCT FROM OLD.cause\n       AND (NEW.cause_change_reason IS NULL",
         "    IF false AND NEW.cause IS DISTINCT FROM OLD.cause\n       AND (NEW.cause_change_reason IS NULL"), "battery"),
    ("M11", "evidence NULL-leg (field report with no reference)", "E10",
     rep("(coalesce(evidence_field_report_ref, ''::text) ~ '[[:alnum:]]'::text)",
         "(evidence_field_report_ref ~ '[[:alnum:]]'::text)"), "battery"),
    ("M12", "one live case per test dropped", "E13",
     rep("CREATE UNIQUE INDEX IF NOT EXISTS uq_meter_correction_cases_live_test", "CREATE INDEX IF NOT EXISTS uq_meter_correction_cases_live_test"), "battery"),
    ("M13", "the application may write case events", "E15",
     first_stmt("enforce_case_events_written_by_database"), "battery"),
    ("M14", "evaluation may cite a rule for another cause", "F1",
     rep("    IF v_rule.cause IS DISTINCT FROM NEW.cause THEN", "    IF false THEN"), "battery"),
    ("M15", "evaluation stamps are the caller's", "F2",
     rep("        NEW.evaluated_by := NULLIF(current_setting('app.user_id', true), '')::uuid;", "        NULL;"), "battery"),
    ("M16", "evidence may cite a rule for another class", "F6",
     rep("    IF v_rule.customer_class IS DISTINCT FROM NEW.customer_class\n       OR",
         "    IF false AND v_rule.customer_class IS DISTINCT FROM NEW.customer_class\n       OR"), "battery"),
    ("M17", "partial forfeiture may give up the whole", "F5",
     rep("AND (abs(forfeited_amount) < abs(correction_amount))", "AND (abs(forfeited_amount) <= abs(correction_amount))"), "battery"),
    ("M18", "evidence may be added in a later transaction", "X1",
     rep("    IF v_txid IS DISTINCT FROM txid_current() THEN", "    IF false THEN"), "txn"),
    ("M19", "approval of another case's evaluation", "G1",
     rep("    CONSTRAINT meter_correction_approvals_same_case_fkey\n        FOREIGN KEY (evaluation_id, case_id) REFERENCES public.meter_correction_evaluations(id, case_id),\n", ""), "battery"),
    ("M20", "approval stamps are the caller's", "G2",
     first_stmt("enforce_meter_correction_approval_record"), "battery"),
    ("M21", "hold record guard bypassed", "I1",
     first_stmt("enforce_meter_correction_hold_record"), "battery"),
    ("M22", "hold unrecoverable NULL-leg", "I5",
     rep("(coalesce(closure_artifact_ref, ''::text) ~ '[[:alnum:]]'::text)", "(closure_artifact_ref ~ '[[:alnum:]]'::text)"), "battery"),
    ("M23", "a frozen case's test may be superseded", "J1",
     rep("    IF v_case IS NOT NULL THEN", "    IF false THEN"), "battery"),
    ("M24", "evaluations lose tenant isolation", "K5",
     rep("CREATE POLICY tenant_isolation ON public.meter_correction_evaluations USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));",
         "CREATE POLICY tenant_isolation ON public.meter_correction_evaluations USING (true);"), "apply"),
    ("M25", "deployment history guard bypassed", "B1",
     first_stmt("enforce_meter_deployment_history"), "battery"),
    # Review round P1 — one per new guard.
    ("M26", "freeze ignores the direction", "H9",
     rep("               OR v_eval.direction IS DISTINCT FROM NEW.direction\n", "\n"), "battery"),
    ("M27", "freeze ignores the claimed start", "H10",
     rep("               OR v_eval.claimed_from IS DISTINCT FROM NEW.claimed_from\n", "\n"), "battery"),
    ("M28", "freeze ignores the discovering test", "H11",
     rep("               OR v_eval.discovering_test_id IS DISTINCT FROM NEW.discovering_test_id THEN",
         "               OR false THEN"), "battery"),
    ("M29", "a frozen case takes new evaluations", "H12",
     rep("    IF v_case.status IS DISTINCT FROM 'open' THEN", "    IF false THEN"), "battery"),
    ("M30", "a frozen case takes new approvals", "H13",
     rep("    IF v_status IS DISTINCT FROM 'open' THEN", "    IF false THEN"), "battery"),
    ("M31", "a frozen case takes new holds", "H14",
     rep("             WHERE mc.id = NEW.case_id AND mc.tenant_id = NEW.tenant_id FOR SHARE) IS DISTINCT FROM 'open' THEN",
         "             WHERE mc.id = NEW.case_id AND mc.tenant_id = NEW.tenant_id FOR SHARE) IS DISTINCT FROM 'open' AND false THEN"), "battery"),
    ("M32", "window terms may be added to an existing rule", "C15",
     rep("    IF v_txid IS NOT NULL AND v_txid <> txid_current() THEN", "    IF false THEN"), "battery"),
    ("M33", "a cited rule may be closed before its citations", "F13",
     rep("    IF v_latest IS NOT NULL AND NEW.effective_to <= v_latest THEN", "    IF false THEN"), "battery"),
    ("M34", "vocabularies and classes editable", "C16",
     first_stmt("enforce_backbilling_law_immutable"), "battery"),
    ("M35", "a case may rest on another meter's test", "E16",
     rep("       AND NOT EXISTS (SELECT 1 FROM public.meter_tests t WHERE t.id = NEW.discovering_test_id AND t.meter_id = NEW.meter_id) THEN",
         "       AND false THEN"), "battery"),
    ("M36", "a case may cite another meter's removal", "E17",
     rep("       AND NOT EXISTS (SELECT 1 FROM public.meter_deployments d WHERE d.id = NEW.evidence_deployment_id AND d.meter_id = NEW.meter_id) THEN",
         "       AND false THEN"), "battery"),
    ("M37", "an evaluation may name another meter's tests", "F11",
     rep("        AND NOT EXISTS (SELECT 1 FROM public.meter_tests t WHERE t.id = NEW.governing_test_id AND t.meter_id = v_case.meter_id))",
         "        AND false)"), "battery"),
    ("M38", "evidence may cite another state's rule", "F12",
     rep("       OR v_rule.state_code IS DISTINCT FROM v_eval.state_code\n", "\n"), "battery"),
    ("M39", "an evaluation may cite another service's rule", "F14",
     rep("    IF v_rule.service_type IS DISTINCT FROM (SELECT m.service_type FROM public.meters m WHERE m.id = v_case.meter_id) THEN",
         "    IF false THEN"), "battery"),
    ("M40", "a withdrawal may carry other changes", "H15",
     rep("            IF (to_jsonb(NEW) - c_withdraw_cols) <> (to_jsonb(OLD) - c_withdraw_cols) THEN", "            IF false THEN"), "battery"),
    ("M41", "a case's updated_at is the caller's on insert", "E1",
     rep("        NEW.updated_at := now();\n        IF NEW.evidence_kind IS NOT NULL THEN", "        IF NEW.evidence_kind IS NOT NULL THEN"), "battery"),
    ("M42", "any role may close a law row", "C19",
     rep("    IF v_sees_all IS NOT TRUE THEN", "    IF false THEN"), "battery"),
    ("M43", "a quantity on a kind that takes none", "C12",
     rep("    IF v_takes IS NOT NULL AND v_takes <> (NEW.quantity IS NOT NULL) THEN", "    IF false THEN"), "battery"),
    ("M44", "a case's shape no longer follows its basis", "E2",
     rep("    IF v_on_test IS NOT NULL\n       AND NOT", "    IF false\n       AND NOT"), "battery"),
    ("M45", "a close is not stamped", "Z2",
     rep("    NEW.closed_at := now();\n    NEW.closed_by := session_user;", "    NULL;"), "battery"),
]


def sh(cmd, inp=None):
    return subprocess.run(cmd, input=inp, capture_output=True, text=True)


def fresh(sql):
    for q in (f"DROP DATABASE IF EXISTS {DB}", f"CREATE DATABASE {DB} TEMPLATE tally"):
        r = sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-qc", q])
        if r.returncode:
            sys.exit(r.stderr)
    return sh(["docker", "exec", "-i", "tally-pg", "psql", "-U", "tally", "-d", DB,
               "-v", "ON_ERROR_STOP=1", "-q", "-f", "-"], sql)


def run(runner):
    if runner == "txn":
        return sh([str(TXN), DB])
    return sh(["docker", "exec", "-i", "tally-pg", "psql", "-U", "tally", "-d", DB,
               "-v", "ON_ERROR_STOP=1", "-q", "-f", "-"], BATTERY.read_text())


def caught(out, check):
    passed = re.search(rf"PASS {check}:", out)
    failed = re.search(rf"FAIL {check}:", out) or "ERROR" in out
    return failed and not passed


def main():
    want = set(sys.argv[1:])
    base = PATCH.read_text()
    todo = [m for m in MUTATIONS if not want or m[0] in want]
    missed = 0
    for mid, what, check, mut, runner in todo:
        a = fresh(mut(base))
        if runner == "apply":
            # The patch's own AC-32 assertion must refuse to land it.
            ok = a.returncode != 0 and "assert_tenant_isolation_invariants" in a.stderr
            print(f"{mid} {'caught at apply (AC-32 assertion)' if ok else 'MISSED (patch applied)'}: {what}")
            missed += 0 if ok else 1
            continue
        if a.returncode:
            print(f"{mid} APPLY-ERROR ({what}): {a.stderr.strip().splitlines()[-1]}")
            missed += 1
            continue
        r = run(runner)
        out = r.stdout + r.stderr
        if caught(out, check):
            print(f"{mid} caught at {check}: {what}")
        else:
            print(f"{mid} MISSED ({check} still passes): {what}")
            missed += 1
    sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-qc", f"DROP DATABASE IF EXISTS {DB}"])
    print(f"{len(todo) - missed}/{len(todo)} caught")
    sys.exit(1 if missed else 0)


if __name__ == "__main__":
    main()
