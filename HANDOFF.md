# Handoff: v5.4.2-16 places and applicability. Relaunch review round 3 on the frozen r3 build

**Generated**: 2026-10-06, end of session
**Branch**: `main` at `c3f1a50` (pushed). gas-billing-memory unchanged (`091c990`).
**Status**: In progress. -16 is in review round 3, which was stopped mid-run at Ryan's request. No round-3 findings exist. -16 is a DRAFT, not yet copied into `tu.sql`.

## Goal

Get to the C# core billing engine. Before that, the schema needs a foundation that every law and tariff row will key on:
- places;
- each premise's dated membership in places;
- each utility's owner type and commission status.

It also needs a convention for representing law that doesn't need DDL for every new state shape.

## Completed this session (2026-10-06)

- [x] **A new way of working** (memory `source-inventory-first-triage-by-rule`):
  - inventory the real sources before drafting;
  - triage review findings by standing rules;
  - ask Ryan only when the rules conflict.
- [x] **The -15 deposits round-3 revision was built and verified** (`7442c68`). It is now **superseded as a design** by rule-terms v2. Its ledger, due rows, races and tests carry over.
- [x] **Deposit source survey across 10 more states:** 29 shapes the typed-column schema can't hold. See `application/deposits-source-survey-2026-10-06.md`.
- [x] **Rule-terms convention v2, ADOPTED by Ryan:** `application/rule-terms-convention-v2-2026-10-06.md`.
  - A law row is a typed key plus a `terms jsonb` document holding strategy choices and parameters only.
  - That document is validated on every write against `rule_term_schemas`.
  - Typed facets copied from the document carry the database's reference checks.
  - Logic lives in named, versioned strategies in the C# core, selected by name, never by state.
  - It uses OpenFisca's parameter-file format, not its runtime.
  - It reverses audit rule 2; a correction note is in the audit.
  - Reviews and research are in `application/rule-terms-review/`.
- [x] **Places source inventory:** `application/places-source-inventory-2026-10-06.md`, research in `application/places-sources/`.
  - **Texas gas law does not bind city-owned gas systems.** Utilities Code §101.003(7)(A) and §102.002; municipal deposits fall under LGC §552.0025(c).
  - K10 is answered from the statute; Kyle should confirm practice. K11 was added.
- [x] **v5.4.2-16 drafted**, then revised twice after review rounds 1 and 2.
  - Patch: `sql/v5.4.2-16-places-and-applicability.sql`.
  - Tests: `tests/v5.4.2-16/` (battery, races, mutations, review).
  - Round 1: all three said "not yet"; triaged in `review-findings-16-r1.md`.
  - Round 2: all three said "not yet", on the same item (the time-zone tie); triaged in `review-findings-16-r2.md`.
  - **Current build: patch `c49b1ec5`, battery `af1013f9`** (frozen as `tests/v5.4.2-16/review/*-frozen-r3.sql`).
  - Verified (all on clones with TEMP revoked):
    - strict apply ×2;
    - battery **68/68**;
    - races **R1–R12**, each two-session leg with the wait observed;
    - mutations **110/110**, each at its named check;
    - regressions 28/58/41/116/3/99/6, and -13's X1.

## Not Yet Done

- [ ] **Relaunch review round 3** with the same three reviewers on the frozen r3 build (Resume step 2).
- [ ] Triage round-3 findings by rule. One revision per round. Repeat until "ready".
- [ ] Copy -16 into `tu.sql` (procedure below) and add a `sql/DEPLOY-VERIFICATION.md` entry, **after Ryan approves**.
- [ ] **Rule-terms v2 §12, step 2, the convention infrastructure, written once:**
  - `rule_term_schemas`;
  - the validator generator;
  - the facet pattern;
  - `rule_parameter_values`;
  - the YAML file format and loader;
  - a `tally_core` role;
  - an audit-findings table;
  - CI (round trip, load, golden scenarios).
- [ ] **Step 3, the sweep:** a source inventory per law area.
- [ ] **Step 4, the rebuilds:**
  - rewrite -15 on the convention (Texas municipal deposits are the city's own tariff rows);
  - migrate -13 (backbilling).
- [ ] **Kyle:**
  - K1–K9;
  - K10 (does practice match the statute; does ch. 183 bind cities?);
  - K11 (which policies sit in the city's ordinance and which in a tariff).
- [ ] **Still open from earlier:** Ryan's R12 follow-ups on deposit waivers. The DIVERGENCE is settled in v2 §8 by a forfeiture event.

## Failed Approaches (Don't Repeat These)

- **Typed column per law setting** (audit rule 2): 5 shapes in two -15 review rounds, then 29 more in the survey; every one needs DDL. Use rule-terms v2 instead.
- **Pinning only the close side of an advisory-lock handshake to READ COMMITTED:** a REPEATABLE READ writer waits on the lock, then reads the place from its pre-wait snapshot, and commits against a closed place (r1 B1). Pin **both** sides (`assert_place_read_committed`).
- **Checking a premise's state only when a membership is inserted:** the state can be edited afterwards (r1 B2). Use a `BEFORE UPDATE OF state` guard, plus `FOR SHARE` on the premise when a membership is inserted.
- **Reading both axes for the time zone with `ORDER BY specificity LIMIT 1`:** picks arbitrarily between disagreeing equal-rank candidates (r2 N1). Refuse when the distinct zones at the top specificity number more than one.
- **A close-floor count with no `rolsuper`/`rolbypassrls` guard:** RLS hides other tenants' rows from it (r1 B4).
- **Validating `service_locations.state` with a CHECK:** breaks -12's landed battery, which keeps `' tx '` and `'Texas'` on purpose. Read it as `upper(btrim(state))`, as -12 does (residual R10).
- **Battery cases refused by another guard first** (about 12 this session). Typical causes:
  - a time-zone fact on Travis County blocking a close test;
  - TRUNCATE cascading into a tenant table's guard;
  - a race premise that already had a committed membership;
  - an edit test where the "close only" rule refuses before the jsonb-comparison guard;
  - a test role lacking EXECUTE on `pg_temp` helpers or the RLS policy functions.

  Build fixtures where only the named guard can refuse, and read the harness's first failure for every catch made outside its named check.
- **A Python `s.replace(old, new)` where `old` was empty:** inserted `new` between every character (battery grew to 525,937 lines). Recovered by removing every copy of `new`. Always `assert s.count(old) == 1`.
- **Codex `read-only` cannot reach docker:** it reviews statically and writes repro SQL, and the main session runs it.

## Key Decisions

| Decision | Rationale |
|---|---|
| Rule-terms v2 (Ryan, 2026-10-06) | Typed key + validated `terms` + facets; strategies in the core. Converged reviews (Opus, Fable, Codex) plus research (Oracle CC&B, OpenFisca, Guidewire) |
| OpenFisca's format, not its runtime | Python microsimulation; no records or ledger; our core is C# |
| Strategy pattern selected by the name in `terms`, never by state | A per-state class rebuilds the branch on a state's name that audit rule 4 forbids |
| Places shared (no tenant); memberships and profiles per tenant, dated, evidenced | Ryan's 2026-09-22 proposal; inventory D1–D3 |
| Axes (regulatory/tax) dated separately | An annexation has an ordinance date and a sales-tax quarter (Tax §321.102) |
| Exclusivity groups: one county; one of {city, limited-purpose area, ETJ, unincorporated} | LGC ch. 42–43; "unincorporated" in law = ETJ or `unincorporated_area` (a law row predicate) |
| Explicit `outside` relation with optional distance; absence = unknown | TX §103.053, KS 66-104f, NM 3-25-3 |
| Owner type and commission status separate and dated, per governing state; an owning place may be in another state | Elections change status without changing ownership; border cities |
| Void (stamped, once, with a reason) for rows wrong from their first day | Settled now because every reader filters voided rows (costly to add later) |
| A Texas state place is `time_zone_uniform = false`, so the lookup refuses without a county or city | El Paso and Hudspeth are Mountain |
| Cross-state outside distances not modelled (R16) | No source in hand |

## Current State

**Working:** `tally-pg` runs the -14 build (`tally` database), with neither -15 nor -16 applied. Every clone was dropped; only `postgres` and `tally` exist.
**Broken:** nothing.
**Uncommitted changes:** none apart from this HANDOFF and the CHANGELOG entry.

## Code Context

```sql
-- v5.4.2-16 (draft) — key functions
public.place_lock_key(p_place_id uuid) RETURNS bigint                      -- advisory key: citers shared, close exclusive
public.assert_place_read_committed(p_what text) RETURNS void               -- both sides of the handshake
public.place_citation_close_or_void(p_old anyelement, p_new anyelement, p_what text, p_end_col text) RETURNS anyelement
public.premise_places_as_of(p_service_location_id uuid, p_on date, p_axis text)
  RETURNS TABLE (place_id uuid, kind_code text, state_code text, place_code text, name text, specificity int, relation text, distance_miles numeric)
public.premise_time_zone_as_of(p_service_location_id uuid, p_on date) RETURNS text   -- refuses: no data, non-uniform state, conflict (cardinality_violation)
public.utility_service_profile_as_of(p_tenant_id uuid, p_service_type text, p_state_code text, p_on date) RETURNS utility_service_profiles
```

Tables:
- platform: `place_kinds`, `place_fact_kinds`, `utility_owner_types`, `place_membership_evidence_kinds`, `places`, `place_facts`;
- tenant: `premise_place_memberships`, `utility_service_profiles`;
- plus `jurisdictions.place_id`.

Non-obvious logic:
- The handshake relies on a READ COMMITTED trigger re-reading after it waits on the lock: the VOLATILE plpgsql statements take fresh snapshots.
- `exclusivity_group` and `place_kind` are copied from the kind on insert; the caller can't set them.
- The edit rule (`place_citation_close_or_void`) decides close or void by whether `void_reason` changed.

**Harnesses:**
- Mutations: `python3 tests/v5.4.2-16/mutations-16.py [Mnn …]`. It needs `tally` to be the -14 build, uses database `m16`, and runs serially.
- Races: `bash tests/v5.4.2-16/races/place-close-16.sh <clone>`, on a throwaway clone of a patched build.
- Each mutation line prints its first failure. Check by hand any catch made outside its named check.

**Copying -16 into `tu.sql`** (after approval):
1. Append the patch body after a 4-line banner, as at `tu.sql` 25,931 and 26,050.
2. `cmp` the prefix and the body.
3. Rebuild: `docker build -q -t tally-postgres -f postgres/Dockerfile . && docker rm -f -v tally-pg && docker run -d --name tally-pg -e POSTGRES_PASSWORD=tally tally-postgres`, then wait for "PostgreSQL init process complete".
4. Diff `tests/v5.4.2-14/parity/catalog-identity.sql` between the clone and the fresh build.

## Resume Instructions

1. Fetch both repos:
   ```
   cd ~/code/tally-utility && git pull --ff-only
   cd ~/code/gas-billing-memory && git fetch && git log --oneline HEAD..origin/main
   ```
   - Expected: nothing new, or Kyle's UI or ruling commits (read any rulings first).
2. **Relaunch round 3** (Ryan: "the same reviewers can pick up in the new session"). Nothing to re-freeze:
   - **Check the hashes:** `md5 -q tests/v5.4.2-16/review/patch-16-frozen-r3.sql` should give `c49b1ec5075e9b7eee16cdb9ad23603e`; the battery file should give `af1013f9e2a4150afe986ab3a43903da`.
   - **Opus and Fable:** a general-purpose Agent each (model `opus`, then model `fable`), background. Prompt: "Read and follow the review brief at `tests/v5.4.2-16/review/review-brief-16-r3.md` exactly. Use database `opus16r3` / `fable16r3`. Write OUTPUT_PATH to `<scratchpad>/review16/opus-r3.md` / `fable-r3.md`. Never modify repo files."
   - **Codex:**
     - Copy the brief and replace its `## Output` section with: "Write the full review as your final message (it is captured to a file); under 12,000 characters. You run read-only and cannot reach docker: review statically, and where a finding needs proof, write the exact SQL repro script into your review."
     - Run it: `PATH=~/.nvm/versions/node/v24.15.0/bin:$PATH codex exec -s read-only -C ~/code/tally-utility -o <scratchpad>/review16/codex-r3.md - < brief-codex-r3.md` (background).
   - Expected: three reports, each within about 10 minutes. Reproduce every finding on a clone before accepting it.
3. Triage into `tests/v5.4.2-16/review/review-findings-16-r3.md`, with the deciding rule for each item.
   - If any item is blocking: fold it in, re-verify everything (strict ×2, battery, races, all mutations, regressions), freeze r4.
   - If all three say "ready": ask Ryan to approve copying -16 into `tu.sql`.
4. Then rule-terms v2 step 2, the convention infrastructure. Start with a short source inventory of what the -15 rewrite and the -13 migration need from it.

## Warnings

- **`tu.sql` is append-only.** Copy patches into it only after Ryan approves.
- **Freeze the hash before any review; one revision per round.** The r3 artefacts are frozen; don't edit them.
- **Revoke TEMP after every `CREATE DATABASE … TEMPLATE`** (memory `template-clone-drops-acl`).
- **Don't trust from-memory citations.** Check against the saved texts; the research agents keep them in the session scratchpad.
- **Never `git add -A` in gas-billing-memory.**
- **Raise only conflicts with Ryan** (memory `source-inventory-first-triage-by-rule`). Explain in prose, not menus.
