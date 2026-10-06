#!/usr/bin/env python3
"""v5.4.2-15 — prove battery-15 (and X1, R1) CATCH drift, not merely pass.

Each mutation alters a copy of the patch, applies it (strict) to a fresh clone
of `tally`, which must be a -14 BASE (tu.sql 26,049 lines, 9139367a…), and
runs the check that must catch it: a battery check (A-Z), X1
(evidence-txn-15.sh) or R1-R6 (races/due-mutex-15.sh). CAUGHT when that check
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
    # No "rule_id IS NULL" mutation: that refusal in enforce_deposit() is also
    # reached by the rule-key comparison (a deposit's basis is never NULL, a
    # missing rule's is), so removing it changes the message, not the outcome.
    # ---- deposits (section 5)
    ("M02", "the decision CHECK admits a NULL core version", "C2",
     rep("AND (decided_by IS NOT NULL) AND (decided_by ~ '[[:alnum:]]'::text))));", "AND (decided_by ~ '[[:alnum:]]'::text))));")),
    ("M03", "the rule's key is not compared with the deposit's", "C3",
     rep("        IF v_rule.state_code IS DISTINCT FROM NEW.state_code OR v_rule.service_type IS DISTINCT FROM NEW.service_type\n           OR v_rule.customer_class IS DISTINCT FROM NEW.customer_class OR v_rule.basis IS DISTINCT FROM NEW.basis THEN",
         "        IF false THEN")),
    ("M04", "the rule need not be in force on the posting date", "C4",
     rep("IF NOT (daterange(v_rule.effective_from, v_rule.effective_to, '[)') @> NEW.posted_on) THEN", "IF false THEN")),
    ("M05", "a statutory cap of a kind the rule has no part of (or under a rule with none)", "C5",
     rep("        IF NEW.cap_source = 'statute' AND (NOT EXISTS (SELECT 1 FROM public.deposit_rule_cap_parts p\n                                                           WHERE p.rule_id = NEW.rule_id AND p.cap_kind = NEW.cap_basis_kind)\n                                           OR",
         "        IF NEW.cap_source = 'statute' AND (")),
    ("M06", "a capped rule needs no recorded cap", "C5",
     rep("        IF v_rule.cap_combinator <> 'none' AND NEW.cap_amount IS NULL THEN", "        IF false THEN")),
    ("M07", "the insertable flag is not read", "C7",
     rep("        IF v_basis.insertable IS NOT TRUE THEN", "        IF false THEN")),
    ("M08", "rule_id not frozen", "C9",
     rep("OR OLD.rule_id IS DISTINCT FROM NEW.rule_id", "")),
    ("M09", "decided_by not frozen", "C9",
     rep("       OR OLD.decided_by IS DISTINCT FROM NEW.decided_by\n", "")),
    ("M10", "cap_basis_amount not frozen", "C9",
     rep("       OR OLD.cap_basis_amount IS DISTINCT FROM NEW.cap_basis_amount\n", "")),
    ("M53", "cap_source not frozen", "C9b",
     rep("       OR OLD.cap_source IS DISTINCT FROM NEW.cap_source OR OLD.cap_tariff_reference IS DISTINCT FROM NEW.cap_tariff_reference\n", "")),
    ("M54", "a cap need not record its kind and basis", "C5",
     rep("        IF NEW.cap_amount IS NOT NULL\n           AND (NEW.cap_basis_kind IS NULL OR ((NEW.cap_basis_amount IS NULL) <> (NEW.cap_basis_kind = 'fixed_amount'))) THEN",
         "        IF false THEN")),
    ("M55", "the cap-source CHECK admits a NULL source (NULL leg)", "C5f",
     rep("OR ((cap_amount IS NOT NULL) AND (cap_source IS NOT NULL) AND (cap_source = 'statute'::text) AND (cap_tariff_reference IS NULL))",
         "OR ((cap_amount IS NOT NULL) AND (cap_source = 'statute'::text) AND (cap_tariff_reference IS NULL))")),
    ("M56", "a tariff cap needs no provision", "C5f",
     rep("             AND (cap_tariff_reference IS NOT NULL) AND (cap_tariff_reference ~ '[[:alnum:]]'::text))));",
         "             )));")),
    ("M57", "a combined statutory cap need not record what else was held", "C5h",
     rep("                                           OR ((NEW.cap_other_held IS NOT NULL) <> (v_rule.cap_scope = 'combined'))) THEN",
         "                                           ) THEN")),
    ("M58", "the cap ignores what else was held", "C13",
     rep("CHECK (((cap_amount IS NULL) OR ((cap_amount > (0)::numeric) AND (principal <= (cap_amount - coalesce(cap_other_held, (0)::numeric))))));",
         "CHECK (((cap_amount IS NULL) OR ((cap_amount > (0)::numeric) AND (principal <= cap_amount))));")),
    ("M59", "a trigger may be named on any basis, or left out", "C12",
     rep("        IF v_basis.requires_trigger <> (NEW.trigger_basis IS NOT NULL) THEN", "        IF false THEN")),
    ("M60", "a new deposit may carry legacy interest", "C11",
     rep("        IF NEW.legacy_interest_earned IS NOT NULL THEN", "        IF false THEN")),
    ("M61", "the caller's created_at is kept", "C10",
     rep("        NEW.created_at    := now();\n        NEW.recorded_txid := txid_current();\n        SELECT * INTO v_cust", "        NEW.recorded_txid := txid_current();\n        SELECT * INTO v_cust")),
    # ---- the law tables (sections 2-3)
    ("M11", "a rule row may be deleted", "A5",
     rep("    IF TG_OP = 'DELETE' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit rule %s: law rows are never deleted",
         "    IF TG_OP = 'DELETE' THEN\n        RETURN OLD;\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit rule %s: law rows are never deleted")),
    ("M12", "a close may carry another change", "A6",
     rep("    IF OLD.effective_to IS NOT NULL OR NEW.effective_to IS NULL\n       OR (to_jsonb(NEW) - c_close_cols) <> (to_jsonb(OLD) - c_close_cols) THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit rule %s: law rows are never edited",
         "    IF OLD.effective_to IS NOT NULL OR NEW.effective_to IS NULL THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit rule %s: law rows are never edited")),
    ("M13", "no close floor", "Z5",
     rep("    IF v_latest IS NOT NULL AND NEW.effective_to <= v_latest THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit rule %s: it is cited", "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit rule %s: it is cited")),
    ("M14", "the close is not stamped", "Z6",
     rep("    NEW.closed_at := now();\n    NEW.closed_by := session_user;\n    RETURN NEW;\nEND;\n$$;\nCOMMENT ON FUNCTION public.enforce_deposit_rule_history()",
         "    RETURN NEW;\nEND;\n$$;\nCOMMENT ON FUNCTION public.enforce_deposit_rule_history()")),
    ("M15", "return reasons left editable", "A7",
     rep("    FOREACH t IN ARRAY ARRAY['deposit_bases', 'deposit_triggers', 'deposit_customer_classes', 'deposit_waiver_classes', 'deposit_return_reasons',",
         "    FOREACH t IN ARRAY ARRAY['deposit_bases', 'deposit_triggers', 'deposit_customer_classes', 'deposit_waiver_classes',")),
    ("M62", "reach rows left deletable", "A7b",
     rep("                             'deposit_refund_disqualifiers', 'deposit_rule_waiver_reach', 'deposit_rule_refund_disqualifiers',\n",
         "                             'deposit_refund_disqualifiers', 'deposit_rule_refund_disqualifiers',\n")),
    ("M16", "a rule row may overlap another for its key", "A8",
     rep(",\n    CONSTRAINT deposit_rules_no_overlap\n        EXCLUDE USING gist (state_code WITH =, service_type WITH =, customer_class WITH =, basis WITH =,\n                            daterange(effective_from, effective_to, '[)'::text) WITH &&)", "")),
    ("M17", "a fraction cap without its divisor (NULL leg)", "A9",
     rep("AND (cap_divisor IS NOT NULL) AND (cap_divisor > 0)", "AND (cap_divisor > 0)")),
    ("M18", "a minimum hold without retroactivity", "A9",
     rep("                 AND ((interest_min_hold_days IS NULL) = (interest_retroactive IS NULL))\n", "")),
    ("M19", "refund fields on no mandatory return", "A9",
     rep("                 AND (refund_after_count IS NULL) AND (refund_measure IS NULL) AND (refund_max_delinquencies IS NULL)\n                 AND (refund_lookback_quantity IS NULL)",
         "                 AND (refund_lookback_quantity IS NULL)")),
    ("M20", "the application may write rules", "A3",
     rep("REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.deposit_rules FROM tally_app;\nGRANT SELECT ON public.deposit_rules TO tally_app;",
         "GRANT SELECT, INSERT, UPDATE ON public.deposit_rules TO tally_app;")),
    ("M63", "a rule's parts may be added after its transaction", "A10",
     rep("    IF v_rule.recorded_txid IS DISTINCT FROM txid_current() THEN", "    IF false THEN")),
    ("M64", "a reach row may name a trigger for a basis without one", "W5",
     rep("        IF NEW.trigger_code IS NOT NULL AND v_requires_trigger IS NOT TRUE THEN", "        IF false THEN")),
    ("M65", "a disqualifier on a rule with no count-based trigger", "W5",
     rep("        IF v_rule.refund_after_count IS NULL THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('deposit_rule_refund_disqualifiers", "        IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('deposit_rule_refund_disqualifiers")),
    ("M66", "a reach row's state need not be its rule's", "W5",
     rep("        FOREIGN KEY (rule_id, state_code, service_type)\n        REFERENCES public.deposit_rules(id, state_code, service_type),",
         "        FOREIGN KEY (rule_id)\n        REFERENCES public.deposit_rules(id),")),
    ("M67", "a reach effect may carry the wrong figure", "W5",
     rep("             OR ((effect = 'defer'::text) AND (defer_days IS NOT NULL) AND (defer_days > 0) AND (reduce_fraction IS NULL))))\n);",
         "             OR ((effect = 'defer'::text) AND (defer_days IS NOT NULL) AND (defer_days > 0))))\n);")),
    # ---- rates (section 4)
    ("M21", "a published rate may be edited", "B3",
     rep("    IF OLD.effective_to IS NOT NULL OR NEW.effective_to IS NULL\n       OR (to_jsonb(NEW) - c_close_cols) <> (to_jsonb(OLD) - c_close_cols) THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit_interest_rate_law %s: published rates are never edited",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit_interest_rate_law %s: published rates are never edited")),
    ("M22", "the report lists equal rates as differing", "B5",
     rep("       AND u.annual_rate <> l.annual_rate\n", "\n")),
    ("M23", "the report omits the no_utility_rate gap", "B5",
     rep("     WHERE f.first_date IS NULL OR l.effective_from < f.first_date;", "     WHERE false;")),
    ("M24", "the backdating guard ignores state and service", "E17",
     rep("     WHERE e.event_type = 'interest_accrued' AND r.tenant_id = NEW.tenant_id\n       AND r.state_code = NEW.state_code AND r.service_type = NEW.service_type",
         "     WHERE e.event_type = 'interest_accrued' AND r.tenant_id = NEW.tenant_id")),
    ("M68", "the rate insert takes no lock", "R5",
     rep("    PERFORM pg_advisory_xact_lock(public.deposit_rate_lock_key(NEW.tenant_id, NEW.state_code, NEW.service_type));\n", "")),
    ("M69", "the accrual takes no rate lock", "R5",
     rep("        PERFORM pg_advisory_xact_lock_shared(public.deposit_rate_lock_key(v_rate.tenant_id, v_rate.state_code, v_rate.service_type));", "")),
    ("M70", "a rate may be recorded under REPEATABLE READ", "R6",
     rep("    IF current_setting('transaction_isolation') <> 'read committed' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit interest rate rejected",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit interest rate rejected")),
    ("M71", "an accrual may cite another class's rate", "E24",
     rep("           OR NOT coalesce(v_rate.customer_class IS NULL OR v_rate.customer_class = d.customer_class, false) THEN", " THEN")),
    # ---- waivers (section 6)
    ("M25", "a certified class needs no reference", "D1",
     rep("    IF v_class.requires_certification AND (NEW.certification_reference IS NULL OR NEW.certification_reference !~ '[[:alnum:]]') THEN", "    IF false THEN")),
    ("M72", "a tariff ground where the law permits none", "W2",
     rep("        IF NOT EXISTS (SELECT 1 FROM public.deposit_waiver_classes w\n                        WHERE w.state_code = NEW.state_code AND w.service_type = NEW.service_type AND w.tariff_defined) THEN",
         "        IF false THEN")),
    ("M73", "a tariff ground's scope is not checked", "W2",
     rep("        IF (NEW.reaches_bases IS NOT NULL AND EXISTS", "        IF false AND (NEW.reaches_bases IS NOT NULL AND EXISTS")),
    ("M74", "a tariff determination need not name its ground", "W3",
     rep("    IF coalesce(v_class.tariff_defined, false) <> (NEW.tariff_ground_id IS NOT NULL) THEN", "    IF false THEN")),
    ("M75", "a tariff ground need not be in force on the date", "W3",
     rep("           OR NOT coalesce(daterange(v_ground.effective_from, v_ground.effective_to, '[)') @> NEW.determined_on, false) THEN", " THEN")),
    ("M76", "a tariff ground may close under its citations", "W4",
     rep("    SELECT max(d.determined_on) INTO v_latest FROM public.deposit_waiver_determinations d WHERE d.tariff_ground_id = OLD.id;", "    v_latest := NULL;")),
    ("M77", "a tariff ground may be edited", "W4",
     rep("            MESSAGE = format('deposit tariff waiver ground %s: never edited", "            MESSAGE = format('deposit tariff waiver ground %s: never edited")
     if False else rep("    IF OLD.effective_to IS NOT NULL OR NEW.effective_to IS NULL\n       OR (to_jsonb(NEW) - c_close_cols) <> (to_jsonb(OLD) - c_close_cols) THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit tariff waiver ground %s: never edited",
                       "    IF OLD.effective_to IS NOT NULL OR NEW.effective_to IS NULL THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit tariff waiver ground %s: never edited")),
    ("M78", "tariff grounds have no tenant policy", "APPLY",
     rep("CREATE POLICY tenant_isolation ON public.deposit_tariff_waiver_grounds USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));",
         "CREATE POLICY tenant_isolation ON public.deposit_tariff_waiver_grounds USING (true);")),
    # ---- events (section 8)
    ("M26", "an event may cite any rule", "E1",
     rep("    IF NEW.rule_id IS NOT NULL\n       AND NOT public.deposit_rule_citable(", "    IF false\n       AND NOT public.deposit_rule_citable(")),
    ("M79", "a citable rule need only share the key (any date)", "E23",
     rep("                    AND daterange(r.effective_from, r.effective_to, '[)') @> daterange(p_from, p_to, '[]'))))", "                    )))")),
    ("M27", "an accrual may cite another state's rate", "E2",
     rep("        IF v_rate.tenant_id IS DISTINCT FROM d.tenant_id OR v_rate.state_code IS DISTINCT FROM d.state_code\n           OR v_rate.service_type IS DISTINCT FROM d.service_type",
         "        IF v_rate.tenant_id IS DISTINCT FROM d.tenant_id")),
    ("M28", "a rate may apply before it takes effect", "E3",
     rep("        IF v_rate.effective_date > NEW.period_start THEN", "        IF false THEN")),
    ("M29", "rate_applied need not be the row's", "E4",
     rep("        IF NEW.rate_applied <> v_rate.annual_rate THEN", "        IF false THEN")),
    # M30 retired in r2: the least-held check refuses a period starting
    # before posting (nothing is held then), so it has no guard of its own;
    # M84 (no bound on the basis) is caught at E5/E21.
    ("M31", "the accrual CHECK admits a NULL core version", "E7",
     rep("AND (rate_id IS NOT NULL) AND (rule_id IS NOT NULL) AND (calculated_by IS NOT NULL) AND (calculated_by ~ '[[:alnum:]]'::text))",
         "AND (rate_id IS NOT NULL) AND (rule_id IS NOT NULL) AND (calculated_by ~ '[[:alnum:]]'::text))")),
    ("M32", "a return may leave accrued interest uncredited", "E10",
     rep("        IF b.interest_credited <> b.interest_accrued THEN", "        IF false THEN")),
    ("M33", "a legacy return needs no reason", "E18",
     rep("        IF d.rule_id IS NULL AND b.interest_accrued = 0 AND (NEW.reason IS NULL OR NEW.reason !~ '[[:alnum:]]') THEN", "        IF false THEN")),
    ("M80", "a return may be dated inside an accrued period", "E19",
     rep("    IF NEW.event_type IN ('principal_returned', 'refund_initiated', 'refunded', 'released')\n       AND b.accrued_through IS NOT NULL AND NEW.effective_on <= b.accrued_through THEN",
         "    IF false THEN")),
    ("M81", "a partial return may take the whole remainder", "E20",
     rep("        IF NEW.amount <= 0 OR NEW.amount >= b.remainder THEN", "        IF NEW.amount <= 0 OR NEW.amount > b.remainder THEN")),
    ("M82", "the balance ignores partial returns", "E20",
     rep("             - coalesce((SELECT sum(e.amount) FROM public.deposit_events e WHERE e.deposit_id = d.id AND e.event_type IN ('applied_to_balance', 'principal_returned')), 0),",
         "             - coalesce((SELECT sum(e.amount) FROM public.deposit_events e WHERE e.deposit_id = d.id AND e.event_type = 'applied_to_balance'), 0),")),
    # The least-held check also stops interest after the principal was used
    # up (nothing is held then), so -15 r2 dropped the separate exhaustion
    # guard (was M84). Reverting to the old principal bound misses N8b.
    ("M83", "interest on more than was held through the period (the old principal bound)", "N8",
     rep("        IF NEW.principal_basis > v_held THEN", "        IF NEW.principal_basis > d.principal THEN")),
    ("M84", "no bound on the principal basis at all (before posting, after exhaustion, above the principal)", "E5",
     rep("        IF NEW.principal_basis > v_held THEN", "        IF false THEN")),
    ("M85", "a core version on any event", "E22",
     rep("             AND (principal_basis IS NULL) AND (rate_id IS NULL) AND (rule_id IS NULL) AND (calculated_by IS NULL))));",
         "             AND (principal_basis IS NULL) AND (rate_id IS NULL))));")),
    ("M34", "a return may cite a withdrawn or foreign due row", "F11",
     rep("        IF NOT FOUND THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('deposit event rejected: return_due_id %s is not a live due row", "        IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('deposit event rejected: return_due_id %s is not a live due row")),
    # ---- the return-due record (section 7)
    ("M35", "a due row may cite any rule", "F5",
     rep("    IF NOT public.deposit_rule_citable(d.id, NEW.rule_id, NEW.due_on, NEW.due_on) THEN", "    IF false THEN")),
    ("M36", "the mandatory-return attributes are not read", "F4",
     rep("    IF NEW.amount IS NULL AND (v_rule.refund_mandatory IS NOT TRUE\n       OR NOT coalesce(d.instrument = ANY (v_rule.return_mandatory_instruments), false)) THEN",
         "    IF NEW.amount IS NULL AND (v_rule.refund_mandatory IS NOT TRUE) THEN")),
    ("M37", "a due row once the return has started", "F17",
     rep("    IF d.status IN ('refund_pending', 'refunded', 'released') THEN", "    IF d.status IN ('refunded', 'released') THEN")),
    ("M38", "a return due before posting", "F6",
     rep("    IF NEW.due_on < d.posted_on THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit return due: due_on", "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit return due: due_on")),
    ("M39", "two live due rows", "F3",
     rep("    IF v_live IS NOT NULL THEN", "    IF false THEN")),
    ("M40", "a due row may supersede a live row", "F13",
     rep("    IF NEW.supersedes_due_id IS NOT NULL AND NOT EXISTS (", "    IF false AND NOT EXISTS (")),
    ("M41", "a row may be superseded twice", "F15b",
     rep("    CONSTRAINT deposit_return_due_supersedes_key UNIQUE (supersedes_due_id),\n", "")),
    ("M42", "a due row needs no evidence", "F1",
     rep("    IF NOT EXISTS (SELECT 1 FROM public.deposit_return_due_evidence e WHERE e.due_id = NEW.id) THEN", "    IF false THEN")),
    ("M43", "evidence of the wrong kind", "F8",
     rep("    IF v_reason.evidence_kind IS DISTINCT FROM (CASE WHEN NEW.invoice_id IS NOT NULL THEN 'invoice'", "    IF false AND v_reason.evidence_kind IS DISTINCT FROM (CASE WHEN NEW.invoice_id IS NOT NULL THEN 'invoice'")),
    ("M44", "evidence from another customer's bill", "F9",
     rep("SELECT 1 FROM public.invoices i WHERE i.id = NEW.invoice_id AND i.customer_id = v_due.customer_id\n", "SELECT 1 FROM public.invoices i WHERE i.id = NEW.invoice_id\n")),
    ("M45", "evidence from another customer's state change", "F21",
     rep("         WHERE s.id = NEW.customer_state_event_id AND s.customer_id = v_due.customer_id\n", "         WHERE s.id = NEW.customer_state_event_id\n")),
    ("M86", "closure evidence of any status", "F18c",
     rep("           AND s.to_status = ANY (v_reason.qualifying_statuses)\n", "\n")),
    ("M87", "closure evidence from before posting", "F18",
     rep("BETWEEN v_due.posted_on AND v_due.due_on) THEN", "<= v_due.due_on) THEN")),
    ("M88", "a reason the rule does not enable", "F19",
     rep("    IF NOT coalesce((CASE v_reason.enabled_by", "    IF false AND NOT coalesce((CASE v_reason.enabled_by")),
    ("M89", "evidence may carry two subjects", "F20",
     rep("             OR ((invoice_id IS NULL) AND (customer_state_event_id IS NULL) AND rests_on_deposit AND (classification IS NULL)))),",
         "             OR (rests_on_deposit))),")),
    ("M46", "evidence after its due row's transaction", "X1",
     rep("    IF v_due.recorded_txid IS DISTINCT FROM txid_current() THEN", "    IF false THEN")),
    # Without the early FOR UPDATE the row-version UPDATE still serialises two
    # due rows (R1), but the status read before it is stale: a refund that
    # commits while the due row waits goes unseen (R2).
    ("M47", "the due row takes no lock on the deposit", "R2",
     rep("SELECT * INTO d FROM public.deposits x WHERE x.id = NEW.deposit_id AND x.tenant_id = NEW.tenant_id FOR UPDATE;",
         "SELECT * INTO d FROM public.deposits x WHERE x.id = NEW.deposit_id AND x.tenant_id = NEW.tenant_id;")),
    ("M90", "the due row writes no row version (a bare lock)", "R3",
     rep("    UPDATE public.deposits x SET status = x.status WHERE x.id = d.id;\n", "")),
    ("M91", "the withdrawal writes no row version", "R4",
     rep("    UPDATE public.deposits d SET status = d.status WHERE d.id = v_deposit;\n", "")),
    ("M48", "the owed list keeps withdrawn rows", "F14",
     rep("     WHERE public.deposit_return_due_is_live(r.id)\n       AND d.status IN ('held', 'partial_applied', 'applied');",
         "     WHERE d.status IN ('held', 'partial_applied', 'applied');")),
    ("M49", "the owed list keeps started and finished returns", "F12",
     rep("     WHERE public.deposit_return_due_is_live(r.id)\n       AND d.status IN ('held', 'partial_applied', 'applied');",
         "     WHERE public.deposit_return_due_is_live(r.id);")),
    # The patch's own AC-32 tail refuses this one at apply time.
    ("M50", "due rows have no tenant policy", "APPLY",
     rep("CREATE POLICY tenant_isolation ON public.deposit_return_due USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));",
         "CREATE POLICY tenant_isolation ON public.deposit_return_due USING (true);")),
    ("M51", "evidence is not append-only", "F16",
     rep("    FOREACH t IN ARRAY ARRAY['deposit_return_due', 'deposit_return_due_evidence', 'deposit_return_due_withdrawals'] LOOP",
         "    FOREACH t IN ARRAY ARRAY['deposit_return_due', 'deposit_return_due_withdrawals'] LOOP")),
    # ---- review round 2 (D1-D4, I1-I8)
    ("M93", "a cap part on a rule with no cap", "A11",
     rep("        IF v_rule.cap_combinator = 'none' THEN", "        IF false THEN")),
    ("M94", "a cap's parts are not counted at commit", "A11",
     rep("    IF NOT (CASE NEW.cap_combinator WHEN", "    IF false AND NOT (CASE NEW.cap_combinator WHEN")),
    ("M95", "an instalment schedule is not checked at commit", "A12",
     rep("    IF v_inst.n > 0 AND NOT (", "    IF false AND v_inst.n > 0 AND NOT (")),
    ("M96", "a threshold on a basis that names no trigger", "A13",
     rep("    WHEN 'deposit_rule_trigger_thresholds' THEN\n        IF v_requires_trigger IS NOT TRUE THEN", "    WHEN 'deposit_rule_trigger_thresholds' THEN\n        IF false THEN")),
    ("M97", "a usage ratio of 1 or less", "A13",
     rep("(min_ratio > (1)::numeric) AND (min_count IS NULL) AND (window_months IS NULL)))),\n    CONSTRAINT deposit_rule_trigger_thresholds_payment_check",
         "(min_ratio > (0)::numeric) AND (min_count IS NULL) AND (window_months IS NULL)))),\n    CONSTRAINT deposit_rule_trigger_thresholds_payment_check")),
    ("M98", "one class may reach a rule for any trigger and for one (I7)", "A14",
     rep("        IF EXISTS (SELECT 1 FROM public.deposit_rule_waiver_reach x", "        IF false AND EXISTS (SELECT 1 FROM public.deposit_rule_waiver_reach x")),
    ("M99", "a lookback without a delinquency limit (I2)", "A15",
     rep("AND ((refund_lookback_quantity IS NULL) OR ((refund_lookback_quantity > 0) AND (refund_max_delinquencies IS NOT NULL)))",
         "AND ((refund_lookback_quantity IS NULL) OR (refund_lookback_quantity > 0))")),
    ("M100", "cap parts and thresholds left editable", "A7c",
     rep("                             'deposit_rule_cap_parts', 'deposit_rule_trigger_thresholds', 'deposit_rule_instalments'] LOOP",
         "                             'deposit_rule_instalments'] LOOP")),
    ("M101", "a threshold added to a rule after its transaction (the part guard misses the new tables)", "A10",
     rep("    FOREACH t IN ARRAY ARRAY['deposit_rule_waiver_reach', 'deposit_rule_refund_disqualifiers', 'deposit_rule_cap_parts',\n                             'deposit_rule_trigger_thresholds', 'deposit_rule_instalments'] LOOP",
         "    FOREACH t IN ARRAY ARRAY['deposit_rule_waiver_reach', 'deposit_rule_refund_disqualifiers', 'deposit_rule_cap_parts',\n                             'deposit_rule_instalments'] LOOP")),
    ("M102", "a deposit need not cite the threshold its rule sets", "N2",
     rep("        IF v_statute_thr.id IS NOT NULL AND NEW.trigger_threshold_source IS NULL THEN", "        IF false THEN")),
    ("M103", "a statutory threshold of another trigger", "N2",
     rep("            IF v_statute_thr.id IS DISTINCT FROM NEW.trigger_rule_threshold_id THEN", "            IF false THEN")),
    ("M104", "the observed measure need not meet the threshold", "N2",
     rep("        IF v_measure IS NOT NULL AND NOT (NEW.trigger_observed >= v_min", "        IF false AND v_measure IS NOT NULL AND NOT (NEW.trigger_observed >= v_min")),
    ("M105", "an event count need not be whole", "N2",
     rep("                                          AND (v_measure <> 'event_count' OR NEW.trigger_observed = trunc(NEW.trigger_observed))) THEN",
         "                                          ) THEN")),
    ("M106", "a tariff threshold of another trigger", "N3",
     rep("               OR v_tariff_thr.trigger_code IS DISTINCT FROM NEW.trigger_basis\n", "")),
    ("M107", "a tariff threshold not in force on posting", "N3",
     rep("               OR NOT coalesce(daterange(v_tariff_thr.effective_from, v_tariff_thr.effective_to, '[)') @> NEW.posted_on, false) THEN",
         "               THEN")),
    ("M108", "the threshold citation not frozen", "N3",
     rep("       OR OLD.trigger_observed IS DISTINCT FROM NEW.trigger_observed\n", "")),
    ("M109", "the deposit takes no share lock on the tariff threshold (I5 pattern)", "R9",
     rep("             WHERE g.id = NEW.trigger_tariff_threshold_id AND g.tenant_id = NEW.tenant_id\n               FOR SHARE;",
         "             WHERE g.id = NEW.trigger_tariff_threshold_id AND g.tenant_id = NEW.tenant_id;")),
    ("M110", "a tariff threshold may close under REPEATABLE READ", "R10",
     rep("    IF current_setting('transaction_isolation') <> 'read committed' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit tariff trigger threshold %s: a close runs only",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit tariff trigger threshold %s: a close runs only")),
    ("M111", "a tariff threshold may close under its citations", "N16",
     rep("    SELECT max(d.posted_on) INTO v_latest FROM public.deposits d WHERE d.trigger_tariff_threshold_id = OLD.id;", "    v_latest := NULL;")),
    ("M112", "a tariff threshold may be edited", "N16",
     rep("    IF OLD.effective_to IS NOT NULL OR NEW.effective_to IS NULL\n       OR (to_jsonb(NEW) - c_close_cols) <> (to_jsonb(OLD) - c_close_cols) THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit tariff trigger threshold %s: never edited",
         "    IF OLD.effective_to IS NOT NULL OR NEW.effective_to IS NULL THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit tariff trigger threshold %s: never edited")),
    ("M113", "a tariff threshold close is not stamped", "N16",
     rep("    NEW.closed_at := now();\n    BEGIN\n        NEW.closed_by := NULLIF(current_setting('app.user_id', true), '')::uuid;\n    EXCEPTION WHEN OTHERS THEN\n        NEW.closed_by := NULL;\n    END;\n    RETURN NEW;\nEND;\n$$;\nCOMMENT ON FUNCTION public.enforce_deposit_tariff_trigger_threshold()",
         "    RETURN NEW;\nEND;\n$$;\nCOMMENT ON FUNCTION public.enforce_deposit_tariff_trigger_threshold()")),
    # M114 retired: the commit-time count refuses instalments under a rule
    # with no schedule (M115 removes it and is caught at N5).
    ("M115", "instalments need not match the schedule's number", "N5",
     rep("    IF v_n + 1 <> v_rule_n OR NEW.received_at_posting + v_sum <> NEW.principal THEN", "    IF NEW.received_at_posting + v_sum <> NEW.principal THEN")),
    ("M116", "instalments need not sum to the deposit", "N5",
     rep("    IF v_n + 1 <> v_rule_n OR NEW.received_at_posting + v_sum <> NEW.principal THEN", "    IF v_n + 1 <> v_rule_n THEN")),
    ("M117", "an instalment on a deposit received whole", "N6",
     rep("    IF d.received_at_posting IS NULL THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit instalment: deposit %s was received whole", "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit instalment: deposit %s was received whole")),
    ("M118", "an instalment due before posting", "N6",
     rep("    IF NEW.due_on < d.posted_on THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit instalment: due", "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit instalment: due")),
    ("M119", "an instalment added in a later transaction", "X2",
     rep("    IF d.recorded_txid IS DISTINCT FROM txid_current() THEN", "    IF false THEN")),
    ("M120", "the posted event records the principal, not what was received", "N4",
     rep("coalesce(NEW.received_at_posting, NEW.principal)", "NEW.principal")),
    ("M121", "the balance holds the principal, not what was received", "N4",
     rep("           coalesce((SELECT sum(e.amount) FROM public.deposit_events e WHERE e.deposit_id = d.id AND e.event_type IN ('posted', 'instalment_received')), 0)\n",
         "           d.principal\n")),
    # M122 retired: a deposit received whole has nothing left to receive, so
    # the receipt bound (M123) refuses it.
    ("M123", "more received than the deposit required", "N7",
     rep("        IF NEW.amount <= 0 OR NEW.amount > d.principal - coalesce((SELECT sum(e.amount) FROM public.deposit_events e", "        IF NEW.amount <= 0 OR false AND NEW.amount > d.principal - coalesce((SELECT sum(e.amount) FROM public.deposit_events e")),
    ("M124", "a receipt does not reopen an applied deposit", "N7",
     rep("                        WHEN 'instalment_received' THEN CASE WHEN d.status = 'applied' THEN 'partial_applied' ELSE d.status END\n", "")),
    ("M125", "received_at_posting not frozen", "N7",
     rep("       OR OLD.received_at_posting IS DISTINCT FROM NEW.received_at_posting\n", "")),
    ("M126", "an accrual may span a partial return (I3)", "N8",
     rep("             OR (e.event_type = 'principal_returned' AND e.effective_on BETWEEN NEW.period_start AND NEW.period_end));", "             OR false);")),
    ("M127", "an accrual may reach a full return (I3)", "N9",
     rep("           AND ((e.event_type IN ('refund_initiated', 'refunded', 'released') AND e.effective_on <= NEW.period_end)", "           AND (false")),
    ("M128", "interest credited before it was earned (I3)", "N8",
     rep("WHERE e.deposit_id = d.id AND e.event_type = 'interest_accrued' AND e.period_end < NEW.effective_on;", "WHERE e.deposit_id = d.id AND e.event_type = 'interest_accrued';")),
    ("M129", "an accrual for a period not yet ended (I3)", "N8",
     rep("        IF NEW.period_end >= (now() AT TIME ZONE 'UTC')::date THEN", "        IF false THEN")),
    ("M130", "a bill dated after the due date as evidence (I4)", "N10",
     rep("           AND i.invoice_date >= v_due.posted_on AND i.invoice_date <= v_due.due_on) THEN", "           AND i.invoice_date >= v_due.posted_on) THEN")),
    ("M131", "a closure after the due date as evidence (I4)", "N10",
     rep("BETWEEN v_due.posted_on AND v_due.due_on) THEN", ">= v_due.posted_on) THEN")),
    ("M132", "a return settling a due row before it fell due (I4)", "N10",
     rep("        IF NEW.effective_on < v_due.due_on THEN", "        IF false THEN")),
    ("M133", "closure dated by the session's time zone (I8)", "N11",
     rep("           AND (s.effective_at AT TIME ZONE 'UTC')::date BETWEEN", "           AND s.effective_at::date BETWEEN")),
    ("M134", "a partial return due under a rule that returns no excess (D4)", "N12",
     rep("        IF v_rule.refund_excess_over_cap IS NOT TRUE THEN", "        IF false THEN")),
    ("M135", "a partial return of everything held (D4)", "N12",
     rep("        IF NEW.amount >= (SELECT b.remainder FROM public.deposit_balance(d.id) b) THEN", "        IF false THEN")),
    ("M136", "a partial reason on a whole due row, or the reverse (D4)", "N12",
     rep("    IF v_reason.partial IS DISTINCT FROM (v_due.amount IS NOT NULL) THEN", "    IF false THEN")),
    ("M137", "a refund may settle a partial due row (D4)", "N13",
     rep("        IF (NEW.event_type = 'principal_returned') <> (v_due.amount IS NOT NULL)\n           OR (NEW.event_type", "        IF false\n           OR (NEW.event_type")),
    ("M138", "a partial due row settled by another amount (D4)", "N13",
     rep("           OR (NEW.event_type = 'principal_returned' AND NEW.amount <> v_due.amount) THEN", "           THEN")),
    ("M139", "a settled partial due row stays live (D4)", "N13",
     rep("p_due_id)\n       AND NOT EXISTS (SELECT 1 FROM public.deposit_events e WHERE e.return_due_id = p_due_id AND e.event_type = 'principal_returned');", "p_due_id);")),
    ("M140", "a reason need not rest on its rule's measure (I2)", "N14",
     rep("    IF v_reason.requires_measure IS NOT NULL AND v_reason.requires_measure IS DISTINCT FROM v_due.refund_measure THEN", "    IF false THEN")),
    ("M141", "the rate report judges coverage across classes (I6)", "N15",
     rep("                   AND (r.customer_class IS NULL OR r.customer_class = s.cls)) AS first_date", "                   AND true) AS first_date")),
    ("M142", "a determination takes no share lock on its ground (I5)", "R7",
     rep("WHERE g.id = NEW.tariff_ground_id AND g.tenant_id = NEW.tenant_id FOR SHARE;", "WHERE g.id = NEW.tariff_ground_id AND g.tenant_id = NEW.tenant_id;")),
    ("M143", "a ground may close under REPEATABLE READ (I5)", "R8",
     rep("    IF current_setting('transaction_isolation') <> 'read committed' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit tariff waiver ground %s: a close runs only",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('deposit tariff waiver ground %s: a close runs only")),
    ("M144", "the close floor ignores a return's date (I1)", "N17",
     rep("        SELECT coalesce(e.period_end, e.effective_on) FROM public.deposit_events e WHERE e.rule_id = OLD.id", "        SELECT e.period_end FROM public.deposit_events e WHERE e.rule_id = OLD.id")),
    # ---- the drops (section 9)
    ("M52", "the Texas interest formula survives", "L4",
     rep("DROP FUNCTION IF EXISTS public.deposit_accrual_amount(numeric, numeric, date, date);\n", "")),
    ("M92", "-06's basis-name CHECK survives", "L5",
     rep("ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_trigger_basis_required_check;\n", "")),
]


def sh(cmd, inp=None):
    return subprocess.run(cmd, input=inp, capture_output=True, text=True)


def psql(db, sql, single=False):
    cmd = ["docker", "exec", "-i", "tally-pg", "psql", "-U", "tally", "-d", db, "-v", "ON_ERROR_STOP=1", "-q"]
    if single:
        cmd.append("-1")
    return sh(cmd + ["-f", "-"], sql)


def run_check(check):
    if check in ("X1", "X2"):
        out = sh([str(XTXN), DB])
    elif check.startswith("R"):
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
        # A TEMPLATE clone does not copy the database ACL: revoke TEMP again,
        # or the depth fences are open (review r1 A15).
        sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", DB, "-qc", f"REVOKE TEMP ON DATABASE {DB} FROM PUBLIC, tally_app"])
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
    print(f"{ran - missed}/{ran} caught")
    sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-qc", f"DROP DATABASE IF EXISTS {DB}"])
    sys.exit(1 if missed else 0)


if __name__ == "__main__":
    main()
