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
     rep("    IF TG_OP = 'DELETE' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('place %s: never deleted",
         "    IF TG_OP = 'DELETE' THEN\n        RETURN OLD;\n        RAISE EXCEPTION USING\n            MESSAGE = format('place %s: never deleted")),
    ("M04", "place kinds left editable", "A3",
     rep("    FOREACH t IN ARRAY ARRAY['place_kinds', 'place_fact_kinds', 'utility_owner_types', 'place_membership_evidence_kinds'] LOOP\n        EXECUTE format('DROP TRIGGER IF EXISTS a_enforce_place_vocabulary_immutable",
         "    FOREACH t IN ARRAY ARRAY['place_fact_kinds', 'utility_owner_types', 'place_membership_evidence_kinds'] LOOP\n        EXECUTE format('DROP TRIGGER IF EXISTS a_enforce_place_vocabulary_immutable")),
    ("M05", "the platform tables may be truncated", "A3",
     rep("    FOREACH t IN ARRAY ARRAY['place_kinds', 'place_fact_kinds', 'utility_owner_types', 'place_membership_evidence_kinds', 'places', 'place_facts'] LOOP",
         "    FOREACH t IN ARRAY ARRAY[]::text[] LOOP")),
    ("M06", "a code need not be of its kind's form", "A4",
     rep("        IF NEW.place_code !~ v_kind.code_pattern OR (NEW.kind_code", "        IF false OR (NEW.kind_code")),
    ("M07", "a state's code need not be its state", "A4",
     rep(" OR (NEW.kind_code = 'state' AND NEW.place_code <> NEW.state_code) THEN", " THEN")),
    ("M08", "a parent of any kind", "A5",
     rep("            IF NOT coalesce(v_parent.kind_code = ANY (v_kind.parent_kinds), false)\n               OR ", "            IF ")),
    ("M09", "a parent of another state", "A5",
     rep("               OR v_parent.state_code IS DISTINCT FROM NEW.state_code\n", "")),
    ("M10", "a parent not in force over the child", "A5",
     rep("               OR NOT coalesce(daterange(v_parent.effective_from, v_parent.effective_to, '[)') @> daterange(NEW.effective_from, NEW.effective_to, '[)'), false) THEN\n                RAISE EXCEPTION USING\n                    MESSAGE = format('place rejected: parent",
         "               THEN\n                RAISE EXCEPTION USING\n                    MESSAGE = format('place rejected: parent")),
    ("M11", "a parent need not match the kind's need for one", "A5",
     rep("        IF (NEW.parent_place_id IS NULL) <> (cardinality(v_kind.parent_kinds) = 0) THEN", "        IF false THEN")),
    ("M12", "two places of one kind and code at once", "A6",
     rep(",\n    CONSTRAINT places_no_overlap\n        EXCLUDE USING gist (kind_code WITH =, state_code WITH =, place_code WITH =,\n                            daterange(effective_from, effective_to, '[)'::text) WITH &&)", "")),
    ("M13", "a place keeps a caller's created_at", "A7",
     rep("        NEW.created_at    := now();\n        NEW.recorded_txid := txid_current();\n        NEW.closed_at     := NULL;", "        NEW.recorded_txid := txid_current();\n        NEW.closed_at     := NULL;")),
    # ---- place facts (section 4)
    ("M14", "a fact on any place kind", "F1",
     rep("        IF NOT coalesce(v_place.kind_code = ANY (v_fk.place_kinds), false) THEN", "        IF false THEN")),
    ("M15", "a fact's value of any type", "F2",
     rep("        IF NOT coalesce((CASE v_fk.value_type", "        IF false AND NOT coalesce((CASE v_fk.value_type")),
    ("M16", "a time zone the server does not know", "F2",
     rep("\n                                          AND EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names z WHERE z.name = NEW.value #>> '{}')", "")),
    ("M17", "a non-geographic zone name", "F2",
     rep("\n                                          AND ((NEW.value #>> '{}') ~ '^[A-Z][A-Za-z_]+/[A-Za-z0-9_/+-]+$' OR (NEW.value #>> '{}') = 'UTC')", "")),
    ("M18", "a fact outside its place's range", "F3",
     rep("        IF NOT (daterange(v_place.effective_from, v_place.effective_to, '[)') @> daterange(NEW.effective_from, NEW.effective_to, '[)')) THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('place fact rejected: place",
         "        IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('place fact rejected: place")),
    ("M19", "two answers to one fact at once", "F4",
     rep("        EXCLUDE USING gist (place_id WITH =, fact_code WITH =, (coalesce(fact_key, ''::text)) WITH =,", "        EXCLUDE USING gist (id WITH =, fact_code WITH =, (coalesce(fact_key, ''::text)) WITH =,")),
    ("M20", "a fact's close may carry an edit", "F4", close_leg("place fact %s: never edited")),
    ("M21", "a fact's close is not stamped", "F5",
     rep("    NEW.closed_at := now();\n    NEW.closed_by := session_user;\n    RETURN NEW;\nEND;\n$$;\nCOMMENT ON FUNCTION public.enforce_place_fact()",
         "    RETURN NEW;\nEND;\n$$;\nCOMMENT ON FUNCTION public.enforce_place_fact()")),
    ("M22", "a key need not follow the fact kind", "F6",
     rep("        IF v_fk.keyed <> (NEW.fact_key IS NOT NULL) THEN", "        IF false THEN")),
    ("M23", "the fact exclusion ignores the key", "F6",
     rep("(coalesce(fact_key, ''::text)) WITH =,", "(''::text) WITH =,")),
    # ---- memberships (section 5)
    ("M24", "the caller sets a membership's kind facets", "M1",
     rep("        NEW.place_kind        := v_kind.kind_code;\n        NEW.exclusivity_group := v_kind.exclusivity_group;\n", "")),
    ("M25", "a membership keeps the caller's created_by", "M1",
     rep("    IF TG_OP = 'INSERT' THEN\n        PERFORM public.assert_place_read_committed('recording a premise place membership');\n        BEGIN\n            NEW.created_by := NULLIF(current_setting('app.user_id', true), '')::uuid;\n        EXCEPTION WHEN OTHERS THEN\n            NEW.created_by := NULL;\n        END;",
         "    IF TG_OP = 'INSERT' THEN\n        PERFORM public.assert_place_read_committed('recording a premise place membership');")),
    ("M26", "a membership keeps a caller's created_at", "M1",
     rep("        NEW.created_at  := now();\n        NEW.closed_at   := NULL;\n        NEW.closed_by   := NULL;\n        NEW.void_reason := NULL;\n        NEW.voided_at   := NULL;\n        NEW.voided_by   := NULL;\n        RETURN NEW;\n    END IF;\n    RETURN public.place_citation_close_or_void(OLD, NEW, 'premise place membership'",
         "        NEW.closed_at   := NULL;\n        NEW.closed_by   := NULL;\n        NEW.void_reason := NULL;\n        NEW.voided_at   := NULL;\n        NEW.voided_by   := NULL;\n        RETURN NEW;\n    END IF;\n    RETURN public.place_citation_close_or_void(OLD, NEW, 'premise place membership'")),
    ("M27", "a membership on any axis", "M2",
     rep("        IF NOT coalesce(NEW.axis = ANY (v_kind.membership_axes), false) THEN", "        IF false THEN")),
    ("M28", "a premise in another state's place", "M3",
     rep("        IF v_place.state_code IS DISTINCT FROM v_state THEN", "        IF false THEN")),
    ("M29", "a membership outside its place's range", "M4",
     rep("        IF NOT (daterange(v_place.effective_from, v_place.effective_to, '[)') @> daterange(NEW.valid_from, NEW.valid_to, '[)')) THEN", "        IF false THEN")),
    ("M30", "two of one exclusivity group at once", "M5",
     rep("        WHERE ((exclusivity_group IS NOT NULL) AND (relation = 'within'::text) AND (voided_at IS NULL))", "        WHERE (false)")),
    ("M31", "a city and its extraterritorial area are not exclusive", "M5",
     rep("    ('extraterritorial_area',  ARRAY['regulatory'],          'municipal_status',", "    ('extraterritorial_area',  ARRAY['regulatory'],          'extraterritorial',")),
    ("M32", "the same place twice", "M5",
     rep("EXCLUDE USING gist (service_location_id WITH =, place_id WITH =, axis WITH =,", "EXCLUDE USING gist (id WITH =, place_id WITH =, axis WITH =,")),
    ("M33", "outside rows occupy the group", "M6",
     rep("        WHERE ((exclusivity_group IS NOT NULL) AND (relation = 'within'::text) AND (voided_at IS NULL))", "        WHERE ((exclusivity_group IS NOT NULL) AND (voided_at IS NULL))")),
    ("M34", "a distance on a within membership", "M6",
     rep("        CHECK ((((relation = 'within'::text) AND (distance_miles IS NULL))", "        CHECK ((((relation = 'within'::text))")),
    ("M35", "evidence without its reference", "M7",
     rep("    CONSTRAINT premise_place_memberships_evidence_check CHECK ((evidence_reference ~ '[[:alnum:]]'::text)),\n", "")),
    ("M36", "evidence without its date", "M7",
     rep("    evidence_reference  text NOT NULL,\n    evidence_date       date NOT NULL,", "    evidence_reference  text NOT NULL,\n    evidence_date       date,")),
    ("M37", "a close may carry an edit (membership and profile)", "M8",
     rep("    IF o ->> p_end_col IS NOT NULL OR n ->> p_end_col IS NULL OR (n - c_close_cols) <> (o - c_close_cols) THEN", "    IF o ->> p_end_col IS NOT NULL OR n ->> p_end_col IS NULL THEN")),
    ("M38", "a zero-length membership close", "M8",
     rep("    CONSTRAINT premise_place_memberships_range_check CHECK (((valid_to IS NULL) OR (valid_to > valid_from))),",
         "    CONSTRAINT premise_place_memberships_range_check CHECK (((valid_to IS NULL) OR (valid_to >= valid_from))),")),
    ("M39", "a close not stamped with its closer", "M8",
     rep("    RETURN jsonb_populate_record(p_new, jsonb_build_object('closed_at', now(), 'closed_by', v_user));", "    RETURN jsonb_populate_record(p_new, jsonb_build_object('closed_at', now()));")),
    ("M40", "a membership's recorder need not be of the tenant", "M9",
     rep("        END;\n        PERFORM public.assert_same_tenant_user(NEW.created_by, NEW.tenant_id, 'created_by');\n        -- Share-lock the premise",
         "        END;\n        -- Share-lock the premise")),
    # ---- a premise's state (section 5)
    ("M41", "a premise's state may change under its memberships", "S1",
     rep("    IF v_other IS NOT NULL THEN", "    IF false THEN")),
    ("M42", "a respelling counts as a change", "R9",
     rep("    IF upper(btrim(NEW.state)) IS NOT DISTINCT FROM upper(btrim(OLD.state)) THEN", "    IF NEW.state IS NOT DISTINCT FROM OLD.state THEN")),
    ("M43", "a premise's state changes outside READ COMMITTED", "R8",
     rep("    PERFORM public.assert_place_read_committed(format('changing the state of service location %s', OLD.id));\n", "")),
    ("M44", "a membership does not share-lock its premise", "R7",
     rep("         WHERE l.id = NEW.service_location_id AND l.tenant_id = NEW.tenant_id\n           FOR SHARE;", "         WHERE l.id = NEW.service_location_id AND l.tenant_id = NEW.tenant_id;")),
    # ---- profiles (section 6)
    ("M45", "an owning place need not follow the owner type", "P1",
     rep("        IF (cardinality(v_owner.owning_place_kinds) > 0) <> (NEW.owning_place_id IS NOT NULL) THEN", "        IF false THEN")),
    ("M46", "an owning place of any kind", "P2",
     rep("            IF NOT coalesce(v_place.kind_code = ANY (v_owner.owning_place_kinds), false) THEN", "            IF false THEN")),
    ("M47", "an owning place not in force over the profile", "P2",
     rep("            IF NOT coalesce(daterange(v_place.effective_from, v_place.effective_to, '[)') @> daterange(NEW.effective_from, NEW.effective_to, '[)'), false) THEN\n                RAISE EXCEPTION USING\n                    MESSAGE = format('utility service profile rejected: owning place",
         "            IF false THEN\n                RAISE EXCEPTION USING\n                    MESSAGE = format('utility service profile rejected: owning place")),
    ("M48", "a profile keeps the caller's created_by", "P3",
     rep("        PERFORM public.assert_place_read_committed('recording a utility service profile');\n        BEGIN\n            NEW.created_by := NULLIF(current_setting('app.user_id', true), '')::uuid;\n        EXCEPTION WHEN OTHERS THEN\n            NEW.created_by := NULL;\n        END;",
         "        PERFORM public.assert_place_read_committed('recording a utility service profile');")),
    ("M49", "two profiles at once", "P4",
     rep("EXCLUDE USING gist (tenant_id WITH =, service_type WITH =, state_code WITH =,", "EXCLUDE USING gist (id WITH =, service_type WITH =, state_code WITH =,")),
    ("M50", "a profile edit outside the close-or-void rule", "P5",
     rep("    RETURN public.place_citation_close_or_void(OLD, NEW, 'utility service profile', 'effective_to');", "    RETURN NEW;")),
    ("M51", "a membership edit outside the close-or-void rule", "M8",
     rep("    RETURN public.place_citation_close_or_void(OLD, NEW, 'premise place membership', 'valid_to');", "    RETURN NEW;")),
    ("M52", "the profile lookup returns empty instead of refusing", "L1",
     rep("    IF NOT FOUND THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('no utility profile is recorded", "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('no utility profile is recorded")),
    ("M53", "the profile lookup accepts NULL arguments", "L1",
     rep("    IF p_tenant_id IS NULL OR p_service_type IS NULL OR p_state_code IS NULL OR p_on IS NULL THEN", "    IF false THEN")),
    ("M54", "candidates of every specificity, not the most specific", "L2",
     rep("     WHERE c.specificity = c.top;", "     ;")),
    ("M55", "a non-uniform state's zone answers (the Chicago guess)", "L3",
     rep("        IF v_uniform IS NOT TRUE THEN\n            v_tz := NULL;", "        IF false THEN\n            v_tz := NULL;")),
    ("M56", "the time-zone lookup returns NULL instead of refusing", "L3",
     rep("    IF v_tz IS NULL THEN", "    IF false THEN")),
    ("M57", "the time zone reads the regulatory axis only", "L4",
     rep("                    UNION ALL\n                    SELECT * FROM public.premise_places_as_of(p_service_location_id, p_on, 'tax')) pl", "                    ) pl")),
    ("M58", "places read on every axis", "L6",
     rep("     WHERE m.service_location_id = p_service_location_id AND m.axis = p_axis", "     WHERE m.service_location_id = p_service_location_id")),
    ("M59", "a membership read on the day it ended", "L6",
     rep("       AND daterange(m.valid_from, m.valid_to, '[)') @> p_on\n", "       AND daterange(m.valid_from, m.valid_to, '[]') @> p_on\n")),
    ("M60", "the place lookup accepts an unknown axis", "L7",
     rep("    IF p_on IS NULL OR p_axis IS NULL OR p_axis <> ALL (ARRAY['regulatory', 'tax']) THEN", "    IF p_on IS NULL THEN")),
    ("M61", "the place lookup answers for an unknown state", "L7",
     rep("    IF v_state_place IS NULL THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('premise_places_as_of: premise %s is not found", "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('premise_places_as_of: premise %s is not found")),
    # M62 retired in r2: an invisible premise has no state, so the state
    # check refuses it (M61 removes that and is caught at L7).
    # ---- the close floor (section 3)
    ("M63", "a place closes under a membership", "C1",
     rep("WHERE m.place_id = OLD.id AND m.voided_at IS NULL AND (m.valid_to IS NULL OR m.valid_to > NEW.effective_to)", "WHERE false")),
    ("M64", "a place closes under a profile", "C2",
     rep("WHERE u.owning_place_id = OLD.id AND u.voided_at IS NULL AND (u.effective_to IS NULL OR u.effective_to > NEW.effective_to)", "WHERE false")),
    ("M65", "a place closes under a fact", "C3",
     rep("WHERE f.place_id = OLD.id AND (f.effective_to IS NULL OR f.effective_to > NEW.effective_to)", "WHERE false")),
    ("M66", "a place closes under a child", "C4",
     rep("WHERE c.parent_place_id = OLD.id AND (c.effective_to IS NULL OR c.effective_to > NEW.effective_to)", "WHERE false")),
    ("M67", "a membership ending on the close day blocks it (>= for >)", "C5",
     rep("(m.valid_to IS NULL OR m.valid_to > NEW.effective_to)", "(m.valid_to IS NULL OR m.valid_to >= NEW.effective_to)")),
    ("M68", "a place's close is not stamped", "C5",
     rep("    NEW.closed_at := now();\n    NEW.closed_by := session_user;\n    RETURN NEW;\nEND;\n$$;\nCOMMENT ON FUNCTION public.enforce_place()",
         "    RETURN NEW;\nEND;\n$$;\nCOMMENT ON FUNCTION public.enforce_place()")),
    ("M69", "a role row-level security narrows may close a place", "C6",
     rep("    IF v_sees_all IS NOT TRUE THEN", "    IF false THEN")),
    ("M70", "a place closes under a jurisdiction pointing at it", "J2",
     rep("        SELECT 'a utility jurisdiction ' || j.id::text FROM public.jurisdictions j\n         WHERE j.place_id = OLD.id", "        SELECT 'a utility jurisdiction ' || j.id::text FROM public.jurisdictions j\n         WHERE false")),
    ("M71", "a place may close under REPEATABLE READ", "R3",
     rep("    PERFORM public.assert_place_read_committed(format('closing place %s', OLD.id));\n", "")),
    ("M72", "the close takes no place lock", "R1",
     rep("    PERFORM pg_advisory_xact_lock(public.place_lock_key(OLD.id));\n", "")),
    ("M73", "a membership takes no place lock", "R1",
     rep("        PERFORM pg_advisory_xact_lock_shared(public.place_lock_key(NEW.place_id));\n", "")),
    ("M74", "a profile takes no place lock", "R2",
     rep("            PERFORM pg_advisory_xact_lock_shared(public.place_lock_key(NEW.owning_place_id));\n", "")),
    ("M75", "a membership may be recorded under REPEATABLE READ", "R4",
     rep("        PERFORM public.assert_place_read_committed('recording a premise place membership');\n", "")),
    ("M76", "a profile may be recorded under REPEATABLE READ", "R5",
     rep("        PERFORM public.assert_place_read_committed('recording a utility service profile');\n", "")),
    ("M77", "a jurisdiction may point at a place under REPEATABLE READ", "R6",
     rep("    PERFORM public.assert_place_read_committed(format('pointing jurisdiction %s at a place', NEW.id));\n", "")),
    # ---- jurisdictions (section 7)
    ("M78", "a jurisdiction may point at a state", "J1",
     rep("    IF v_place.kind_code = 'state' OR v_place.effective_to IS NOT NULL", "    IF v_place.effective_to IS NOT NULL")),
    # ---- review round 2
    ("M81", "the time zone chooses among disagreeing candidates", "N1",
     rep("    IF cardinality(v_zones) > 1 THEN", "    IF false THEN")),
    ("M82", "an outside place answers the time zone", "N2",
     rep("             WHERE pl.relation = 'within') c", "            ) c")),
    ("M83", "a zone fact not yet in force answers", "N2",
     rep("              JOIN public.place_facts f ON f.place_id = pl.place_id AND f.fact_code = 'time_zone'\n                                       AND daterange(f.effective_from, f.effective_to, '[)') @> p_on\n             WHERE",
         "              JOIN public.place_facts f ON f.place_id = pl.place_id AND f.fact_code = 'time_zone'\n             WHERE")),
    ("M84", "a uniform fact no longer in force answers", "N14",
     rep("          JOIN public.place_facts f ON f.place_id = pl.place_id AND f.fact_code = 'time_zone_uniform'\n                                   AND daterange(f.effective_from, f.effective_to, '[)') @> p_on",
         "          JOIN public.place_facts f ON f.place_id = pl.place_id AND f.fact_code = 'time_zone_uniform'")),
    ("M85", "the limited-purpose area is its own group", "N3",
     rep("    ('limited_purpose_area',   ARRAY['regulatory'],          'municipal_status',", "    ('limited_purpose_area',   ARRAY['regulatory'],          'limited_purpose',")),
    ("M86", "unincorporated territory is its own group", "N3",
     rep("    ('unincorporated_area',    ARRAY['regulatory', 'tax'],   'municipal_status',", "    ('unincorporated_area',    ARRAY['regulatory', 'tax'],   'unincorporated',")),
    ("M87", "a void may change other columns", "N4",
     rep("        IF (n - c_void_cols) <> (o - c_void_cols) OR (n ->> 'void_reason') !~ '[[:alnum:]]' THEN", "        IF (n ->> 'void_reason') !~ '[[:alnum:]]' THEN")),
    ("M88", "a void is not stamped", "N4",
     rep("        RETURN jsonb_populate_record(p_new, jsonb_build_object('voided_at', now(), 'voided_by', v_user));", "        RETURN jsonb_populate_record(p_new, jsonb_build_object('voided_at', now()));")),
    ("M89", "a voided row may be edited", "N4",
     rep("    IF o ->> 'voided_at' IS NOT NULL THEN", "    IF false THEN")),
    ("M90", "the place lookup reads voided memberships", "N4",
     rep("     WHERE m.service_location_id = p_service_location_id AND m.axis = p_axis AND m.voided_at IS NULL", "     WHERE m.service_location_id = p_service_location_id AND m.axis = p_axis")),
    ("M91", "a voided membership still occupies its group", "N4",
     rep("        WHERE ((exclusivity_group IS NOT NULL) AND (relation = 'within'::text) AND (voided_at IS NULL))", "        WHERE ((exclusivity_group IS NOT NULL) AND (relation = 'within'::text))")),
    ("M92", "the profile lookup reads voided profiles", "N5",
     rep("       AND u.voided_at IS NULL AND daterange(u.effective_from, u.effective_to, '[)') @> p_on;", "       AND daterange(u.effective_from, u.effective_to, '[)') @> p_on;")),
    ("M93", "a voided profile still blocks its successor", "N5",
     rep("                            daterange(effective_from, effective_to, '[)'::text) WITH &&)\n        WHERE (voided_at IS NULL)\n);\nCREATE INDEX IF NOT EXISTS idx_utility_service_profiles_tenant",
         "                            daterange(effective_from, effective_to, '[)'::text) WITH &&)\n);\nCREATE INDEX IF NOT EXISTS idx_utility_service_profiles_tenant")),
    ("M94", "a profile for a state that does not exist", "N6",
     rep("        IF NOT EXISTS (SELECT 1 FROM public.places p\n                        WHERE p.kind_code = 'state' AND p.state_code = NEW.state_code", "        IF false AND NOT EXISTS (SELECT 1 FROM public.places p\n                        WHERE p.kind_code = 'state' AND p.state_code = NEW.state_code")),
    ("M95", "a profile on evidence dated in the future", "N6",
     rep("        IF NEW.evidence_date > CURRENT_DATE THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('utility service profile rejected: its evidence", "        IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('utility service profile rejected: its evidence")),
    ("M96", "a membership on evidence dated in the future", "N6",
     rep("        IF NEW.evidence_date > CURRENT_DATE THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('premise place membership rejected: its evidence", "        IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('premise place membership rejected: its evidence")),
    ("M97", "a membership born voided", "N7",
     rep("        NEW.void_reason := NULL;\n        NEW.voided_at   := NULL;\n        NEW.voided_by   := NULL;\n        RETURN NEW;\n    END IF;\n    RETURN public.place_citation_close_or_void(OLD, NEW, 'premise place membership'",
         "        RETURN NEW;\n    END IF;\n    RETURN public.place_citation_close_or_void(OLD, NEW, 'premise place membership'")),
    ("M98", "a jurisdiction may point at a place scheduled to close", "N9",
     rep("    IF v_place.kind_code = 'state' OR v_place.effective_to IS NOT NULL", "    IF v_place.kind_code = 'state'")),
    ("M99", "the application may write evidence kinds", "N10",
     rep("REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.place_membership_evidence_kinds FROM tally_app;", "GRANT INSERT ON public.place_membership_evidence_kinds TO tally_app;")),
    ("M100", "fact kinds and evidence kinds left editable", "N11",
     rep("    FOREACH t IN ARRAY ARRAY['place_kinds', 'place_fact_kinds', 'utility_owner_types', 'place_membership_evidence_kinds'] LOOP\n        EXECUTE format('DROP TRIGGER IF EXISTS a_enforce_place_vocabulary_immutable",
         "    FOREACH t IN ARRAY ARRAY['place_kinds', 'utility_owner_types'] LOOP\n        EXECUTE format('DROP TRIGGER IF EXISTS a_enforce_place_vocabulary_immutable")),
    ("M101", "a number fact of any value", "N12",
     rep("                                          AND (v_fk.value_min IS NULL OR (NEW.value)::text::numeric >= v_fk.value_min)\n                                          AND (v_fk.value_max IS NULL OR (NEW.value)::text::numeric <  v_fk.value_max)", "")),
    ("M102", "a fixed Etc/ offset as a zone", "N13",
     rep("\n                                          AND (NEW.value #>> '{}') !~ '^Etc/'", "")),
    ("M103", "a key with surrounding blanks", "N13",
     rep("((fact_key ~ '[[:alnum:]]'::text) AND (fact_key = btrim(fact_key)))", "((fact_key ~ '[[:alnum:]]'::text))")),
    ("M104", "a fact keeps the caller's created_at", "N13",
     rep("        NEW.created_at := now();\n        NEW.closed_at  := NULL;\n        NEW.closed_by  := NULL;\n        RETURN NEW;\n    END IF;\n    IF TG_OP = 'DELETE' THEN\n        RAISE EXCEPTION USING MESSAGE = format('place fact",
         "        NEW.closed_at  := NULL;\n        NEW.closed_by  := NULL;\n        RETURN NEW;\n    END IF;\n    IF TG_OP = 'DELETE' THEN\n        RAISE EXCEPTION USING MESSAGE = format('place fact")),
    ("M105", "the state guard counts only open memberships", "N15",
     rep("     WHERE m.service_location_id = OLD.id AND m.voided_at IS NULL AND p.state_code IS DISTINCT FROM upper(btrim(NEW.state))",
         "     WHERE m.service_location_id = OLD.id AND m.voided_at IS NULL AND m.valid_to IS NULL AND p.state_code IS DISTINCT FROM upper(btrim(NEW.state))")),
    ("M106", "a profile ending on the close day blocks it", "N16",
     rep("(u.effective_to IS NULL OR u.effective_to > NEW.effective_to)", "(u.effective_to IS NULL OR u.effective_to >= NEW.effective_to)")),
    ("M107", "a fact ending on the close day blocks it", "N16",
     rep("(f.effective_to IS NULL OR f.effective_to > NEW.effective_to)", "(f.effective_to IS NULL OR f.effective_to >= NEW.effective_to)")),
    ("M108", "a child ending on the close day blocks it", "N16",
     rep("(c.effective_to IS NULL OR c.effective_to > NEW.effective_to)", "(c.effective_to IS NULL OR c.effective_to >= NEW.effective_to)")),
    ("M109", "a voided membership holds its place open", "N17",
     rep("WHERE m.place_id = OLD.id AND m.voided_at IS NULL AND", "WHERE m.place_id = OLD.id AND")),
    ("M110", "the jurisdiction pointer takes no place lock", "R10",
     rep("    PERFORM pg_advisory_xact_lock_shared(public.place_lock_key(NEW.place_id));\n    SELECT * INTO v_place FROM public.places p WHERE p.id = NEW.place_id;\n    -- The pointer is undated",
         "    SELECT * INTO v_place FROM public.places p WHERE p.id = NEW.place_id;\n    -- The pointer is undated")),
    ("M111", "a voided membership holds the premise's state", "N18",
     rep("     WHERE m.service_location_id = OLD.id AND m.voided_at IS NULL AND p.state_code", "     WHERE m.service_location_id = OLD.id AND p.state_code")),
    # ---- tenancy (sections 6, 11)
    ("M79", "memberships and profiles deletable by the owner", "G3",
     rep("    FOREACH t IN ARRAY ARRAY['premise_place_memberships', 'utility_service_profiles'] LOOP\n        EXECUTE format('DROP TRIGGER IF EXISTS no_hard_delete",
         "    FOREACH t IN ARRAY ARRAY[]::text[] LOOP\n        EXECUTE format('DROP TRIGGER IF EXISTS no_hard_delete")),
    # The patch's own AC-32 tail refuses this one at apply time.
    ("M80", "memberships have no tenant policy", "APPLY",
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
