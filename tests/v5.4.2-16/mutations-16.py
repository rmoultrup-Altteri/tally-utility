#!/usr/bin/env python3
"""v5.4.2-16 — prove battery-16 and the race script CATCH drift, not merely pass.

Each mutation alters a copy of the patch, applies it (strict) to a fresh clone
of `tally` (the -14 build; -16 does not depend on the -15 draft), and runs the
check that must catch it: a battery check (A-G) or R1-R3
(races/place-close-16.sh). CAUGHT when that check reports FAIL, or the run
errors without reporting it as PASS.

    python3 tests/v5.4.2-16/mutations-16.py [M07 M12 ...]
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATCH = ROOT / "sql/v5.4.2-16-places-and-applicability.sql"
BATTERY = ROOT / "tests/v5.4.2-16/battery-16.sql"
RACE = ROOT / "tests/v5.4.2-16/races/place-close-16.sh"
DB = "m16"


def rep(old, new):
    def m(s):
        assert s.count(old) == 1, f"mutation anchor not unique/found: {old[:80]!r}"
        return s.replace(old, new, 1)
    return m


CLOSE_LEG = "    IF OLD.effective_to IS NOT NULL OR NEW.effective_to IS NULL\n       OR (to_jsonb(NEW) - c_close_cols) <> (to_jsonb(OLD) - c_close_cols) THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s"
def close_leg(label):
    return rep(CLOSE_LEG.encode().decode('unicode_escape') % label,
               ("    IF OLD.effective_to IS NOT NULL OR NEW.effective_to IS NULL THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s").encode().decode('unicode_escape') % label)

MUTATIONS = [
    # ---- places (section 3)
    ("M01", "the application may write places", "A1",
     rep("REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.places FROM tally_app;\nGRANT SELECT ON public.places TO tally_app;",
         "GRANT SELECT, INSERT ON public.places TO tally_app;")),
    ("M02", "a place's close may carry an edit", "A2", close_leg("place %s: never edited")),
    ("M03", "a place may be deleted", "A2",
     rep("            MESSAGE = format('place %s: never deleted", "            MESSAGE = format('place %s: never deleted")
     if False else rep("    IF TG_OP = 'DELETE' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('place %s: never deleted",
                       "    IF TG_OP = 'DELETE' THEN\n        RETURN OLD;\n        RAISE EXCEPTION USING\n            MESSAGE = format('place %s: never deleted")),
    ("M04", "place kinds left editable", "A3",
     rep("    FOREACH t IN ARRAY ARRAY['place_kinds', 'place_fact_kinds',", "    FOREACH t IN ARRAY ARRAY['place_fact_kinds',")),
    ("M05", "a code need not be of its kind's form", "A4",
     rep("        IF NEW.place_code !~ v_kind.code_pattern OR (NEW.kind_code", "        IF false OR (NEW.kind_code")),
    ("M06", "a state's code need not be its state", "A4",
     rep(" OR (NEW.kind_code = 'state' AND NEW.place_code <> NEW.state_code) THEN", " THEN")),
    ("M07", "a parent of another state or range", "A5",
     rep("            IF v_parent.state_code IS DISTINCT FROM NEW.state_code\n               OR NOT coalesce(", "            IF false\n               AND NOT coalesce(")),
    ("M08", "two places of one kind and code at once", "A6",
     rep(",\n    CONSTRAINT places_no_overlap\n        EXCLUDE USING gist (kind_code WITH =, state_code WITH =, place_code WITH =,\n                            daterange(effective_from, effective_to, '[)'::text) WITH &&)", "")),
    # ---- place facts (section 4)
    ("M09", "a fact on any place kind", "F1",
     rep("        IF NOT (v_place.kind_code = ANY (v_fk.place_kinds)) THEN", "        IF false THEN")),
    ("M10", "a fact's value of any type", "F2",
     rep("        IF NOT (CASE v_fk.value_type", "        IF false AND NOT (CASE v_fk.value_type")),
    ("M11", "a time zone the server does not know", "F2",
     rep("\n                                          AND EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names z WHERE z.name = NEW.value #>> '{}')", "")),
    ("M12", "a fact outside its place's range", "F3",
     rep("        IF NOT (daterange(v_place.effective_from, v_place.effective_to, '[)') @> daterange(NEW.effective_from, NEW.effective_to, '[)')) THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('place fact rejected: place",
         "        IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('place fact rejected: place")),
    ("M13", "two answers to one fact at once", "F4",
     rep(",\n    CONSTRAINT place_facts_no_overlap\n        EXCLUDE USING gist (place_id WITH =, fact_code WITH =, daterange(effective_from, effective_to, '[)'::text) WITH &&)", "")),
    ("M14", "a fact's close may carry an edit", "F4", close_leg("place fact %s: never edited")),
    ("M15", "a fact's close is not stamped", "F5",
     rep("    NEW.closed_at := now();\n    NEW.closed_by := session_user;\n    RETURN NEW;\nEND;\n$$;\nCOMMENT ON FUNCTION public.enforce_place_fact()",
         "    RETURN NEW;\nEND;\n$$;\nCOMMENT ON FUNCTION public.enforce_place_fact()")),
    # ---- memberships (section 5)
    ("M16", "the caller sets a membership's kind facets", "M1",
     rep("        NEW.place_kind         := v_kind.kind_code;\n        NEW.single_per_premise := v_kind.single_per_premise;\n", "")),
    ("M17", "a membership on any axis", "M2",
     rep("        IF NOT (NEW.axis = ANY (v_kind.membership_axes)) THEN", "        IF false THEN")),
    ("M18", "a premise in another state's place", "M3",
     rep("        IF v_place.state_code IS DISTINCT FROM v_loc.state THEN", "        IF false THEN")),
    ("M19", "a membership outside its place's range", "M4",
     rep("        IF NOT (daterange(v_place.effective_from, v_place.effective_to, '[)') @> daterange(NEW.valid_from, NEW.valid_to, '[)')) THEN", "        IF false THEN")),
    ("M20", "two cities at once (the single-kind exclusion never applies)", "M5",
     rep("        WHERE (single_per_premise)\n);", "        WHERE (false)\n);")),
    ("M21", "the same place twice (the no-repeat exclusion keys on the row)", "M5",
     rep("EXCLUDE USING gist (service_location_id WITH =, place_id WITH =, axis WITH =,", "EXCLUDE USING gist (id WITH =, place_id WITH =, axis WITH =,")),
    ("M22", "evidence without its reference", "M6",
     rep("    CONSTRAINT premise_place_memberships_evidence_check CHECK ((evidence_reference ~ '[[:alnum:]]'::text)),\n", "")),
    ("M23", "a membership's close may carry an edit", "M7",
     rep("    IF OLD.valid_to IS NOT NULL OR NEW.valid_to IS NULL\n       OR (to_jsonb(NEW) - c_close_cols) <> (to_jsonb(OLD) - c_close_cols) THEN",
         "    IF OLD.valid_to IS NOT NULL OR NEW.valid_to IS NULL THEN")),
    ("M24", "a zero-length membership close", "M7",
     rep("    CONSTRAINT premise_place_memberships_range_check CHECK (((valid_to IS NULL) OR (valid_to > valid_from))),",
         "    CONSTRAINT premise_place_memberships_range_check CHECK (((valid_to IS NULL) OR (valid_to >= valid_from))),")),
    ("M25", "a membership's close not stamped with its closer", "M7",
     rep("format('premise place membership %s: never edited — close it (valid_to, once, nothing else) and record the new membership (v5.4.2-16)', OLD.id),\n            ERRCODE = 'restrict_violation';\n    END IF;\n    NEW.closed_at := now();\n    BEGIN\n        NEW.closed_by := NULLIF(current_setting('app.user_id', true), '')::uuid;",
         "format('premise place membership %s: never edited — close it (valid_to, once, nothing else) and record the new membership (v5.4.2-16)', OLD.id),\n            ERRCODE = 'restrict_violation';\n    END IF;\n    NEW.closed_at := now();\n    BEGIN\n        NEW.closed_by := NULL;")),
    ("M26", "memberships and profiles deletable by the owner", "G6",
     rep("    FOREACH t IN ARRAY ARRAY['premise_place_memberships', 'utility_service_profiles'] LOOP\n        EXECUTE format('DROP TRIGGER IF EXISTS no_hard_delete",
         "    FOREACH t IN ARRAY ARRAY[]::text[] LOOP\n        EXECUTE format('DROP TRIGGER IF EXISTS no_hard_delete")),
    # ---- profiles (section 6)
    ("M27", "an owning place need not follow the owner type", "P1",
     rep("        IF v_owner.requires_owning_place IS DISTINCT FROM (NEW.owning_place_id IS NOT NULL) THEN", "        IF false THEN")),
    ("M28", "an owning place of another state", "P2",
     rep("            IF v_place.kind_code = 'state' OR v_place.state_code IS DISTINCT FROM NEW.state_code\n", "            IF v_place.kind_code = 'state'\n")),
    ("M29", "a state as the owning place", "P2",
     rep("            IF v_place.kind_code = 'state' OR v_place.state_code", "            IF false OR v_place.state_code")),
    ("M30", "an owning place not in force over the profile", "P2",
     rep("               OR NOT coalesce(daterange(v_place.effective_from, v_place.effective_to, '[)') @> daterange(NEW.effective_from, NEW.effective_to, '[)'), false) THEN\n                RAISE EXCEPTION USING\n                    MESSAGE = format('utility service profile rejected: owning place",
         "               THEN\n                RAISE EXCEPTION USING\n                    MESSAGE = format('utility service profile rejected: owning place")),
    ("M31", "two profiles at once", "P3",
     rep(",\n    CONSTRAINT utility_service_profiles_no_overlap\n        EXCLUDE USING gist (tenant_id WITH =, service_type WITH =, state_code WITH =,\n                            daterange(effective_from, effective_to, '[)'::text) WITH &&)", "")),
    ("M32", "a profile's close may carry an edit", "P4", close_leg("utility service profile %s: never edited")),
    ("M33", "the profile lookup invents nothing but returns empty", "L1",
     rep("    IF NOT FOUND THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('no utility profile is recorded", "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('no utility profile is recorded")),
    # ---- lookups (section 8)
    ("M34", "the least specific time zone wins", "L2",
     rep("     ORDER BY pl.specificity DESC", "     ORDER BY pl.specificity ASC")),
    ("M35", "the time-zone lookup returns NULL instead of refusing", "L3",
     rep("    IF v_tz IS NULL THEN", "    IF false THEN")),
    ("M36", "places read on every axis", "L4",
     rep("     WHERE m.service_location_id = p_service_location_id AND m.axis = p_axis", "     WHERE m.service_location_id = p_service_location_id")),
    ("M37", "the premise's own state is not read", "L2",
     rep("JOIN public.places p ON p.kind_code = 'state' AND p.state_code = upper(btrim(l.state))", "JOIN public.places p ON p.kind_code = 'state' AND p.state_code = 'ZZ'")),
    # ---- the close floor (section 3)
    ("M38", "a place closes under a membership", "C1",
     rep("WHERE m.place_id = OLD.id AND (m.valid_to IS NULL OR m.valid_to > NEW.effective_to)", "WHERE false")),
    ("M39", "a place closes under a profile", "C2",
     rep("WHERE u.owning_place_id = OLD.id AND (u.effective_to IS NULL OR u.effective_to > NEW.effective_to)", "WHERE false")),
    ("M40", "a place closes under a fact", "C3",
     rep("WHERE f.place_id = OLD.id AND (f.effective_to IS NULL OR f.effective_to > NEW.effective_to)", "WHERE false")),
    ("M41", "a place closes under a child", "C4",
     rep("WHERE c.parent_place_id = OLD.id AND (c.effective_to IS NULL OR c.effective_to > NEW.effective_to)", "WHERE false")),
    ("M42", "a place's close is not stamped", "C5",
     rep("    NEW.closed_at := now();\n    NEW.closed_by := session_user;\n    RETURN NEW;\nEND;\n$$;\nCOMMENT ON FUNCTION public.enforce_place()",
         "    RETURN NEW;\nEND;\n$$;\nCOMMENT ON FUNCTION public.enforce_place()")),
    ("M43", "a place may close under REPEATABLE READ", "R3",
     rep("    IF current_setting('transaction_isolation') <> 'read committed' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('place %s: a close runs only",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('place %s: a close runs only")),
    ("M44", "the close takes no place lock", "R1",
     rep("    PERFORM pg_advisory_xact_lock(public.place_lock_key(OLD.id));\n", "")),
    ("M45", "a membership takes no place lock", "R1",
     rep("        PERFORM pg_advisory_xact_lock_shared(public.place_lock_key(NEW.place_id));\n", "")),
    ("M46", "a profile takes no place lock", "R2",
     rep("            PERFORM pg_advisory_xact_lock_shared(public.place_lock_key(NEW.owning_place_id));\n", "")),
    # ---- tenancy and the premise's state (sections 5, 11)
    ("M47", "the membership compares the raw state", "G4",
     rep("        SELECT upper(btrim(l.state)) AS state INTO v_loc FROM public.service_locations l", "        SELECT l.state INTO v_loc FROM public.service_locations l")),
    # The patch's own AC-32 tail refuses this one at apply time.
    ("M48", "memberships have no tenant policy", "APPLY",
     rep("CREATE POLICY tenant_isolation ON public.premise_place_memberships USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));",
         "CREATE POLICY tenant_isolation ON public.premise_place_memberships USING (true);")),
]


def sh(cmd, inp=None):
    return subprocess.run(cmd, input=inp, capture_output=True, text=True)


def psql(db, sql, single=False):
    cmd = ["docker", "exec", "-i", "tally-pg", "psql", "-U", "tally", "-d", db, "-v", "ON_ERROR_STOP=1", "-q"]
    if single:
        cmd.append("-1")
    return sh(cmd + ["-f", "-"], sql)


def run_check(check):
    if check.startswith("R"):
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
