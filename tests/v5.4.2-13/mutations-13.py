import subprocess, sys, re, concurrent.futures as cf, os, threading
LOCK=threading.Lock()
# The planted-mutation harness for v5.4.2-13 (48 mutations). Each breaks one
# guard in a copy of the patch, applies it strictly to a fresh clone of
# `tally`, runs battery-13, and prints the last PASS before the first error.
# A mutation is caught when the first failure is the check written for it.
# Usage: python3 tests/v5.4.2-13/mutations-13.py [M01 M13 ...]
# Needs the tally-pg container; writes mutated copies under $MUT_DIR.
import tempfile
HERE=os.path.dirname(os.path.abspath(__file__))
SP=os.environ.get('MUT_DIR') or tempfile.mkdtemp(prefix='mut13-')
os.makedirs(f'{SP}/mut', exist_ok=True)
PATCH=os.path.join(HERE, '..', '..', 'sql', 'v5.4.2-13-backbilling-caps.sql')
BAT=os.path.join(HERE, 'battery-13.sql')
src=open(PATCH).read()
M=[
 ('M01 class-mode platform-only', "IF current_user = 'tally_app'\n       AND NEW.regulatory_class_mode IS DISTINCT FROM", "IF false\n       AND NEW.regulatory_class_mode IS DISTINCT FROM", 'A1'),
 ('M02 tenant_admin grant', "       AND NOT public.session_is_supervisor() THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('user %s: only a supervisor", "       AND false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('user %s: only a supervisor", 'A5'),
 ('M03 history key CHECK', "'cutover_date'::text, 'regulatory_class_mode'::text, 'backbilling_adverse_limit_months'::text]", "'cutover_date'::text, 'regulatory_class_mode'::text]", 'fixtures'),
 ('M04 install_date immutable', "       OR NEW.install_date IS DISTINCT FROM OLD.install_date\n", "\n", 'B1'),
 ('M05 created_at stamped', "        NEW.created_at := now();\n        RETURN NEW;\n    END IF;\n    IF NEW.meter_id", "        RETURN NEW;\n    END IF;\n    IF NEW.meter_id", 'B4'),
 ('M06 removal write-once', "       OR (OLD.removal_reason IS NOT NULL AND NEW.removal_reason IS DISTINCT FROM OLD.removal_reason) THEN", " THEN", 'B3'),
 ('M07 cap table revoke', "REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.backbilling_cap_rules FROM tally_app;", "", 'C1'),
 ('M08 target cause domain', "(backbill_cause = 'rate_misapplication'::text)))", "(backbill_cause = ANY (ARRAY['rate_misapplication'::text, 'meter_error'::text]))))", 'D1'),
 ('M09 increase test', "IF v_prior_charge IS NULL OR v_new_charge <= v_prior_charge THEN", "IF v_prior_charge IS NULL THEN", 'D6'),
 ('M10 units check', "IF NOT public.backbilling_units_match(NEW.replaces_invoice_id, NEW.id) THEN", "IF false THEN", 'D4'),
 ('M11 no-cause increase', "    IF v_t.backbill_cause IS NULL THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('backbilling: invoice %s increases the charge", "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('backbilling: invoice %s increases the charge", 'D3'),
 ('M12 target freeze column', "       AND NEW.backbill_cause     IS NOT DISTINCT FROM OLD.backbill_cause THEN", "       THEN", 'D7'),
 ('M13 anchor = test date', "        IF NEW.anchor_date IS NOT NULL AND NEW.anchor_date <> v_anchor\n", "        IF false AND NEW.anchor_date <> v_anchor\n", 'E2'),
 ('M14 meter_error outcome', "IF NEW.cause = 'meter_error' AND v_test.outcome NOT IN ('fast', 'slow') THEN", "IF false THEN", 'E3'),
 ('M15 non_registering outcome', "IF NEW.cause = 'non_registering_meter' AND v_test.outcome IS DISTINCT FROM 'non_registering' THEN", "IF false THEN", 'E5'),
 ('M16 adverse needs readings', "IF v_direction = 'customer_owes' AND NOT v_test.has_readings THEN", "IF false THEN", 'E6'),
 ('M17 insert fence derived', "           OR NEW.anchor_basis IS NOT NULL OR NEW.direction IS NOT NULL THEN", " THEN", 'E7'),
 ('M18 tamper supervisor', "        IF NOT public.session_is_supervisor() THEN\n            RAISE EXCEPTION USING\n                MESSAGE = 'meter correction case: a finding of tampering_bypass needs a supervisor", "        IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = 'meter correction case: a finding of tampering_bypass needs a supervisor", 'E11'),
 ('M19 tamper deployment meter', "                              AND d.meter_id = NEW.meter_id AND d.removal_reason = 'tamper') THEN", "                              AND d.removal_reason = 'tamper') THEN", 'E12'),
 ('M20 cause change reason', "            IF NEW.cause_change_reason IS NULL\n               OR NEW.cause_change_reason IS NOT DISTINCT FROM OLD.cause_change_reason THEN", "            IF false THEN", 'E13'),
 ('M21 events depth fence', "    IF pg_trigger_depth() < 2 THEN\n        RAISE EXCEPTION USING\n            MESSAGE = 'meter_correction_case_events rows", "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = 'meter_correction_case_events rows", 'E16'),
 ('M22 amounts key set', "    IF v_ids IS DISTINCT FROM (SELECT coalesce(array_agg(k ORDER BY k), ARRAY[]::text[]) FROM jsonb_object_keys(NEW.submitted_amounts) AS k) THEN", "    IF false THEN", 'F11'),
 ('M23 sign check', "        IF (c.direction = 'customer_owed' AND v_amount > 0) OR (c.direction = 'customer_owes' AND v_amount < 0) THEN", "        IF false THEN", 'F13'),
 ('M24 derived columns refused', "    IF v_caller IS NOT NULL THEN", "    IF false THEN", 'F15'),
 ('M25 evidence depth fence', "    IF pg_trigger_depth() < 2 THEN\n        RAISE EXCEPTION USING\n            MESSAGE = 'meter_correction_period_evidence rows", "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = 'meter_correction_period_evidence rows", 'F16'),
 ('M26 straddle forfeits', "            IF v_pwindow IS NOT NULL AND v_start < v_pwindow THEN", "            IF v_pwindow IS NOT NULL AND v_end < v_pwindow THEN", 'F3'),
 ('M27 tenant limit favourable', "        IF v_dir = 'customer_owes' THEN\n            IF v_pwindow", "        IF v_dir <> 'neutral' THEN\n            IF v_pwindow", 'F8'),
 ('M28 late deployment', "       AND d.created_at <= v_fence\n       AND daterange(d.install_date, d.removal_date, '[)') && daterange(v_stat", "       AND daterange(d.install_date, d.removal_date, '[)') && daterange(v_stat", 'F5'),
 ('M29 corroboration', "IF v_dep_id IS NOT NULL AND c.direction = 'customer_owed' AND NOT v_dep_corroborated THEN", "IF false THEN", 'F7c'),
 ('M30 governing test prong', "CASE WHEN v_rule.billable_scope = 'shorter_of_months_or_last_test' THEN g.test_date END,\n                             v_dep_install);", "NULL::date,\n                             v_dep_install);", 'F2'),
 ('M31 R-36 enforced', "    IF e.supervisor_gate_required\n       AND NOT EXISTS", "    IF false\n       AND NOT EXISTS", 'G2'),
 ('M32 approver not opener', "    IF v_user IS NULL OR v_user IS NOT DISTINCT FROM c.opened_by OR v_user IS NOT DISTINCT FROM e.evaluated_by THEN", "    IF v_user IS NULL OR v_user IS NOT DISTINCT FROM e.evaluated_by THEN", 'G4'),
 ('M33 approval current eval', "    IF EXISTS (SELECT 1 FROM public.meter_correction_evaluations v2\n                WHERE v2.case_id = c.id AND v2.evaluation_seq > e.evaluation_seq) THEN", "    IF false THEN", 'G7'),
 ('M34 hold fast only', "    IF c.cause <> 'meter_error' OR c.direction <> 'customer_owed' THEN", "    IF false THEN", 'H1'),
 ('M35 hold unbilled only', "    IF public.meter_correction_range_billed(c.tenant_id, c.meter_id, NEW.range_start, NEW.range_end) THEN", "    IF false THEN", 'H4'),
 ('M36 legacy before cutover', "        IF v_cut IS NULL OR NEW.range_end >= v_cut THEN", "        IF v_cut IS NULL THEN", 'H6'),
 ('M37 under-reach at freeze', "    IF v_gap > 0 THEN", "    IF false THEN", 'H2'),
 ('M38 hold completion', "            IF NOT public.meter_correction_range_fully_billed(OLD.tenant_id, c.meter_id, OLD.range_start, OLD.range_end) THEN", "            IF false THEN", 'H13'),
 ('M39 predecessor acquisition', "           AND a.acquired_on > NEW.range_end\n", "\n", 'H3'),
 ('M40 fingerprint at freeze', "    IF md5(v_now::text) <> e.inputs_fingerprint THEN", "    IF false THEN", 'I5'),
 ('M41 supersession vs frozen', "    IF v_case IS NOT NULL THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('meter test %s is cited", "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('meter test %s is cited", 'I7'),
 ('M42 withdrawal guard', "            IF v_head_outcome = 'fast' THEN", "            IF false THEN", 'I10'),
 ('M44 superseded discoverer', "        IF EXISTS (SELECT 1 FROM public.meter_tests s WHERE s.supersedes_test_id = v_test.id) THEN", "        IF false THEN", 'I12'),
 ('M45 tamper evidence frozen', "    ELSIF NEW.cause = 'tampering_bypass' THEN\n        -- staying in tampering", "    ELSIF false THEN\n        -- staying in tampering", 'E15'),
 ('M46 frozen eval stamped', "        IF NEW.frozen_evaluation_id IS DISTINCT FROM OLD.frozen_evaluation_id\n           OR NEW.frozen_at", "        IF false\n           OR NEW.frozen_at", 'I3'),
 ('M47 case meter fixed', "           OR NEW.meter_id IS DISTINCT FROM OLD.meter_id\n", "\n", 'E17'),
 ('M49 test finding keeps cause', "        IF OLD.cause IN ('meter_error', 'non_registering_meter')\n           AND NEW.cause NOT IN", "        IF false\n           AND NEW.cause NOT IN", 'E20'),
 ('M48 unrecoverable supervisor', "            IF NOT public.session_is_supervisor() THEN\n                RAISE EXCEPTION USING\n                    MESSAGE = format('hold %s: an unrecoverable closure", "            IF false THEN\n                RAISE EXCEPTION USING\n                    MESSAGE = format('hold %s: an unrecoverable closure", 'H11'),
 # ---- review round 1 guards (battery group M)
 ('M50 direction fence first', "        IF NEW.anchor_basis IS DISTINCT FROM OLD.anchor_basis\n           OR NEW.direction IS DISTINCT FROM OLD.direction THEN", "        IF false THEN", 'M1'),
 ('M51 status carries nothing', "        IF NEW.status IS DISTINCT FROM OLD.status AND v_substance_moved THEN", "        IF false THEN", 'I2'),
 ('M52 withdrawal reads head', "            IF v_head_outcome = 'fast' THEN", "            IF v_head_outcome = 'fast' AND NOT EXISTS (SELECT 1 FROM public.meter_tests s WHERE s.supersedes_test_id = OLD.discovering_test_id) THEN", 'M3'),
 ('M53 evaluation refuses corrected', "    IF v_inputs ->> 'discovering_test_superseded_by' IS NOT NULL THEN", "    IF false THEN", 'M4'),
 ('M54 inputs carry supersession', "        'discovering_test_id', c.discovering_test_id, 'discovering_test_superseded_by', v_superseded_by,", "        'discovering_test_id', c.discovering_test_id, 'discovering_test_superseded_by', NULL::uuid,", 'M4'),
 ('M55 no closed deployment insert', "        IF NEW.removal_date IS NOT NULL OR NEW.removal_reason IS NOT NULL THEN", "        IF false THEN", 'M5'),
 ('M56 predecessor into window', "           AND pd.removal_date >= v_stat);", "           );", 'M6'),
 ('M57 completed hold covers nothing', "                        WHERE h.case_id = e.case_id AND h.status <> 'completed'", "                        WHERE h.case_id = e.case_id", 'M7'),
 ('M58 completed hold not exclusive', "    WHERE ((status <> 'completed'::text));", ";", 'M7'),
 ('M59 reissue overlap', "         OR (daterange(i.period_start, i.period_end, '[]') && daterange(NEW.period_start, NEW.period_end, '[]')", "         OR (i.period_start = NEW.period_start AND i.period_end = NEW.period_end", 'M8'),
 ('M60 same-day opposite', "        IF v_test.outcome IN ('fast', 'slow', 'non_registering') AND EXISTS (", "        IF false AND EXISTS (", 'M9'),
 ('M61 zero refused', "        IF c.direction IS NOT NULL AND v_amount = 0", "        IF false AND v_amount = 0", 'M10'),
 ('M62 one live case', "CREATE UNIQUE INDEX IF NOT EXISTS uq_meter_correction_cases_live_test", "CREATE INDEX IF NOT EXISTS uq_meter_correction_cases_live_test", 'M11'),
 ('M63 fast-findings surface', " WHERE t.outcome = 'fast'\n   AND NOT EXISTS (SELECT 1 FROM public.meter_tests s WHERE s.supersedes_test_id = t.id)\n   AND NOT EXISTS (SELECT 1 FROM public.meter_correction_cases mc", " WHERE t.outcome = 'fast'\n   AND NOT EXISTS (SELECT 1 FROM public.meter_correction_cases mc", 'M12'),
]
def run(i, m):
    name, old, new, exp = m
    n = src.count(old)
    if n != 1: return (name, exp, f'SED-MISS count={n}', '')
    db=f'mut{i:02d}'
    path=f'{SP}/mut/{db}.sql'; open(path,'w').write(src.replace(old,new))
    sh=lambda c: subprocess.run(c, shell=True, capture_output=True, text=True)
    sh(f'docker exec tally-pg psql -U tally -d tally -qtA -c "DROP DATABASE IF EXISTS {db}"')
    with LOCK:
        c=sh(f'docker exec tally-pg psql -U tally -d tally -qtA -c "CREATE DATABASE {db} TEMPLATE tally"')
    if c.returncode!=0: return (name, exp, 'CREATE-FAIL', c.stderr.strip()[:120])
    sh(f'docker cp {path} tally-pg:/tmp/{db}.sql')
    a=sh(f"docker exec tally-pg sh -c \"PGOPTIONS='-c search_path= -c check_function_bodies=on' psql -U tally -d {db} -v ON_ERROR_STOP=1 -q -f /tmp/{db}.sql\"")
    if a.returncode!=0:
        sh(f'docker exec tally-pg psql -U tally -d tally -qtA -c "DROP DATABASE {db}"')
        return (name, exp, 'APPLY-FAIL', a.stderr.strip().splitlines()[-1][:160])
    b=sh(f'docker exec tally-pg psql -U tally -d {db} -v ON_ERROR_STOP=1 -f /tmp/b13.sql')
    sh(f'docker exec tally-pg psql -U tally -d tally -qtA -c "DROP DATABASE {db}"')
    lines=(b.stdout+b.stderr).splitlines()
    passes=[re.search(r'PASS (\S+):',l).group(1) for l in lines if 'PASS ' in l]
    err=[l for l in lines if 'ERROR' in l]
    first=err[0][err[0].find('ERROR'):][:150] if err else 'NO ERROR (battery green!)'
    after=passes[-1] if passes else '-'
    return (name, exp, f'last PASS {after}', first)
subprocess.run(f'docker cp {BAT} tally-pg:/tmp/b13.sql', shell=True)
sel=sys.argv[1:] 
todo=[(i,m) for i,m in enumerate(M) if not sel or m[0][:3] in sel]
with cf.ThreadPoolExecutor(6) as ex:
    for r in ex.map(lambda t: run(*t), todo):
        print(' | '.join(r), flush=True)
