# v5.4.2-18 review round 1 — Opus

Frozen hashes checked: patch db6179fd… (703 lines), battery 5a4f0271… — both match; the patch equals sql/v5.4.2-18-backbilling-rule-terms.sql.

Ran: strict apply on opus18pre (clone of `tally`, TEMP revoked) — OK; battery-18 — all pass; migration-18.py (copy with DB names prefixed `opus_`) against `tally` — P1–P7 all pass; registered schema == law/backbilling/backbilling.v1.schema.json (jsonb equal). No function body in public references a dropped column/table (only the adoption check, by design); a sweep of every pg_class description finds no stale name beyond the two the patch rewrote. tally_core keeps SELECT on rules, anchor bases, causes, classes.

## Verdict: NOT YET

### B1 (blocking). `system_kinds = NULL` binds piped propane (and master-meter) systems the law excludes
R1 (patch 656-668) itself reads 101.003(7)(B) as excluding LPG distribution, yet the rows bind every system kind, including `piped_propane_distribution` ("propane or LP-gas by pipe") and `master_meter` (whose own source note is TX Util. Code 121.211(d), a safety-only "gas master meter operator").
Reproduction (opus18pre, rolled back): an investor_owned TX gas profile with system_kind piped_propane_distribution; `rule_law_row_as_of(..., 'piped_propane_distribution', 'TX', {protected, meter_error}, 2026-01-15)` returns the adopted 7.45 row. That is wrong law answered, not unknown law refused.
Fix: `system_kinds = {distribution}` in 3.2 (default + span), the law file, M7, migration-18 P1; decide master_meter with Kyle (default: out). Cost framing: schema-level data on never-edited law rows; later it is a close plus successor that falsely dates the propane binding; now it is free.

### B2 (blocking pending Ryan's ruling). The eight "unprotected" rows are delegations adopted as law
Their source note: "16 TAC 7.45 does not reach this class; ordinary limitations law and the filed tariff govern, outside this table." That is the V8 `delegated_to_utility` document. The migration adopts them as `governs: law` with uncapped / permitted / include_whole, and the adoption check forbids anything else (patch 185-187). Under a law document the core reads "uncapped" as the law's permission; under a delegation it refuses without the utility's tariff row (-17 comment on rule_tariff_row_as_of). Meaning-changing; settle now (memories: utility owns regulated values; munis' policy = tariff rows). Recommended default: adopt them as delegated (citation "16 TAC 7.45", note = rest of source note), with the adoption check accepting exactly that document for exactly rows whose note says so. The three R-39 "never pending counsel" rows are law placeholders; leave as law but see N4.

### S1. Incorporated areas: §7.45's applicability is not all jurisdiction statuses
§7.45's preamble: the minimum standards apply in unincorporated areas; inside incorporated areas utilities include them in their service rules only to the extent they do not conflict with standards lawfully established by the municipality. `commission_jurisdiction` is utility-wide (-16 profile), so it cannot express this per premise. Consequence: for an IOU serving inside a city with its own lawful standards, the lookup gives 7.45, and the template tariff check would refuse a city-standard tariff looser than 7.45. Add a residual (and a Kyle question); do not claim "every jurisdiction status" without it.

### S2. River authorities
101.003(7), as R1 quotes it, makes a gas utility "a person or river authority". A river authority's owner type is political_subdivision / special_district, which R1 says "finds no row" as if correct. It fails closed (refusal), so not blocking, but R1's reading is wrong for river authorities; say so in R1/R2.

### S3. Qualifying outcomes are not in canonical order
Reproduction: a ZZ test_date rule with qualifying_outcomes ["slow","fast"] is accepted and stored so. The insert check canonicalises windows "so one law has one document" but not outcomes; a seed restating the same law as ["fast","slow"] is then refused as different terms. Add an order (byte order) check to backbilling_rule_insert_check and a case.

### N1. The adoption check's anchor comparison is vacuous in the real path
enforce_rule_row_history (-17:2328-2330) passes `v_new || v_set`, and v_set carries the facet anchor_basis derived from the document (rule_row_prepare -17:2095). So patch line 204 compares the document with itself. Coverage survives (outcomes ⇔ test_date via schema + line 210; identity hash 3.6 includes anchor_basis), but "compares every key" overstates. Builder and check also share the citation regex and window jsonb construction; true independence is P1b / K2 (Python, battery), which is fine — say so.

### N2. Fixed database names in migration-18.py (m18_a..f) and mutations-18.py (m18mut), with DROP DATABASE IF EXISTS
Concurrent reviewers or CI runs drop each other's databases. Take a prefix argument.

### N3. G4 is narrower than its claim
It looks at three objects and three phrases. Sweep every pg_description (and prosrc) for the ten column names and three table names instead; my sweep is clean, so it would pass.

### N4. Citations that are not law
The lead-clause rule yields "R-39: no 7.45 billing cap" (a ruling id) ×3 and "No 7.45 billing cap on an estimation catch-up" (a statement); meter_error and non_registering enforce `never` on (4)(E)(vi), which their citation omits. Source notes keep the rest; R4 admits the five. Fine for adoption; the law file should carry real clauses when written.

### N5. Preconditions worth stating
The fill needs a superuser or BYPASSRLS owner under READ COMMITTED (-17's template); otherwise the DO block fails whole. A database holding a -13 row on a vocabulary row -13 allowed but v1 does not name (e.g. battery-13's old notice_date anchor or customer_denied_access condition) fails the fill with a validator message: correct fail-closed, worth one line in PRECONDITION.

### Checked and fine
Ordering (defaults evaluated once; no row updated before the -13 history trigger is dropped; registration's legacy-row checks pass); idempotence (P2); partial state impossible (one DO block; P4–P6 untouched); FKs class/cause/anchor_basis kept; enforce_condition FK dropped with its column before its table; stamps hashed; window-term uniqueness and kind/quantity pairing carried by insert check and schema; battery-13 C/Z rewrite keeps every protection (C5/C11/C12/C14/C15/C16d-e now D3-D5, D10-D11, D19, S3, or inherent); CI runs migration-18 while `tally` is pre-18 and skips after.
