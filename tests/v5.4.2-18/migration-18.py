#!/usr/bin/env python3
"""v5.4.2-18 — the migration itself, on clones of a PRE-18 base (default `tally`, the -17 build):

  P1  strict-apply on the real data: every row's document equals one built HERE, apart from the
      patch, from the dump of its old columns and window terms; identity, key, dates, note and
      stamps are unchanged; the old columns, the child table and two vocabularies are gone
  P2  a second application changes nothing (the table is registered; the patch says so)
  P3  extra legacy rows the sixteen do not exercise (closed historical Texas gas rows: a fallback chain
      with priorities, windows in days and billing periods, outcomes listed out of order, a conditional
      enforcement, a delegation) are adopted too, identity and stamps unchanged
  P4  a legacy row that is not Texas gas (nobody ruled on who it binds) stops the patch: the table is
      untouched (columns, rows, no registration, no kind, no facet)
  P5  a row whose source note has no lead clause (so no citation) stops the patch, likewise
  P6  an old-column value the document cannot hold (an outcome the schema does not name, set
      past -13's CHECK) stops the patch, likewise
  P7  the adoption check, called on its own (the patch's functions on a pre-18 clone, the legacy
      table still there): every builder document passes; a document that differs from the old
      columns or window terms in any one key is refused, naming that key

PATCH18=<path> python3 ... runs a different patch text (the mutation runner does).

    python3 tests/v5.4.2-18/migration-18.py [base-db]
"""
from __future__ import annotations

import atexit
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATCH = Path(os.environ.get("PATCH18") or ROOT / "sql/v5.4.2-18-backbilling-rule-terms.sql")
BASE = sys.argv[1] if len(sys.argv) > 1 else "tally"
STRICT = "-c search_path= -c check_function_bodies=on"
fails = 0
RUN = str(os.getpid())


def _cleanup():
    """Drop every clone this run made, however it ends (a crash must not leave databases behind)."""
    names = subprocess.run(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-Atc",
                            f"SELECT datname FROM pg_database WHERE datname ~ '^m18_[a-z]_{RUN}$'"], capture_output=True, text=True).stdout.split()
    for n in names:
        subprocess.run(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-qc", f"DROP DATABASE IF EXISTS {n}"], capture_output=True, text=True)


atexit.register(_cleanup)


def sh(cmd, inp=None):
    return subprocess.run(cmd, input=inp, capture_output=True, text=True)


def psql(db, sql, strict=False, check=True):
    db = nm(db)
    cmd = ["docker", "exec", "-i"] + (["-e", f"PGOPTIONS={STRICT}"] if strict else []) + \
          ["tally-pg", "psql", "-U", "tally", "-d", db, "-v", "ON_ERROR_STOP=1", "-q", "-At", "-f", "-"]
    r = sh(cmd, sql)
    if check and r.returncode != 0:
        raise RuntimeError(r.stderr.strip())
    return r


def nm(name):
    return name if (not name.startswith("m18_") or name.endswith("_" + RUN)) else f"{name}_{RUN}"


def clone(name):
    name = nm(name)
    sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-qc", f"DROP DATABASE IF EXISTS {name}", "-qc", f"CREATE DATABASE {name} TEMPLATE {BASE}"])
    psql(name, f"REVOKE TEMP ON DATABASE {name} FROM PUBLIC; REVOKE TEMP ON DATABASE {name} FROM tally_app; REVOKE TEMP ON DATABASE {name} FROM tally_core;")


def apply(db):
    db = nm(db)
    sh(["docker", "cp", str(PATCH), f"tally-pg:/tmp/m18_{RUN}.sql"])
    return sh(["docker", "exec", "-e", f"PGOPTIONS={STRICT}", "tally-pg", "psql", "-U", "tally", "-d", db, "-v", "ON_ERROR_STOP=1", "-q", "-f", f"/tmp/m18_{RUN}.sql"])


def one(db, sql):
    return psql(db, sql).stdout.strip()


def report(label, ok, detail=""):
    global fails
    print(("PASS " if ok else "FAIL ") + label + (f": {detail}" if detail and not ok else ""))
    if not ok:
        fails += 1


DUMP = """SELECT coalesce(jsonb_agg(jsonb_build_object('row', to_jsonb(b),
          'terms', (SELECT coalesce(jsonb_agg(to_jsonb(w)), '[]') FROM public.backbilling_rule_window_terms w WHERE w.rule_id = b.id))
          ORDER BY b.id), '[]') FROM public.backbilling_rules b"""
IDENTITY = ["id", "state_code", "service_type", "customer_class", "cause", "anchor_basis", "effective_from", "effective_to",
            "source_note", "created_at", "recorded_txid", "closed_at", "closed_by"]


def expected_document(row: dict, terms: list) -> dict:
    """The document a legacy row should become — typed here from the column meanings, not from the patch."""
    note = row["source_note"]
    if note.startswith("16 TAC 7.45 does not reach this class;"):
        return {"governs": "delegated_to_utility", "citation": "16 TAC 7.45", "note": note}
    m = re.match(r"^(.*?)(?: — |;|$)", note, re.S)
    anchor = {"strategy": row["anchor_basis"], "version": 1}
    if row["qualifying_test_outcomes"] is not None:
        anchor["qualifying_outcomes"] = sorted(set(row["qualifying_test_outcomes"]), key=lambda o: o.encode())
    enf = {"strategy": row["enforce_scope"], "version": 1}
    if row["enforce_months"] is not None:
        enf["months"] = row["enforce_months"]
    if row["enforce_condition"] is not None:
        enf["condition"] = row["enforce_condition"]
    windows = {}
    for d in ("adverse", "favourable"):
        ts = []
        for t in sorted((t for t in terms if t["direction"] == d), key=lambda t: t["term_kind"].encode()):
            x = {"kind": t["term_kind"]}
            if t["quantity"] is not None:
                x["quantity"], x["unit"] = t["quantity"], t["unit"]
            if t["priority"] is not None:
                x["priority"] = t["priority"]
            ts.append(x)
        windows[d] = ts
    return {"governs": "law", "citation": m.group(1).strip(), "anchor": anchor,
            "favourable_duty": row["favourable_duty"], "adverse_straddle": row["adverse_straddle"],
            "favourable_straddle": row["favourable_straddle"], "delivery_path": row["delivery_path"],
            "requires_supervisor_evidence": row["requires_supervisor_evidence"], "units_invariant": row["units_invariant"],
            "enforcement": enf, "windows": windows}


def compare(db, dump, label):
    try:
        _compare(db, dump, label)
    except Exception as exc:  # the patch did not apply: the comparison has nothing to read
        report(label, False, f"could not compare: {str(exc)[:160]}")


def _compare(db, dump, label):
    post = json.loads(one(db, "SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id), '[]') FROM public.backbilling_rules b"))
    byid = {p["id"]: p for p in post}
    bad = []
    if len(post) != len(dump):
        bad.append(f"{len(dump)} rows before, {len(post)} after")
    for d in dump:
        row, terms = d["row"], d["terms"]
        p = byid.get(row["id"])
        if p is None:
            bad.append(f"{row['id']} vanished")
            continue
        delegated = row["source_note"].startswith("16 TAC 7.45 does not reach this class;")
        for k in IDENTITY:
            want = None if (k == "anchor_basis" and delegated) else row.get(k)
            if p.get(k) != want:
                bad.append(f"{row['customer_class']}/{row['cause']}: {k} {want!r} -> {p.get(k)!r}")
        exp = expected_document(row, terms)
        if p["terms"] != exp:
            bad.append(f"{row['customer_class']}/{row['cause']}: document {json.dumps(p['terms'], sort_keys=True)} != expected {json.dumps(exp, sort_keys=True)}")
    report(label, not bad, "; ".join(bad[:3]))


def untouched(db, label):
    """The patch aborted: the table is exactly as it was."""
    q = """SELECT (SELECT count(*) FROM pg_attribute WHERE attrelid = 'public.backbilling_rules'::regclass AND attname = 'enforce_scope' AND NOT attisdropped) = 1
         AND to_regclass('public.backbilling_rule_window_terms') IS NOT NULL
         AND to_regclass('public.backbilling_window_term_kinds') IS NOT NULL
         AND NOT EXISTS (SELECT 1 FROM public.rule_tables WHERE table_name = 'public.backbilling_rules'::regclass)
         AND NOT EXISTS (SELECT 1 FROM public.rule_term_schemas WHERE terms_kind = 'backbilling')
         AND NOT EXISTS (SELECT 1 FROM public.rule_term_facets WHERE terms_kind = 'backbilling')
         AND NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.backbilling_rules'::regclass AND attname = 'terms' AND NOT attisdropped)
         AND EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.backbilling_rules'::regclass AND tgname = 'a_enforce_backbilling_rule_history')"""
    report(label, one(db, q) == "t", "the table was changed although the patch aborted")


# ---- the base must be a pre-18 build
if one(BASE, "SELECT to_regclass('public.backbilling_rule_window_terms') IS NOT NULL AND to_regclass('public.rule_tables') IS NOT NULL") != "t":
    print(f"{BASE} is not a -17 build (no legacy window terms, or no -17): this script needs a pre-18 base")
    sys.exit(2)

# ---- P1, P2
clone("m18_a")
dump = json.loads(one("m18_a", DUMP))
r = apply("m18_a")
report("P1a: the patch applies strictly (search_path empty, function bodies checked)", r.returncode == 0, r.stderr.strip()[-300:])
compare("m18_a", dump, "P1b: the sixteen documents equal those built apart from the patch; identity, key, dates, note and stamps unchanged")
gone = one("m18_a", """SELECT NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.backbilling_rules'::regclass AND NOT attisdropped
              AND attname IN ('qualifying_test_outcomes', 'favourable_duty', 'adverse_straddle', 'favourable_straddle', 'delivery_path',
                              'requires_supervisor_evidence', 'units_invariant', 'enforce_scope', 'enforce_months', 'enforce_condition'))
         AND to_regclass('public.backbilling_rule_window_terms') IS NULL AND to_regclass('public.backbilling_window_term_kinds') IS NULL
         AND to_regclass('public.backbilling_enforce_conditions') IS NULL""")
report("P1c: the ten columns, the child table and the two vocabularies are gone", gone == "t")
before = one("m18_a", "SELECT md5(string_agg(to_jsonb(b)::text, '|' ORDER BY b.id)) FROM public.backbilling_rules b")
r = apply("m18_a")
after = one("m18_a", "SELECT md5(string_agg(to_jsonb(b)::text, '|' ORDER BY b.id)) FROM public.backbilling_rules b")
report("P2: a second application changes nothing and says so", r.returncode == 0 and "nothing to do" in r.stderr and before == after, r.stderr.strip()[-200:])

# ---- P3 extra legacy rows (historical, closed or closing, Texas gas)
clone("m18_b")
psql("m18_b", """
BEGIN;
INSERT INTO public.backbilling_rules (id, state_code, service_type, customer_class, cause, anchor_basis, qualifying_test_outcomes, favourable_duty,
   adverse_straddle, favourable_straddle, delivery_path, requires_supervisor_evidence, units_invariant, enforce_scope, enforce_months, enforce_condition,
   effective_from, effective_to, source_note)
VALUES ('00000000-0000-4000-8000-0000000018e1', 'TX', 'gas', 'protected', 'meter_error', 'test_date', ARRAY['slow', 'fast', 'non_registering'], 'mandatory', 'prorate_days', 'prorate_days',
   'adjustment', false, false, 'conditional', NULL, 'read_beyond_utility_control', DATE '1990-01-01', DATE '1995-01-01',
   'A historical chain row; from when the error is known to have begun, otherwise half since the last test'),
  ('00000000-0000-4000-8000-0000000018e2', 'TX', 'gas', 'protected', 'crossed_meters', 'discovery_date', NULL, 'mandatory', 'include_whole', 'include_whole',
   'reissue', true, true, 'months', 9, NULL, DATE '1990-01-01', DATE '2000-01-01', 'A historical days row — ninety days'),
  ('00000000-0000-4000-8000-0000000018e3', 'TX', 'gas', 'protected', 'unbilled_service', 'discovery_date', NULL, 'permitted', 'forfeit_whole', 'prorate_days',
   'unruled', false, false, 'uncapped', NULL, NULL, DATE '1990-01-01', DATE '2001-01-01', 'A historical billing-periods row; two billing periods'),
  ('00000000-0000-4000-8000-0000000018e4', 'TX', 'gas', 'unprotected', 'meter_error', 'test_date', ARRAY['non_registering', 'slow', 'fast'], 'permitted', 'include_whole', 'include_whole',
   'adjustment', false, false, 'uncapped', NULL, NULL, DATE '1990-01-01', DATE '2000-01-01',
   '16 TAC 7.45 does not reach this class; a historical delegation');
INSERT INTO public.backbilling_rule_window_terms (rule_id, direction, term_kind, quantity, unit, priority) VALUES
  ('00000000-0000-4000-8000-0000000018e1', 'adverse', 'claimed_start', NULL, NULL, 1),
  ('00000000-0000-4000-8000-0000000018e1', 'adverse', 'half_since_last_test', NULL, NULL, 2),
  ('00000000-0000-4000-8000-0000000018e1', 'adverse', 'before_anchor', 12, 'months', NULL),
  ('00000000-0000-4000-8000-0000000018e1', 'favourable', 'before_anchor', 36, 'months', NULL),
  ('00000000-0000-4000-8000-0000000018e1', 'favourable', 'service_start', NULL, NULL, NULL),
  ('00000000-0000-4000-8000-0000000018e2', 'adverse', 'before_anchor', 90, 'days', NULL),
  ('00000000-0000-4000-8000-0000000018e2', 'adverse', 'last_test_accurate', NULL, NULL, NULL),
  ('00000000-0000-4000-8000-0000000018e3', 'adverse', 'before_anchor', 2, 'billing_periods', 3);
COMMIT;
-- a row closed before the migration, with its stamps (as a close would have left them)
ALTER TABLE public.backbilling_rules DISABLE TRIGGER a_enforce_backbilling_rule_history;
UPDATE public.backbilling_rules SET closed_at = TIMESTAMPTZ '2001-01-02 09:00+00', closed_by = 'a_platform_closer' WHERE id = '00000000-0000-4000-8000-0000000018e3';
ALTER TABLE public.backbilling_rules ENABLE ALWAYS TRIGGER a_enforce_backbilling_rule_history;
""")
dump = json.loads(one("m18_b", DUMP))
r = apply("m18_b")
report("P3a: sixteen rows and four historical ones (chains, days, billing periods, unsorted outcomes, conditional, a delegation, one closed) apply", r.returncode == 0, r.stderr.strip()[-300:])
compare("m18_b", dump, "P3b: every document equals the one built apart from the patch; the closed row's stamps are unchanged")
closed = one("m18_b", "SELECT closed_at IS NOT NULL AND closed_by = 'a_platform_closer' AND effective_to = DATE '2001-01-01' FROM public.backbilling_rules WHERE id = '00000000-0000-4000-8000-0000000018e3'")
report("P3c: the row closed before the migration is still closed, by whom it was closed", closed == "t")

# ---- P4-P6 aborts
clone("m18_c")
psql("m18_c", """
INSERT INTO public.backbilling_customer_classes (state_code, service_type, class_code, description, source_note) VALUES ('ZZ', 'gas', 'protected', 'ZZ', 'ZZ 1');
INSERT INTO public.backbilling_rules (state_code, service_type, customer_class, cause, anchor_basis, favourable_duty, adverse_straddle, favourable_straddle,
   delivery_path, requires_supervisor_evidence, units_invariant, enforce_scope, effective_from, source_note)
VALUES ('ZZ', 'gas', 'protected', 'crossed_meters', 'discovery_date', 'permitted', 'include_whole', 'include_whole', 'unruled', false, false, 'never', DATE '2020-01-01', 'a row of a state nobody ruled on');
""")
r = apply("m18_c")
report("P4a: a legacy row that is not Texas gas stops the patch, naming it", r.returncode != 0 and "other than Texas gas" in r.stderr and "ZZ gas protected crossed_meters" in r.stderr, r.stderr.strip()[-300:])
untouched("m18_c", "P4b: … and the table is exactly as it was")

clone("m18_d")
psql("m18_d", """
ALTER TABLE public.backbilling_rules DISABLE TRIGGER a_enforce_backbilling_rule_history;
UPDATE public.backbilling_rules SET source_note = ' — a note that opens without a clause' WHERE customer_class = 'protected' AND cause = 'crossed_meters';
ALTER TABLE public.backbilling_rules ENABLE ALWAYS TRIGGER a_enforce_backbilling_rule_history;
""")
r = apply("m18_d")
report("P5a: a source note with no lead clause (no citation) stops the patch", r.returncode != 0 and "/citation" in r.stderr, r.stderr.strip()[-300:])
untouched("m18_d", "P5b: … and the table is exactly as it was")

clone("m18_e")
psql("m18_e", """
ALTER TABLE public.backbilling_rules DISABLE TRIGGER a_enforce_backbilling_rule_history;
ALTER TABLE public.backbilling_rules DROP CONSTRAINT backbilling_rules_qualifying_outcomes_check;
UPDATE public.backbilling_rules SET qualifying_test_outcomes = ARRAY['fast', 'sideways'] WHERE customer_class = 'protected' AND cause = 'meter_error';
ALTER TABLE public.backbilling_rules ENABLE ALWAYS TRIGGER a_enforce_backbilling_rule_history;
""")
r = apply("m18_e")
report("P6a: an outcome the schema does not name, past -13's CHECK, stops the patch (by the schema, or first by the unprotected twin that no longer matches)", r.returncode != 0 and ('"sideways" is not one of' in r.stderr or "facts about its cause" in r.stderr), r.stderr.strip()[-300:])
untouched("m18_e", "P6b: … and the table is exactly as it was")

# ---- P8-P10 the r4 review's reproductions (Codex): valid under -13, once refused or lost by -18
COPY = """INSERT INTO public.backbilling_rules (id, state_code, service_type, customer_class, cause, anchor_basis, qualifying_test_outcomes, favourable_duty, adverse_straddle, favourable_straddle,
   delivery_path, requires_supervisor_evidence, units_invariant, enforce_scope, enforce_months, enforce_condition, effective_from, effective_to, source_note)
SELECT '{id}', state_code, service_type, customer_class, cause, {anchor}, qualifying_test_outcomes, favourable_duty, adverse_straddle, favourable_straddle,
   delivery_path, requires_supervisor_evidence, units_invariant, enforce_scope, enforce_months, enforce_condition, DATE '1800-01-01', DATE '1801-01-01', source_note
FROM public.backbilling_rules WHERE customer_class = '{cls}' AND cause = 'rate_misapplication' ORDER BY effective_from LIMIT 1;
"""
clone("m18_g")
psql("m18_g", "BEGIN;\n" + COPY.format(id="00000000-0000-4000-8000-000000001801", anchor="anchor_basis", cls="protected") + """
INSERT INTO public.backbilling_rule_window_terms(rule_id, direction, term_kind, priority) VALUES ('00000000-0000-4000-8000-000000001801', 'adverse', 'claimed_start', 9);
COMMIT;
""")
dump = json.loads(one("m18_g", DUMP))
r = apply("m18_g")
report("P8a: a window term at priority 9 (valid under -13) is adopted", r.returncode == 0, r.stderr.strip()[-300:])
compare("m18_g", dump, "P8b: … and its document says priority 9")

clone("m18_h")
psql("m18_h", """
INSERT INTO public.backbilling_rules (id, state_code, service_type, customer_class, cause, anchor_basis, qualifying_test_outcomes, favourable_duty, adverse_straddle, favourable_straddle,
   delivery_path, requires_supervisor_evidence, units_invariant, enforce_scope, effective_from, effective_to, source_note)
VALUES ('00000000-0000-4000-8000-000000001803', 'TX', 'gas', 'protected', 'meter_error', 'test_date', ARRAY['fast', 'fast'], 'mandatory', 'forfeit_whole', 'forfeit_whole',
   'adjustment', false, false, 'never', DATE '1800-01-01', DATE '1801-01-01', 'A historical row naming an outcome twice'),
  ('00000000-0000-4000-8000-000000001804', 'TX', 'gas', 'unprotected', 'meter_error', 'test_date', ARRAY['fast'], 'permitted', 'include_whole', 'include_whole',
   'adjustment', false, false, 'uncapped', DATE '1800-01-01', DATE '1801-01-01', '16 TAC 7.45 does not reach this class; its twin names an outcome twice'),
  ('00000000-0000-4000-8000-000000001805', 'TX', 'gas', 'protected', 'crossed_meters', 'test_date', ARRAY['slow'], 'mandatory', 'forfeit_whole', 'forfeit_whole',
   'adjustment', false, false, 'never', DATE '1800-01-01', DATE '1801-01-01', 'A historical row'),
  ('00000000-0000-4000-8000-000000001806', 'TX', 'gas', 'unprotected', 'crossed_meters', 'test_date', ARRAY['slow', 'slow'], 'permitted', 'include_whole', 'include_whole',
   'adjustment', false, false, 'uncapped', DATE '1800-01-01', DATE '1801-01-01', '16 TAC 7.45 does not reach this class; it names an outcome twice');
""")
dump = json.loads(one("m18_h", DUMP))
r = apply("m18_h")
report("P9a: an outcome listed twice (valid under -13) is adopted", r.returncode == 0, r.stderr.strip()[-300:])
compare("m18_h", dump, "P9b: … and its document names it once")

clone("m18_i")
psql("m18_i", """
INSERT INTO public.backbilling_anchor_bases(basis_code, rests_on_test, description) VALUES ('notice_date', false, 'The notice date, distinct from discovery');
""" + COPY.format(id="00000000-0000-4000-8000-000000001801", anchor="anchor_basis", cls="protected")
    + COPY.format(id="00000000-0000-4000-8000-000000001802", anchor="'notice_date'", cls="unprotected"))
r = apply("m18_i")
report("P10a: a delegation whose anchor differs from its protected twin's stops the patch, naming the row", r.returncode != 0 and "anchor" in r.stderr and "00000000-0000-4000-8000-000000001802" in r.stderr, r.stderr.strip()[-300:])
untouched("m18_i", "P10b: … and the table is exactly as it was")

# ---- P11 a concurrent writer cannot slip a row past the pre-flight (Codex r5 should-fix)
import time
clone("m18_j")
psql("m18_j", "INSERT INTO public.backbilling_anchor_bases(basis_code, rests_on_test, description) VALUES ('notice_date', false, 'The notice date, distinct from discovery');\n"
     + COPY.format(id="00000000-0000-4000-8000-000000001801", anchor="anchor_basis", cls="protected"))
writer_sql = ("BEGIN;\n" + COPY.format(id="00000000-0000-4000-8000-000000001802", anchor="'notice_date'", cls="unprotected") + "SELECT pg_sleep(6);\nCOMMIT;\n")
writer = subprocess.Popen(["docker", "exec", "-i", "tally-pg", "psql", "-U", "tally", "-d", nm("m18_j"), "-v", "ON_ERROR_STOP=1", "-q", "-f", "-"],
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
writer.stdin.write(writer_sql)
writer.stdin.close()


def activity(where):
    return sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-At", "-c",
               f"SELECT count(*) FROM pg_stat_activity WHERE datname = '{nm('m18_j')}' AND {where}"]).stdout.strip()


def wait_for(where, seconds=20):
    end = time.time() + seconds
    while time.time() < end:
        if activity(where) not in ("", "0"):
            return True
        time.sleep(0.2)
    return False


held = wait_for("query LIKE '%pg_sleep(6)%' AND state = 'active'")   # the writer has inserted and holds its row, uncommitted
sh(["docker", "cp", str(PATCH), f"tally-pg:/tmp/m18_{RUN}.sql"])
mig = subprocess.Popen(["docker", "exec", "-e", f"PGOPTIONS={STRICT}", "tally-pg", "psql", "-U", "tally", "-d", nm("m18_j"), "-v", "ON_ERROR_STOP=1", "-q", "-f", f"/tmp/m18_{RUN}.sql"],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
waited = held and wait_for("wait_event_type = 'Lock' AND query LIKE '%DO $migration$%' OR wait_event_type = 'Lock' AND query LIKE '%LOCK TABLE%'")
out, err = mig.communicate()
writer.wait()
writer_err = writer.stderr.read()
report("P11-setup: the writer held its row while the patch waited on a lock (so the race was really exercised) and the writer itself succeeded",
       held and waited and writer.returncode == 0, f"held={held} waited={waited} writer rc={writer.returncode} {writer_err.strip()[-120:]}")
report("P11a: a delegation committed by another session while the patch runs is seen, and its differing anchor stops the patch",
       mig.returncode != 0 and "differ from their protected twin" in err and "00000000-0000-4000-8000-000000001802" in err, err.strip()[-300:])
untouched("m18_j", "P11b: … and the table is exactly as the writer left it")

# ---- P7 the adoption check on its own
clone("m18_f")
psql("m18_f", """
BEGIN;
INSERT INTO public.backbilling_rules (id, state_code, service_type, customer_class, cause, anchor_basis, qualifying_test_outcomes, favourable_duty, adverse_straddle, favourable_straddle,
   delivery_path, requires_supervisor_evidence, units_invariant, enforce_scope, effective_from, effective_to, source_note)
VALUES ('00000000-0000-4000-8000-0000000018f1', 'TX', 'gas', 'protected', 'crossed_meters', 'test_date', ARRAY['slow', 'fast'], 'mandatory', 'prorate_days', 'prorate_days',
   'unruled', false, false, 'never', DATE '1990-01-01', DATE '1995-01-01', 'A historical chain row');
INSERT INTO public.backbilling_rules (id, state_code, service_type, customer_class, cause, anchor_basis, favourable_duty, adverse_straddle, favourable_straddle,
   delivery_path, requires_supervisor_evidence, units_invariant, enforce_scope, effective_from, effective_to, source_note)
VALUES ('00000000-0000-4000-8000-0000000018f2', 'TX', 'gas', 'unprotected', 'crossed_meters', 'discovery_date', 'permitted', 'include_whole', 'include_whole',
   'unruled', false, false, 'uncapped', DATE '1990-01-01', DATE '1995-01-01', '16 TAC 7.45 does not reach this class; a delegation that kept a window');
INSERT INTO public.backbilling_rule_window_terms (rule_id, direction, term_kind, quantity, unit, priority) VALUES
  ('00000000-0000-4000-8000-0000000018f1', 'adverse', 'claimed_start', NULL, NULL, 1),
  ('00000000-0000-4000-8000-0000000018f1', 'adverse', 'half_since_last_test', NULL, NULL, 2),
  ('00000000-0000-4000-8000-0000000018f2', 'adverse', 'last_test_accurate', NULL, NULL, NULL);
COMMIT;
""")
text = PATCH.read_text()
prefix = text[:text.index("DO $migration$")]
r = psql("m18_f", prefix, check=False)
report("P7-setup: the hook functions and the builder load on a pre-18 clone", r.returncode == 0, r.stderr.strip()[-200:])
rows = json.loads(one("m18_f", """SELECT jsonb_agg(jsonb_build_object('row', to_jsonb(b) || jsonb_build_object('terms', public.backbilling_rule_legacy_document(b.id)))
                                         ORDER BY b.customer_class, b.cause, b.effective_from) FROM public.backbilling_rules b"""))


def shaped(row):
    """The row as the template hands it to the check: the facet already derived from the document."""
    row = json.loads(json.dumps(row))
    t = row["terms"]
    row["anchor_basis"] = t.get("anchor", {}).get("strategy") if t.get("governs") == "law" else None
    return row


by = {(x["row"]["customer_class"], x["row"]["cause"], x["row"]["effective_from"]): shaped(x["row"]) for x in rows}


def check(row):
    return psql("m18_f", f"SELECT public.backbilling_rule_adoption_check({sql_lit(json.dumps(row))}::jsonb)", check=False)


def sql_lit(t):
    return "'" + t.replace("'", "''") + "'"


WINDOWED = "00000000-0000-4000-8000-0000000018f2"
good = [check(shaped(x["row"])).returncode == 0 for x in rows if x["row"]["id"] != WINDOWED]
report("P7a: the document built from each of the sixteen rows (and a chain row), in the shape the template passes, passes the adoption check", all(good) and len(good) == 17, f"{good.count(False)} refused")


def mut(label, key, edit, phrase, row_edit=None):
    row = json.loads(json.dumps(by[key]))
    edit(row["terms"])
    if row_edit:
        row_edit(row)
    r = check(row)
    report(label, r.returncode != 0 and phrase in r.stderr, (r.stderr.strip()[-220:] or "accepted"))


D = "2004-07-12"
M = ("protected", "meter_error", D)
CH = ("protected", "crossed_meters", "1990-01-01")
UP = ("unprotected", "meter_error", D)
mut("P7b: a different favourable duty", M, lambda t: t.__setitem__("favourable_duty", "permitted"), "favourable_duty")
mut("P7c: a different adverse straddle", M, lambda t: t.__setitem__("adverse_straddle", "include_whole"), "adverse_straddle")
mut("P7d: a different favourable straddle", M, lambda t: t.__setitem__("favourable_straddle", "prorate_days"), "favourable_straddle")
mut("P7e: a different delivery path", M, lambda t: t.__setitem__("delivery_path", "reissue"), "delivery_path")
mut("P7f: supervisor evidence flipped", ("protected", "tampering_bypass", D), lambda t: t.__setitem__("requires_supervisor_evidence", False), "requires_supervisor_evidence")
mut("P7g: units invariance flipped", ("protected", "rate_misapplication", D), lambda t: t.__setitem__("units_invariant", False), "units_invariant")
mut("P7h: another citation", M, lambda t: t.__setitem__("citation", "16 TAC 7.45(7)(B)(v)(II)"), "the document cites")
mut("P7i: another anchor strategy (the outcomes go with it)", M, lambda t: t.__setitem__("anchor", {"strategy": "discovery_date", "version": 1}), "qualifying outcomes")
mut("P7j: another anchor version", M, lambda t: t["anchor"].__setitem__("version", 2), "the document anchors on")
mut("P7k: other qualifying outcomes", M, lambda t: t["anchor"].__setitem__("qualifying_outcomes", ["fast"]), "qualifying outcomes")
mut("P7l: qualifying outcomes dropped", M, lambda t: t["anchor"].pop("qualifying_outcomes"), "qualifying outcomes")
mut("P7m: outcomes where the old column has none", ("protected", "billing_constant_error", D), lambda t: t["anchor"].__setitem__("qualifying_outcomes", ["fast"]), "qualifying outcomes")
mut("P7n: another enforcement strategy", ("protected", "billing_constant_error", D), lambda t: t.__setitem__("enforcement", {"strategy": "uncapped", "version": 1}), "the document enforces")
mut("P7o: another month count", ("protected", "rate_misapplication", D), lambda t: t["enforcement"].__setitem__("months", 7), "the document enforces")
mut("P7p: another enforcement condition", ("protected", "estimation_catchup", D), lambda t: t["enforcement"].__setitem__("condition", "other"), "the document enforces")
mut("P7q: another enforcement version", ("protected", "billing_constant_error", D), lambda t: t["enforcement"].__setitem__("version", 2), "the document enforces")
mut("P7r: an adverse term missing", M, lambda t: t["windows"]["adverse"].pop(), "adverse window")
mut("P7s: a favourable quantity changed", M, lambda t: t["windows"]["favourable"][0].__setitem__("quantity", 7), "favourable window")
mut("P7t: a term added where the old rows have none", ("protected", "crossed_meters", D), lambda t: t["windows"]["adverse"].append({"kind": "service_start"}), "adverse window")
mut("P7u: a priority where the old row has none", M, lambda t: t["windows"]["adverse"][0].__setitem__("priority", 1), "adverse window")
mut("P7v: the directions swapped", ("protected", "non_registering_meter", D), lambda t: t["windows"].update({"adverse": [], "favourable": t["windows"]["adverse"]}), "window")
mut("P7x: a legacy priority the document leaves out", CH, lambda t: [x.pop("priority", None) for x in t["windows"]["adverse"]], "adverse window")
mut("P7w: a delegation for a row whose note does not say 7.45 stops short of it", M, lambda t: (t.clear(), t.update({"governs": "delegated_to_utility", "citation": "x"})), "is law, not a delegation")
mut("P7y: a law document for a row whose note says 7.45 does not reach it", UP, lambda t: (t.clear(), t.update(json.loads(json.dumps(by[M]["terms"])))), "it is a delegation to the utility, not law")
mut("P7z: a delegation citing another clause", UP, lambda t: t.__setitem__("citation", "16 TAC 7.46"), "carries the source note whole")
mut("P7aa: a delegation with another note", UP, lambda t: t.__setitem__("note", "something else"), "carries the source note whole")
mut("P7ab: a delegation over old columns that claimed a cap", UP, lambda t: None, "must claim nothing", lambda r: r.__setitem__("enforce_scope", "never"))
mut("P7ac: … or a straddle", UP, lambda t: None, "must claim nothing", lambda r: r.__setitem__("adverse_straddle", "forfeit_whole"))
mut("P7ad: … or a duty", UP, lambda t: None, "must claim nothing", lambda r: r.__setitem__("favourable_duty", "mandatory"))
mut("P7ae: … or supervisor evidence", UP, lambda t: None, "must claim nothing", lambda r: r.__setitem__("requires_supervisor_evidence", True))
r = check(shaped(next(x["row"] for x in rows if x["row"]["id"] == WINDOWED)))
report("P7ag: … or window terms", r.returncode != 0 and "must claim nothing" in r.stderr, r.stderr.strip()[-200:] or "accepted")
mut("P7ah: a delegation over a cause whose units flag differs from the protected row's", UP, lambda t: None, "facts about its cause", lambda r: r.__setitem__("units_invariant", True))
mut("P7ai: … or whose delivery path differs", UP, lambda t: None, "facts about its cause", lambda r: r.__setitem__("delivery_path", "reissue"))
mut("P7aj: … or whose outcomes differ", UP, lambda t: None, "facts about its cause", lambda r: r.__setitem__("qualifying_test_outcomes", ["fast"]))
mut("P7ak: a note that does not say 7.45 does not reach it, on the unprotected class", UP, lambda t: (t.clear(), t.update(json.loads(json.dumps(by[M]["terms"])))), "the note and the class must agree", lambda r: r.__setitem__("source_note", "a reworded note; ordinary limitations law"))
mut("P7al: the note that says it, on the protected class", M, lambda t: None, "the note and the class must agree", lambda r: r.__setitem__("source_note", "16 TAC 7.45 does not reach this class; but the class is protected"))
mut("P7am: a delegation with no protected row of its cause in force over its dates has nothing to be compared with", UP, lambda t: None, "nothing to be compared with",
    lambda r: r.update({"effective_from": "1980-01-01", "effective_to": "1981-01-01"}))
r = check({**json.loads(json.dumps(by[UP])), "effective_from": "2010-01-01"})
report("P7an: … but a protected row of the same cause that merely overlaps (it began on another day) is its twin", r.returncode == 0, r.stderr.strip()[-200:])
mut("P7af: unsorted outcomes where the old column is unsorted still equal as a set; a different set does not", CH, lambda t: t["anchor"].__setitem__("qualifying_outcomes", ["fast", "non_registering"]), "qualifying outcomes")

print("migration-18:", "all pass" if fails == 0 else f"{fails} FAILURE(S)")
sys.exit(1 if fails else 0)
