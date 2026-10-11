#!/usr/bin/env python3
"""v5.4.2-18 — prove the -18 checks CATCH drift, not merely pass.

Each mutation alters a copy of the patch and is judged by the script that owns the named check:

  battery check (S M K D O H X L G)   run-battery-18.sh on a clone of `tally` with the mutated patch applied
  F13                                  battery-13 (the close floor against real citations), same clone
  P1a P2 P3a P7x ...                   migration-18.py with PATCH18 = the mutated patch
  APPLY:<phrase>                       the mutated patch itself must refuse, with that phrase

CAUGHT only when the named check prints its own FAIL line: the battery stops at the first failing
check, so a mutation an EARLIER check catches is reported as missed, and its named check is wrong —
fix the name, never loosen the rule.

Needs a PRE-18 base (`tally` while -18 is not mirrored; on a mirrored build, restore one first):

    python3 tests/v5.4.2-18/mutations-18.py [M01 M07 ...]
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[2]
PATCH = ROOT / "sql/v5.4.2-18-backbilling-rule-terms.sql"
HERE = ROOT / "tests/v5.4.2-18"
DB = f"m18mut{os.getpid()}"


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


# The embedded schema is JSON inside the patch: a mutation edits it by text.
MUTATIONS = [
    # ---- the close floor (section 1)
    ("M01", "the floor ignores an evaluation's anchor", "H13",
     rep("SELECT greatest(v.anchor_date, v.evaluated_at::date) AS d", "SELECT v.evaluated_at::date AS d")),
    ("M02", "the floor ignores an evaluation's own date", "H12",
     rep("SELECT greatest(v.anchor_date, v.evaluated_at::date) AS d", "SELECT v.anchor_date AS d")),
    ("M03", "the floor ignores evidence", "H14",
     rep("        SELECT p.period_start FROM public.meter_correction_period_evidence p WHERE p.rule_id = p_rule_id\n", "        SELECT NULL::date WHERE false\n")),
    ("M04", "the floor is the earliest citation", "H15",
     rep("    SELECT max(d) FROM (\n        SELECT greatest", "    SELECT min(d) FROM (\n        SELECT greatest")),
    ("M05", "the floor ignores the evaluations' rule", "H12",
     rep("FROM public.meter_correction_evaluations v WHERE v.rule_id = p_rule_id", "FROM public.meter_correction_evaluations v WHERE v.rule_id IS NOT NULL AND false")),
    # ---- the insert check
    ("M06", "the basis vocabulary is not consulted", "X5",
     rep("    IF v_on_test IS DISTINCT FROM ((v_terms -> 'anchor') ? 'qualifying_outcomes') THEN", "    IF false THEN")),
    ("M07", "a kind may be named twice in a direction", "X1",
     rep("        IF v_dup IS NOT NULL THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('%s: the %s window names the window-term kind", "        IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('%s: the %s window names the window-term kind")),
    ("M08", "a priority may be used twice", "X3",
     rep("        IF v_dup IS NOT NULL THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('%s: the %s window uses priority", "        IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('%s: the %s window uses priority")),
    ("M09", "a window may list its terms in any order", "X7",
     rep("        IF (SELECT array_agg(t ->> 'kind' ORDER BY o) IS DISTINCT FROM", "        IF false AND (SELECT array_agg(t ->> 'kind' ORDER BY o) IS DISTINCT FROM")),
    ("M10", "only the adverse direction is checked for repeats", "X9",
     rep("    FOREACH v_dir IN ARRAY ARRAY['adverse', 'favourable'] LOOP\n        SELECT t ->> 'kind' INTO v_dup", "    FOREACH v_dir IN ARRAY ARRAY['adverse'] LOOP\n        SELECT t ->> 'kind' INTO v_dup")),
    ("M11", "the document's outcomes are not weighed against the vocabulary's flag in the other direction", "X5",
     rep("    IF v_on_test IS DISTINCT FROM ((v_terms -> 'anchor') ? 'qualifying_outcomes') THEN", "    IF v_on_test AND NOT ((v_terms -> 'anchor') ? 'qualifying_outcomes') THEN")),
    ("M12", "the order check is by locale-free reverse", "APPLY:out of order",
     rep("array_agg(t ->> 'kind' ORDER BY t ->> 'kind' COLLATE \"C\")", "array_agg(t ->> 'kind' ORDER BY t ->> 'kind' COLLATE \"C\" DESC)")),
    # ---- the adoption check (called on its own: migration-18 P7)
    ("M13", "the units flag is not compared", "P7g",
     rep("'requires_supervisor_evidence', 'units_invariant'] LOOP", "'requires_supervisor_evidence'] LOOP")),
    ("M14", "the supervisor flag is not compared", "P7f",
     rep("'delivery_path',\n                               'requires_supervisor_evidence', 'units_invariant'] LOOP", "'delivery_path',\n                               'units_invariant'] LOOP")),
    ("M15", "the duty is not compared", "P7b",
     rep("FOREACH v_k IN ARRAY ARRAY['favourable_duty', 'adverse_straddle'", "FOREACH v_k IN ARRAY ARRAY['adverse_straddle'")),
    ("M16", "the citation is not compared", "P7h",
     rep("    IF (v_t ->> 'citation') IS DISTINCT FROM btrim(", "    IF false AND (v_t ->> 'citation') IS DISTINCT FROM btrim(")),
    ("M18", "the anchor version is not compared", "P7j",
     rep("    IF (v_t -> 'anchor' -> 'version') IS DISTINCT FROM to_jsonb(1) THEN", "    IF false THEN")),
    ("M19", "the qualifying outcomes are not compared", "P7k",
     rep("    IF (v_t -> 'anchor' -> 'qualifying_outcomes') IS DISTINCT FROM v_want THEN", "    IF false THEN")),
    ("M20", "the enforcement strategy is not compared", "P7n",
     rep("    IF (v_t -> 'enforcement' ->> 'strategy') IS DISTINCT FROM (p_row ->> 'enforce_scope')\n       OR", "    IF false\n       OR")),
    ("M21", "the enforcement version is not compared", "P7q",
     rep("       OR (v_t -> 'enforcement' -> 'version') IS DISTINCT FROM to_jsonb(1)\n", "")),
    ("M22", "the month count is not compared", "P7o",
     rep("       OR (v_t -> 'enforcement' -> 'months') IS DISTINCT FROM (CASE WHEN p_row ->> 'enforce_months' IS NOT NULL THEN p_row -> 'enforce_months' END)\n", "")),
    ("M23", "the enforcement condition is not compared", "P7p",
     rep("       OR (v_t -> 'enforcement' -> 'condition') IS DISTINCT FROM (CASE WHEN p_row ->> 'enforce_condition' IS NOT NULL THEN p_row -> 'enforce_condition' END) THEN", "       OR false THEN")),
    ("M24", "only the adverse window is compared", "P7s",
     rep("    FOREACH v_dir IN ARRAY ARRAY['adverse', 'favourable'] LOOP\n        SELECT coalesce(jsonb_agg(e ORDER BY e::text), '[]') INTO v_want", "    FOREACH v_dir IN ARRAY ARRAY['adverse'] LOOP\n        SELECT coalesce(jsonb_agg(e ORDER BY e::text), '[]') INTO v_want")),
    ("M25", "the legacy priority is not compared", "P7x",
     rep("'unit', w.unit, 'priority', w.priority)) AS e\n                  FROM public.backbilling_rule_window_terms w WHERE w.rule_id = v_id", "'unit', w.unit)) AS e\n                  FROM public.backbilling_rule_window_terms w WHERE w.rule_id = v_id")),
    ("M26", "a delegation passes for a row with old columns", "P7w",
     rep("    IF v_t ->> 'governs' IS DISTINCT FROM 'law' THEN\n        RAISE EXCEPTION USING MESSAGE = format('%s: a row whose note", "    IF false THEN\n        RAISE EXCEPTION USING MESSAGE = format('%s: a row whose note")),
    ("M27", "the adverse straddle is not compared", "P7c",
     rep("ARRAY['favourable_duty', 'adverse_straddle', 'favourable_straddle', 'delivery_path',", "ARRAY['favourable_duty', 'favourable_straddle', 'delivery_path',")),
    ("M28", "the delivery path is not compared", "P7e",
     rep("'favourable_straddle', 'delivery_path',\n                               'requires_supervisor_evidence'", "'favourable_straddle',\n                               'requires_supervisor_evidence'")),
    # ---- the builder (a wrong document is refused by the adoption check, at apply)
    ("M29", "the builder reads the adverse straddle from the favourable column", "APPLY:adverse_straddle",
     rep("'adverse_straddle', r -> 'adverse_straddle',", "'adverse_straddle', r -> 'favourable_straddle',")),
    ("M30", "the builder cites the whole note", "APPLY:the document cites",
     rep("        'citation', btrim(substring(r ->> 'source_note' from '^(.*?)(?: — |;|$)')),", "        'citation', r ->> 'source_note',")),
    ("M31", "the builder drops the window priority", "P3a",
     rep("'quantity', w.quantity, 'unit', w.unit, 'priority', w.priority))\n                                              ORDER BY", "'quantity', w.quantity, 'unit', w.unit))\n                                              ORDER BY")),
    ("M32", "the builder omits qualifying outcomes", "APPLY:/anchor/qualifying_outcomes: required",
     rep("'qualifying_outcomes', CASE WHEN jsonb_typeof(r -> 'qualifying_test_outcomes') = 'array'\n                                                            THEN (SELECT jsonb_agg(o ORDER BY o COLLATE \"C\") FROM (SELECT DISTINCT o FROM jsonb_array_elements_text(r -> 'qualifying_test_outcomes') o) u) END)),", "'qualifying_outcomes', NULL::jsonb)),")),
    ("M33", "the builder puts both directions' terms in the adverse window", "APPLY:window",
     rep("FROM public.backbilling_rule_window_terms w WHERE w.rule_id = p_id AND w.direction = dd), '[]') AS terms", "FROM public.backbilling_rule_window_terms w WHERE w.rule_id = p_id AND w.direction IN ('adverse', 'favourable')), '[]') AS terms")),
    ("M34", "the builder loses the months", "APPLY:/enforcement/months: required",
     rep("'months', r -> 'enforce_months', 'condition', r -> 'enforce_condition')),", "'months', NULL::jsonb, 'condition', r -> 'enforce_condition')),")),
    ("M35", "the builder orders a window by priority", "P3a",
     rep("ORDER BY w.term_kind COLLATE \"C\")", "ORDER BY w.priority NULLS LAST, w.term_kind COLLATE \"C\")")),
    # ---- the migration
    ("M36", "the rows bind investor-owned utilities only", "M7",
     both(rep("ADD COLUMN owner_types text[] DEFAULT ARRAY['investor_owned', 'cooperative'],", "ADD COLUMN owner_types text[] DEFAULT ARRAY['investor_owned'],"),
          rep("ADD COLUMN owner_span int4multirange NOT NULL DEFAULT public.rule_applicability_span('owner_type', ARRAY['investor_owned', 'cooperative']),", "ADD COLUMN owner_span int4multirange NOT NULL DEFAULT public.rule_applicability_span('owner_type', ARRAY['investor_owned']),"),
          rep("c_owner_types CONSTANT text[] := ARRAY['investor_owned', 'cooperative'];", "c_owner_types CONSTANT text[] := ARRAY['investor_owned'];"))),
    ("M37", "the rows bind every system kind (propane, master meters)", "M7",
     both(rep("        ADD COLUMN system_kinds text[] DEFAULT ARRAY['distribution'],", "        ADD COLUMN system_kinds text[],"),
          rep("DEFAULT public.rule_applicability_span('system_kind', ARRAY['distribution']),", "DEFAULT public.rule_applicability_span('system_kind', NULL),"),
          rep(" OR system_kinds IS DISTINCT FROM ARRAY['distribution']) THEN", ") THEN"))),
    ("M38", "the facet column stays NOT NULL", "APPLY:is NOT NULL",
     rep("        ALTER COLUMN anchor_basis DROP NOT NULL;      -- a facet column allows NULL (-17 R23)", "        ALTER COLUMN anchor_basis SET NOT NULL;")),
    ("M39", "-13's history trigger stays", "APPLY:never edited",
     rep("    DROP TRIGGER a_enforce_backbilling_rule_history ON public.backbilling_rules;\n", "")),
    ("M40", "-13's overlap exclusion stays", "M5",
     rep("        DROP CONSTRAINT backbilling_rules_no_overlap,\n", "")),
    ("M41", "-13's range check stays", "M5",
     rep("        DROP CONSTRAINT backbilling_rules_range_check,\n", "")),
    ("M42", "the fill does nothing", "APPLY:were not adopted",
     rep("     WHERE b.terms IS NULL;\n    SELECT count(*) INTO v_unfilled", "     WHERE b.terms IS NULL AND false;\n    SELECT count(*) INTO v_unfilled")),
    ("M43", "a content column survives", "M2",
     rep("        DROP COLUMN delivery_path, DROP COLUMN requires_supervisor_evidence, DROP COLUMN units_invariant,", "        DROP COLUMN requires_supervisor_evidence, DROP COLUMN units_invariant,")),
    ("M44", "the child table survives", "APPLY:cannot drop table",
     rep("    DROP TABLE public.backbilling_rule_window_terms;\n", "")),
    ("M45", "the window-term kinds survive", "S3",
     rep("    DROP TABLE public.backbilling_window_term_kinds;\n", "")),
    ("M46", "the enforcement conditions survive", "S3",
     rep("    DROP TABLE public.backbilling_enforce_conditions;\n", "")),
    ("M47", "-13's record guard survives", "M4",
     rep("    DROP FUNCTION public.enforce_backbilling_rule_record();\n", "")),
    ("M48", "-13's history function survives", "M4",
     rep("    DROP FUNCTION public.enforce_backbilling_rule_history();\n", "")),
    ("M49", "the window-term guard survives", "M4",
     rep("    DROP FUNCTION public.enforce_backbilling_window_term_record();\n", "")),
    ("M50", "the builder survives", "G4",
     rep("DROP FUNCTION IF EXISTS public.backbilling_rule_legacy_document(uuid);\n", "")),
    ("M51", "the old comments stay", "G4",
     rep("d.description LIKE '%' || t.old_text || '%' LOOP", "d.description LIKE '%' || t.old_text || '%' AND false LOOP")),
    ("M52", "a second run registers again", "P2",
     rep("    IF EXISTS (SELECT 1 FROM public.rule_tables WHERE table_name = 'public.backbilling_rules'::regclass) THEN\n        RAISE NOTICE", "    IF false THEN\n        RAISE NOTICE")),
    ("M53", "the table is registered without its adoption check", "APPLY:already holds rows",
     rep("                                       'public.backbilling_rule_adoption_check(jsonb)');", "                                       NULL);")),
    ("M54", "the table is registered without its close floor", "M1",
     rep("                                       'public.backbilling_rule_close_floor(uuid)', 'public.backbilling_rule_insert_check(jsonb)', NULL, NULL,", "                                       NULL, 'public.backbilling_rule_insert_check(jsonb)', NULL, NULL,")),
    ("M55", "the table is registered without its insert check", "M1",
     rep("                                       'public.backbilling_rule_close_floor(uuid)', 'public.backbilling_rule_insert_check(jsonb)', NULL, NULL,", "                                       'public.backbilling_rule_close_floor(uuid)', NULL, NULL, NULL,")),
    ("M56", "the table is keyed by cause alone", "APPLY:could not create exclusion constraint",
     rep("ARRAY['customer_class', 'cause'], ARRAY['anchor_basis'],", "ARRAY['cause'], ARRAY['anchor_basis'],")),
    ("M57", "the anchor facet reads the wrong path", "APPLY:is a facet, derived from the document",
     rep("'$.anchor.strategy', 'public.backbilling_anchor_bases'", "'$.governs', 'public.backbilling_anchor_bases'")),
    ("M58", "the anchor facet names no vocabulary", "S2",
     rep("'$.anchor.strategy', 'public.backbilling_anchor_bases', 'basis_code',", "'$.anchor.strategy', NULL, NULL,")),
    ("M59", "the hooks stay open to the application", "G5",
     rep("REVOKE ALL ON FUNCTION public.backbilling_rule_close_floor(uuid), public.backbilling_rule_insert_check(jsonb), public.backbilling_rule_adoption_check(jsonb)\n    FROM PUBLIC, tally_app, tally_core;",
         "GRANT EXECUTE ON FUNCTION public.backbilling_rule_close_floor(uuid), public.backbilling_rule_insert_check(jsonb), public.backbilling_rule_adoption_check(jsonb) TO tally_app;")),
    ("M60", "the kind is registered frozen-looking: not a law kind", "APPLY:",
     rep("VALUES ('backbilling', 1, 'law', $schema$", "VALUES ('backbilling', 1, 'tariff', $schema$")),
    # ---- the schema (embedded JSON)
    ("M61", "a month count may be zero", "D3",
     rep('"months": {"type": "integer", "minimum": 1}', '"months": {"type": "integer", "minimum": 0}')),
    ("M62", "a document may omit its windows", "D1",
     rep('"requires_supervisor_evidence", "units_invariant", "enforcement", "windows"],', '"requires_supervisor_evidence", "units_invariant", "enforcement"],')),
    ("M63", "outcomes may repeat", "D13",
     rep('"type": "array", "minItems": 1, "maxItems": 3, "uniqueItems": true,', '"type": "array", "minItems": 1, "maxItems": 3,')),
    ("M64", "a quantity may sit on a deployment-start term", "D19",
     rep('''        "kind": {"type": "string", "const": "deployment_start"},
        "priority": {"$ref": "#/$defs/priority"}''', '''        "kind": {"type": "string", "const": "deployment_start"},
        "quantity": {"type": "integer", "minimum": 1},
        "priority": {"$ref": "#/$defs/priority"}''')),
    ("M65", "a unit of fortnights", "D20",
     rep('"enum": ["months", "days", "billing_periods"]', '"enum": ["months", "days", "billing_periods", "fortnights"]')),
    ("M66", "a priority has an upper bound of eight", "P8a",
     rep('"priority": {"type": "integer", "minimum": 1, "maximum": 2147483647},', '"priority": {"type": "integer", "minimum": 1, "maximum": 8},')),
    ("M108", "a priority has no upper bound", "D40c",
     rep('"priority": {"type": "integer", "minimum": 1, "maximum": 2147483647},', '"priority": {"type": "integer", "minimum": 1},')),
    ("M107", "the migration does not lock the table before its pre-flight", "P11a",
     rep("    LOCK TABLE public.backbilling_rules IN ACCESS EXCLUSIVE MODE;\n", "")),
    ("M67", "a window has no size limit", "D41",
     rep('"window": {"type": "array", "maxItems": 8,', '"window": {"type": "array",')),
    ("M68", "a courier delivery path", "D24",
     rep('"enum": ["adjustment", "reissue", "unruled"],', '"enum": ["adjustment", "reissue", "unruled", "courier"],')),
    ("M69", "a split straddle", "D23",
     rep('"enum": ["forfeit_whole", "prorate_days", "include_whole"],\n      "description": "A billed period', '"enum": ["forfeit_whole", "prorate_days", "include_whole", "split"],\n      "description": "A billed period')),
    ("M70", "a maybe duty", "D25",
     rep('"enum": ["mandatory", "permitted"],', '"enum": ["mandatory", "permitted", "maybe"],')),
    ("M71", "any enforcement condition", "D7",
     rep('"enum": ["read_beyond_utility_control"],', '"enum": ["read_beyond_utility_control", "whenever"],')),
    ("M72", "a test anchor needs no outcomes", "D10",
     rep('"required": ["strategy", "version", "qualifying_outcomes"],', '"required": ["strategy", "version"],')),
    ("M73", "a discovery anchor may name outcomes", "D11",
     rep('''        "strategy": {"type": "string", "const": "discovery_date"},
        "version": {"type": "integer", "minimum": 1, "maximum": 1}''', '''        "strategy": {"type": "string", "const": "discovery_date"},
        "version": {"type": "integer", "minimum": 1, "maximum": 1},
        "qualifying_outcomes": {"type": "array", "items": {"type": "string"}}''')),
    ("M74", "claimed_start is not a window-term kind", "D22",
     rep('{"$ref": "#/$defs/term_before_anchor"}, {"$ref": "#/$defs/term_last_test_any_outcome"},\n      {"$ref": "#/$defs/term_last_test_accurate"}, {"$ref": "#/$defs/term_half_since_last_test"},\n      {"$ref": "#/$defs/term_deployment_start"}, {"$ref": "#/$defs/term_service_start"},\n      {"$ref": "#/$defs/term_claimed_start"}]},',
         '{"$ref": "#/$defs/term_before_anchor"}, {"$ref": "#/$defs/term_last_test_any_outcome"},\n      {"$ref": "#/$defs/term_last_test_accurate"}, {"$ref": "#/$defs/term_half_since_last_test"},\n      {"$ref": "#/$defs/term_deployment_start"}, {"$ref": "#/$defs/term_service_start"}]},')),
    ("M75", "the citation may be anything", "D27",
     rep('"citation": {"type": "string", "pattern": "[A-Za-z0-9]"},\n    "delegated"', '"citation": {"type": "string"},\n    "delegated"')),
    ("M76", "an enforcement strategy may carry a stray month count", "D5",
     rep('''        "strategy": {"type": "string", "const": "never"},
        "version": {"type": "integer", "minimum": 1, "maximum": 1}''', '''        "strategy": {"type": "string", "const": "never"},
        "version": {"type": "integer", "minimum": 1, "maximum": 1},
        "months": {"type": "integer", "minimum": 1}''')),
    ("M77", "a conditional enforcement needs no condition", "D6",
     rep('"required": ["strategy", "version", "condition"],', '"required": ["strategy", "version"],')),
    ("M78", "a before_anchor term needs no unit", "D18",
     rep('"required": ["kind", "quantity", "unit"],', '"required": ["kind", "quantity"],')),
    ("M79", "flags may be anything", "APPLY:/units_invariant: expected a string",
     rep('''        "units_invariant": {
          "type": "boolean",''', '''        "units_invariant": {
          "type": "string",''')),
    # ---- r2: delegations, Texas gas only, outcome order
    ("M81", "a legacy row of another state is adopted with Texas's owner types", "P4a",
     rep("    IF v_other IS NOT NULL THEN\n        RAISE EXCEPTION 'v5.4.2-18: backbilling_rules holds rows other", "    IF false THEN\n        RAISE EXCEPTION 'v5.4.2-18: backbilling_rules holds rows other")),
    ("M82", "the builder writes no delegations", "APPLY:it is a delegation to the utility, not law",
     rep("    IF (r ->> 'source_note') LIKE '16 TAC 7.45 does not reach this class;%' THEN\n        RETURN", "    IF false THEN\n        RETURN")),
    ("M83", "a law document passes for a row whose note says 7.45 does not reach it", "P7y",
     rep("        IF v_t ->> 'governs' IS DISTINCT FROM 'delegated_to_utility' THEN", "        IF false THEN")),
    ("M84", "a delegation may cite and note anything", "P7z",
     rep("        IF (v_t ->> 'citation') IS DISTINCT FROM '16 TAC 7.45' OR (v_t ->> 'note') IS DISTINCT FROM (p_row ->> 'source_note') THEN", "        IF false THEN")),
    ("M85", "a delegation may drop an enforcement cap", "P7ab",
     rep("        IF p_row ->> 'enforce_scope' IS DISTINCT FROM 'uncapped' OR p_row ->> 'favourable_duty'", "        IF false AND p_row ->> 'enforce_scope' IS DISTINCT FROM 'uncapped' OR p_row ->> 'favourable_duty'")),
    ("M86", "a delegation may drop a window", "P7ag",
     rep("           OR EXISTS (SELECT 1 FROM public.backbilling_rule_window_terms w WHERE w.rule_id = v_id) THEN", "           OR false THEN")),
    ("M87", "a delegation may drop a duty", "P7ad",
     rep("OR p_row ->> 'favourable_duty' IS DISTINCT FROM 'permitted'\n", "\n")),
    ("M88", "a delegation may drop supervisor evidence", "P7ae",
     rep("           OR (p_row -> 'requires_supervisor_evidence') IS DISTINCT FROM 'false'::jsonb\n", "")),
    ("M89", "a delegation may drop an adverse straddle", "P7ac",
     rep("           OR p_row ->> 'adverse_straddle' IS DISTINCT FROM 'include_whole' OR p_row ->> 'favourable_straddle' IS DISTINCT FROM 'include_whole'\n", "\n")),
    ("M90", "qualifying outcomes may be listed in any order", "X12",
     rep("    IF (v_terms -> 'anchor') ? 'qualifying_outcomes' AND\n", "    IF false AND (v_terms -> 'anchor') ? 'qualifying_outcomes' AND\n")),
    ("M91", "the fill keeps a delegation's anchor facet", "APPLY:is a facet, derived from the document",
     rep("           anchor_basis = CASE WHEN public.backbilling_rule_legacy_document(b.id) ->> 'governs' = 'law' THEN b.anchor_basis END", "           anchor_basis = b.anchor_basis")),
    ("M92", "the identity proof compares the anchor of a delegation, which the fill rightly clears", "APPLY:moved a row",
     rep("""                                       CASE WHEN b.source_note LIKE '16 TAC 7.45 does not reach this class;%' THEN NULL ELSE b.anchor_basis END, b.effective_from,""", """                                       b.anchor_basis, b.effective_from,""")),
    ("M93", "the basis vocabulary's comment is not rewritten", "G7",
     rep("a new basis is a vocabulary row, a new schema version of the kind, and a core change (v5.4.2-18).", "a new basis is a row plus a core change.")),
    ("M94", "a delegation may differ from its protected twin in units, delivery or outcomes", "P7ah",
     rep("        IF EXISTS (SELECT 1 FROM public.backbilling_rules q\n", "        IF false AND EXISTS (SELECT 1 FROM public.backbilling_rules q\n")),
    ("M95", "the note and the class need not agree", "P7ak",
     rep("    IF v_unreached IS DISTINCT FROM ((p_row ->> 'customer_class') = 'unprotected') THEN", "    IF false THEN")),
    ("M96", "the twin comparison ignores delivery path", "P7ai",
     rep("                           OR q.delivery_path IS DISTINCT FROM p_row ->> 'delivery_path')) THEN", "                           OR false)) THEN")),
    ("M97", "the twin comparison ignores outcomes", "P7aj",
     rep("                      AND ((SELECT array_agg(o ORDER BY o COLLATE \"C\") FROM (SELECT DISTINCT o FROM unnest(q.qualifying_test_outcomes) o) u)", "                      AND (false AND (SELECT array_agg(o ORDER BY o COLLATE \"C\") FROM unnest(q.qualifying_test_outcomes) o)")),
    ("M98", "the twin comparison ignores units", "P7ah",
     rep("                           OR q.units_invariant IS DISTINCT FROM (p_row ->> 'units_invariant')::boolean\n", "")),
    ("M99", "a delegation needs no protected row of its cause to compare with", "P7am",
     rep("        IF NOT EXISTS (SELECT 1 FROM public.backbilling_rules q\n", "        IF false AND NOT EXISTS (SELECT 1 FROM public.backbilling_rules q\n")),
    ("M100", "the twin is any protected row of the cause, whatever its dates", "P7am",
     rep("""                          AND daterange(q.effective_from, q.effective_to, '[)')
                              && daterange((p_row ->> 'effective_from')::date, (p_row ->> 'effective_to')::date, '[)')) THEN""", """                          ) THEN""")),
    ("M101", "the twin must begin on the same day", "P7an",
     rep("""                          AND daterange(q.effective_from, q.effective_to, '[)')
                              && daterange((p_row ->> 'effective_from')::date, (p_row ->> 'effective_to')::date, '[)')) THEN""", """                          AND q.effective_from = (p_row ->> 'effective_from')::date) THEN""")),
    # ---- r5: what the r4 review reproduced
    ("M102", "the builder lists a repeated outcome twice", "P9a",
     rep("""THEN (SELECT jsonb_agg(o ORDER BY o COLLATE "C") FROM (SELECT DISTINCT o FROM jsonb_array_elements_text(r -> 'qualifying_test_outcomes') o) u) END)),""",
         """THEN (SELECT jsonb_agg(o ORDER BY o COLLATE "C") FROM jsonb_array_elements_text(r -> 'qualifying_test_outcomes') o) END)),""")),
    ("M103", "the adoption check compares outcomes with repeats", "P9a",
     rep("""                THEN (SELECT jsonb_agg(o ORDER BY o COLLATE "C") FROM (SELECT DISTINCT o FROM jsonb_array_elements_text(p_row -> 'qualifying_test_outcomes') o) u) END
      INTO v_want;""", """                THEN (SELECT jsonb_agg(o ORDER BY o COLLATE "C") FROM jsonb_array_elements_text(p_row -> 'qualifying_test_outcomes') o) END
      INTO v_want;""")),
    ("M104", "a delegation's anchor may differ from its protected twin's", "P10a",
     rep("WHERE b.source_note LIKE '16 TAC 7.45 does not reach this class;%' AND q.anchor_basis IS DISTINCT FROM b.anchor_basis;",
         "WHERE b.source_note LIKE '16 TAC 7.45 does not reach this class;%' AND false;")),
    ("M105", "the twin's repeated outcomes count twice", "P9a",
     rep("""AND ((SELECT array_agg(o ORDER BY o COLLATE "C") FROM (SELECT DISTINCT o FROM unnest(q.qualifying_test_outcomes) o) u)""",
         """AND ((SELECT array_agg(o ORDER BY o COLLATE "C") FROM unnest(q.qualifying_test_outcomes) o)""")),
    ("M106", "the delegation's repeated outcomes count twice against its twin", "P9a",
     rep("""THEN (SELECT array_agg(o ORDER BY o COLLATE "C") FROM (SELECT DISTINCT o FROM jsonb_array_elements_text(p_row -> 'qualifying_test_outcomes') o) u) END)""",
         """THEN (SELECT array_agg(o ORDER BY o COLLATE "C") FROM jsonb_array_elements_text(p_row -> 'qualifying_test_outcomes') o) END)""")),
    # ---- battery-13 (the real citations)
    ("M80", "a close is allowed on the floor", "F13",
     rep("    SELECT max(d) FROM (\n        SELECT greatest(v.anchor_date, v.evaluated_at::date) AS d", "    SELECT max(d) FILTER (WHERE false) FROM (\n        SELECT greatest(v.anchor_date, v.evaluated_at::date) AS d")),
]


def sh(cmd: list[str], inp: str | None = None, env=None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, input=inp, capture_output=True, text=True, env=env)


def clone() -> None:
    for q in (f"DROP DATABASE IF EXISTS {DB}", f"CREATE DATABASE {DB} TEMPLATE tally"):
        sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-qc", q])
    sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", DB, "-qc", f"REVOKE TEMP ON DATABASE {DB} FROM PUBLIC, tally_app, tally_core"])


def battery(check: str) -> subprocess.CompletedProcess:
    if check == "F13":
        sh(["docker", "cp", str(ROOT / "tests/v5.4.2-13/battery-13.sql"), f"tally-pg:/tmp/b13_{DB}.sql"])
        return sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", DB, "-v", "ON_ERROR_STOP=1", "-q", "-o", "/dev/null", "-f", f"/tmp/b13_{DB}.sql"])
    return sh([str(HERE / "run-battery-18.sh"), DB])


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
        if re.fullmatch(r"P\d+[a-z0-9-]*", check):
            with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as f:
                f.write(patched)
            env = dict(os.environ, PATCH18=f.name)
            out = sh([sys.executable, str(HERE / "migration-18.py"), "tally"], env=env)
            os.unlink(f.name)
            text = out.stdout + out.stderr
            if re.search(rf"FAIL {re.escape(check)}[:\s]", text):
                print(f"{mid} caught at {check}: {what}")
            else:
                first = next((l for l in text.splitlines() if "FAIL" in l or "Error" in l), "")[:120]
                print(f"{mid} MISSED ({check}): {what}  [first: {first}]")
                missed += 1
            continue
        clone()
        a = sh(["docker", "exec", "-i", "tally-pg", "psql", "-U", "tally", "-d", DB, "-v", "ON_ERROR_STOP=1", "-q", "-1", "-f", "-"],
               "SET search_path = ''; SET check_function_bodies = on;\n" + patched)
        if a.returncode:
            last = next((l for l in a.stderr.splitlines() if "ERROR" in l), a.stderr.strip()[-200:] or "?")
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
        out = battery(check)
        text = out.stdout + out.stderr
        first = next((l for l in text.splitlines() if "FAIL" in l or "ERROR" in l), "")
        first = re.sub(r"^psql:[^:]+:\d+: ", "", first)[:120]
        if re.search(rf"FAIL {re.escape(check)}[a-z]?[:\s]", text):
            print(f"{mid} caught at {check}: {what}")
        else:
            print(f"{mid} MISSED ({check}): {what}  [first: {first}]")
            missed += 1
    print(f"{ran - missed}/{ran} caught")
    sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-qc", f"DROP DATABASE IF EXISTS {DB}"])
    return 1 if missed else 0


if __name__ == "__main__":
    sys.exit(main())
