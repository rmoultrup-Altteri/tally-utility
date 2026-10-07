# Handoff: v5.4.2-16 landed in tu.sql. Next: rule-terms v2 step 2 (the convention infrastructure)

**Generated**: 2026-10-07, end of session
**Branch**: `main` at `c86d811`, pushed. gas-billing-memory unchanged (`091c990`).
**Status**: Ready for the next piece. -16 is done: five review rounds, Ryan's approval, mirrored into `tu.sql`, and verified on a fresh build.

## Goal

Get to the C# core billing engine. The foundation every law and tariff row keys on is now in place in `tu.sql` (-16):
- places;
- premise memberships;
- utility profiles (owner type, system kind, commission jurisdiction).

Next comes the shared machinery that represents law: rule-terms v2 §12, step 2.

## Completed this session (2026-10-07)

- [x] **Review round 3** on r3 (`c49b1ec5`): all three said "not yet", converging on a `NaN` distance. Folded into r4 (`70134c1`):
  - NaN refused;
  - a state can't close under the profiles it governs, and a profile locks its state;
  - the time zone refuses an unzoned peer at the answering level;
  - fact keys must be citation-shaped;
  - the isolation refusal raises SQLSTATE 25000;
  - one unincorporated area per state;
  - residual R19.
- [x] **Round 4** on r4 (`a0b43c01`): Opus and Fable "ready", Codex "not yet" on a successor-state race (reproduced). Folded into r5 (`e1debe1`):
  - a profile locks *and re-reads the same* covering state row;
  - owner type split from system kind (`utility_system_kinds`);
  - extraterritorial and limited-purpose areas take the tax axis;
  - key rules tightened;
  - mutation attribution made strict;
  - residual R20.
- [x] **Round 5** on r5 (`24757cfc`): **all three "ready"**.
- [x] **Ryan's decision, 2026-10-07:** a profile is per system kind. `system_kind` joins the profile exclusion, and the lookup takes it. Residual R21: which system serves a premise.
- [x] **The r6 cleanup** (`c339035`), not re-reviewed:
  - owner wording: ownership, not operation; a nonprofit or public trust acting for a city is municipal;
  - residual R22 (untyped owners);
  - a jurisdiction pointer at an unknown place refused by name;
  - battery group V;
  - race R21 (a city-owned profile racing its state's close);
  - mutation catches attributed by line span.
- [x] **Verified on frozen r6** (patch `eec3f3a6`, battery `0b7e7174`):
  - strict apply ×2;
  - battery **97/97**;
  - races **R1–R21** (20 legs);
  - mutations **157/157**, each at its named check;
  - regressions 28/58/41/116/3/99/6, and -13's X1.
- [x] **Mirrored into `tu.sql`** (`c86d811`, Ryan approved):
  - 26,049 → **27,331 lines**, md5 `9c1d0813e64853cebcb5aaff519a4201`;
  - prefix and body checked with `cmp`;
  - `tally-pg` rebuilt with zero init errors;
  - catalog identity (9,964 lines) and counts identical to the patched clone;
  - every battery passes on the build, races too;
  - -16 re-applies cleanly;
  - entry added to `sql/DEPLOY-VERIFICATION.md`.
  - New counts: 109 tables, 93 policies, 429 FKs, 469 CHECKs, 19 EXCLUDE, 330 triggers, 440 functions, 652 indexes.

## Not Yet Done

- [ ] **Rule-terms v2 §12 step 2, the convention infrastructure, written once:**
  - `rule_term_schemas`;
  - the validator generator;
  - the facet pattern;
  - `rule_parameter_values`;
  - the YAML format and loader;
  - a `tally_core` role;
  - an audit-findings table;
  - CI (round trip, load, golden scenarios; a fictional-state fixture, which Opus noted).
- [ ] **First,** a short source inventory of what the two consumers need from step 2:
  - the -15 rewrite (Texas municipal deposits as the city's own tariff rows);
  - the -13 migration (backbilling).
- [ ] **Step 3:** the per-law-area sweep. **Step 4:** rebuild -15 on the convention, then migrate -13.
- [ ] **Kyle:** K1–K11 (K10: does practice match the statute; K11: which policies sit in an ordinance and which in a tariff).
- [ ] **Still open:** Ryan's R12 follow-ups on deposit waivers.

## Failed Approaches (Don't Repeat These)

- **Locking every row of a state, then checking containment against any row** (r4): a successor row committed while the profile waited was trusted unlocked, so its later close didn't wait. Lock the *covering* row, then re-read *that same row*, and refuse if it changed.
- **Owner type holding product or role values** (`propane_piped`, `master_meter`): a city-owned propane system could be recorded only one way. Who owns a system and what it runs are separate facts.
- **ETJ and limited-purpose areas on the regulatory axis only:** "in no city" had no positive tax record, and "unincorporated" meant two things depending on the axis.
- **A `btrim` key check:** strips U+0020 only, so tab, NBSP and doubled spaces passed. Whitelist the characters (the standing rule *blank checks whitelist alnum*).
- **SQLSTATE 40001 for an isolation refusal:** drivers retry it forever at the same isolation. `tu.sql` uses 25000.
- **Mutation "caught" = any ERROR without the target's PASS:**
  - credited earlier checks and fixture errors;
  - stricter rules exposed mis-aimed tests (M98 is J1's, not N9's; U10 used a place with a citation).

  Now a catch needs the target's own FAIL line, or the first error inside the target's own DO-block lines with every earlier check passing.
- **Battery fixtures refused by a different guard than the one named** (again): T7 (rate overlap), T10 (overlap), U6b (state check before the owner-type FK). Read each mutation's first failure.
- **Untestable on their own, and recorded as such:** the NOT NULL on `system_kind` (the trigger's service check refuses first), and `utility_system_kinds`' no-truncate trigger (the foreign key or the profiles guard refuses first).

## Key Decisions

| Decision | Rationale |
|---|---|
| A profile per system kind; the lookup takes `p_system_kind` (Ryan, 2026-10-07) | Law keys on the system (NM 62-3-3(G)(2)). Cheap now and meaning-changing once the core exists. The premise→system link is R21 |
| Five owner types plus three system kinds (distribution / piped_propane_distribution / master_meter) | NM, OH 4905.90(K) and 5117.01(D), TX 121.211(d): product and operator are tested apart from owner |
| Owner type = ownership, not operation; a nonprofit or trust acting for a city is `municipal` | LA 45:850 "owned by"; TX 101.003(8); OK 60 O.S. 176. Operator-only and other owners are R22 |
| ETJ and LPA on both axes | One meaning per row; LGC 43.130 makes an LPA a tax fact |
| Time zone: answer at the most specific level where any place has a zone; refuse an unzoned or disagreeing peer there | A partial load must refuse, not answer; a city's zone outranks its county's by design |
| A state row isn't succeeded under its profiles (R19) | A profile lies within one state row; no source has a state's identity change |
| r6 not re-reviewed | All three "ready" on r5. r6 is Ryan's decision plus should-fixes, re-verified in full |

## Current State

**Working:** `tally-pg` runs the **-16 build** (`tally` = `tu.sql` at `9c1d0813`). Only `postgres` and `tally` exist.
**Broken:** nothing.
**Uncommitted changes:** none apart from this HANDOFF and the CHANGELOG entry.

## Code Context

```sql
-- in tu.sql since c86d811
public.premise_places_as_of(p_service_location_id uuid, p_on date, p_axis text)
  RETURNS TABLE (place_id uuid, kind_code text, state_code text, place_code text, name text, specificity int, relation text, distance_miles numeric)
public.premise_time_zone_as_of(p_service_location_id uuid, p_on date) RETURNS text
  -- no_data_found: nothing answers, or an unzoned peer at the answering level; cardinality_violation: disagreeing zones
public.utility_service_profile_as_of(p_tenant_id uuid, p_service_type text, p_system_kind text, p_state_code text, p_on date)
  RETURNS utility_service_profiles   -- 5 args since r6; the 4-arg form is dropped
public.place_lock_key(uuid) RETURNS bigint          -- citers take it shared, a close takes it exclusive
public.assert_place_read_committed(text)            -- raises 25000 invalid_transaction_state
```

Vocabularies (platform, immutable):
- `place_kinds`;
- `place_fact_kinds`;
- `utility_owner_types` (municipal, political_subdivision, special_district, investor_owned, cooperative);
- `utility_system_kinds`;
- `place_membership_evidence_kinds`.

Lock order for a profile: the state row, then the owning place. Migrations close places in that order too (R18).

## Resume Instructions

1. Fetch both repos:
   ```
   cd ~/code/tally-utility && git pull --ff-only
   cd ~/code/gas-billing-memory && git fetch && git log --oneline HEAD..origin/main
   ```
   - Expected: nothing new, or Kyle's UI or ruling commits. Read any rulings first.
2. Confirm the build: `docker exec tally-pg psql -U tally -d tally -Atc "select count(*) from pg_tables where schemaname='public'"`.
   - Expected: **109**. If you get 100, the container predates `c86d811`: rebuild (`sql/DEPLOY-VERIFICATION.md`, -16 entry).
3. Read `application/rule-terms-convention-v2-2026-10-06.md` §§10–12, then write the **step-2 source inventory**: what the -15 rewrite and the -13 migration each need from the infrastructure.
   - Method: memory `source-inventory-first-triage-by-rule`.
   - Raise with Ryan only the conflicts between rules.
4. Draft step 2 as v5.4.2-17 (the next number at drafting), on the house review loop:
   - freeze the hash;
   - three reviewers;
   - triage by rule;
   - one revision per round.

## Warnings

- **The -16 harnesses assume `tally` is the -14 build.** `mutations-16.py` and the review briefs clone `tally` and apply -16 to it, which over the -16 build only tests re-application. Use a -14 base, or retire them; -16 is landed.
- **`tu.sql` is append-only.** Mirror a patch only after Ryan approves.
- **Revoke TEMP after every `CREATE DATABASE … TEMPLATE`.**
- **Freeze the hash before any review; one revision per round.**
- **Don't trust from-memory citations.** Check them against `application/places-sources/` or saved texts.
- **Never `git add -A` in gas-billing-memory.**
- **Explain choices to Ryan in prose, not menus.** Ask only on rule conflicts.
- **Background reviewers' reports truncate at about 4 KB.** Read their output files.
