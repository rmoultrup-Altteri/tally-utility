# Review round 3 — v5.4.2-16 places and applicability (Opus)

**Artefacts checked.** patch `patch-16-frozen-r3.sql` md5 `c49b1ec5075e9b7eee16cdb9ad23603e`, battery `battery-16-frozen-r3.sql` md5 `af1013f9e2a4150afe986ab3a43903da`. Both match the brief.
**Method.** I cloned `opus16r3` from `tally`, revoked TEMP, and strict-applied the patch (`search_path=''`, `check_function_bodies=on`, one transaction). It applied cleanly. The battery ran clean (all PASS through G4). I wrote probes as `tally_app` with `app.user_id` set, and platform rows as owner (scripts `p1.sql`, `p2.sql`, `fx.sql` in `scratchpad/review16/opus/`). I wrote 12 extra mutations against the frozen patch with my own runner (`mut.py`): each built a fresh clone and ran the battery. I did not run `mutations-16.py`, because it hard-codes database `m16` and the repo paths. The races I checked by reading `races/place-close-16.sh`. I dropped both of my databases at the end.

**Verdict: not yet — one blocking item (B1). It is a one-line fix with a one-case test.** Everything else round 2 asked for holds. The rest is should-fix or a note.

---

## 0. Did round 2's fixes hold?

| Item | Holds? | What I tried |
|---|---|---|
| **N1** time-zone conflict | **Holds for what it claims** (patch:1057-1072). | Two counties on two axes with different zones are refused, and the battery shows it. Agreeing duplicates answer. Mutation X31 (aggregating over all levels) is caught. **Two gaps remain, both should-fix or note (S2, N-1 below):** a same-level peer that carries **no** zone fact is invisible, so the other peer answers (reproduced: El Paso on regulatory plus Harris with no fact on tax gives `America/Denver`). A city's zone silently overrides its county's: El Paso city set to Chicago plus El Paso county set to Denver gives `America/Chicago`. |
| **S-a** jurisdiction points at an open place | **Holds** (patch:979-984). The close counts every pointer (patch:435-436). Races R10 and R11 cover both orders. | Mutation X4 removes the "has begun" leg (`effective_from <= CURRENT_DATE`, patch:980) and **survives** (T1). |
| **S-b** VOID | **Holds.** | Re-void is refused (Q5b). A void that also closes is refused (Q6). A void is stamped with time and user even when the caller passes `voided_at`/`voided_by` (Q5). A replacement row for the same days answers the time zone (Q5c). The same place re-recorded with a corrected start after a void is accepted (Q11). Every reader filters voided rows: `premise_places_as_of` (patch:1029), and through it the time zone; the profile lookup (1114); the state guard (796); the close floor for memberships (424) and profiles (427); and all three exclusions (645, 652, 855). I found nothing that should ignore voided rows and does not. Racing a void against a close of the same row serialises on the row lock, and the loser then sees `voided_at` and is refused. A concurrent replacement insert waits on the exclusion and succeeds after commit. **Tests:** X1 (the close floor counts voided *profiles*) and X9 (`no_repeat` counts voided rows) **survive** (T1). |
| **S-c** unincorporated kind | **Holds** (patch:172-173, seed 1149-1153). Within ETJ plus within unincorporated on one axis is refused by the group. | "One per state" (findings r2) is **not enforced**: a second TX `unincorporated_area` (code `UNINC-B`) is accepted (Q8). The header does not claim it, so this is a note (N-3). |
| **S-d** profile's state is a state place | **Holds at insert** (patch:882-888). | **It can be broken by a later close** (S1): a profile governed by QZ, then the owner closes the QZ state place. The close is **accepted** (Q7). Mutation X15 (existence only, no range containment) **survives** (T1). |
| **S-e** ranges | **Partly.** Number ranges hold (patch:514-515). Evidence after its recording is refused (759, 889). | **Distance is not finite: `NaN` passes** (B1). The rate boundary at exactly 1 is untested (X3 survives). Evidence dated `0001-01-01` is accepted (N-4). |
| **S-f** `Etc/` zones | **Holds** (patch:518-521). | `CST6CDT`, `GMT0` and lower-case `posix/…` all fail the Area/Location pattern. |
| **S-g** key whitespace | **Only ASCII spaces** (patch:475, `btrim`). | `'HB 1'`, `'HB 1<TAB>'`, `'HB 1<NBSP>'` and `'HB  1'` coexist on one place, kind and range (Q10). This is should-fix S3. |
| **S-h** state change pinned to RC | **Holds as stated.** | Mutation X10 is caught by race R8. |
| **S-i / S-j** | Residuals R17 and R18 are stated. | — |

---

## Blocking

### B1. `distance_miles = 'NaN'` passes, and a law predicate then answers instead of refusing
- **Where:** `premise_place_memberships_relation_check`, patch:636-638: `(distance_miles IS NULL) OR (distance_miles > 0)`. In PostgreSQL, `NaN` sorts above every number, so `'NaN'::numeric(8,3) > 0` is **true**. `numeric(8,3)` does refuse `Infinity` (22003), but it does not refuse `NaN`.
- **Reproduction (Q1, as `tally_app`):** insert an `outside` membership for premise O1 in a TX municipality with `distance_miles = 'NaN'`. It is **accepted** and stored as `NaN`. `SELECT 'NaN'::numeric(8,3) > 3` is `t`. `premise_places_as_of` returns the NaN distance.
- **Why it blocks:** round 2 settled S-e as "Distance must be finite", and the header's refusals depend on it. This is exactly the failure the brief names: "a lookup return a wrong answer instead of refusing". A Kansas 66-104f predicate ("more than three miles outside", residual R15) evaluates to *true* for a premise whose distance is not a number.
- **Fix:** `AND distance_miles <> 'NaN'::numeric` in the outside leg. Add a battery case that only this leg refuses: an outside relation with distance `NaN`.

---

## Should-fix

### S1. A state place can close under the profiles that name it (S-d broken after insert)
- The close floor counts profiles only by `owning_place_id` (patch:426-427), never by `state_code`. So "a governing state with no state place in force over the range" is refused at insert (882-888) but can be produced by a close.
- **Reproduction (Q7):** state place QZ with no facts or children. As `tally_app`, record an open gas profile governed by QZ. As owner, `UPDATE places SET effective_to='2022-01-01'` on QZ. The close is **accepted**. `utility_service_profile_as_of(...,'QZ', 2024-…)` still answers, because it never checks the state place.
- The profile insert also takes no lock on the state place (it locks only the owning place, patch:902), so even with the floor extended, the two would race.
- **Fix:** in the close, when the closing place is `kind_code='state'`, add a floor leg `u.state_code = OLD.state_code AND u.voided_at IS NULL AND (u.effective_to IS NULL OR u.effective_to > NEW.effective_to)`. In the profile insert, take the state place's lock shared. Otherwise, state the gap as a residual ("states are not closed"). The fact and child floors make a TX close impractical today, which is why this is should-fix rather than blocking.
- **A related modelling note:** the insert check requires *one* state row to contain the whole range. If a state row is ever closed and succeeded, a profile spanning the seam can never be recorded. The check probably wants "covered by the union of state rows", not "contained in one".

### S2. The time-zone conflict check sees only peers that carry a fact
- `premise_time_zone_as_of` computes `top` over candidates already inner-joined to a `time_zone` fact (patch:1058-1066). A same-specificity place the premise is within, but which has no zone fact, is not a candidate. Its disagreement is invisible, and the remaining peer answers.
- **Reproduction (Q12):** premise within El Paso County (Denver) on regulatory and within Harris County (no zone fact) on tax. The answer is `America/Denver`. That is the N1 situation (two counties on two axes) answered rather than refused, whenever loading is partial. R2 says counties are loaded "with their facts", but nothing makes a county carry one, and the TX seed deliberately gives most counties none.
- **Fix:** take `top` over all *within* places whose kind is listed for `time_zone` in `place_fact_kinds.place_kinds`, and refuse when any place at that level has no fact. This keeps "a city with no zone fact falls through to its county" only if `top` is computed per level that has at least one fact *and* every place at that level has one. Alternatively, state the precondition as a residual and test it.

### S3. Fact keys are normalised for ASCII spaces only
- patch:475: `fact_key = btrim(fact_key)`. `btrim` strips only U+0020. Tab, newline, NBSP and doubled interior spaces all make distinct keys for one law (Q10). This is the same family as the standing rule that blank checks whitelist `[[:alnum:]]`.
- **Fix:** constrain the key's form, e.g. `fact_key ~ '^[[:alnum:]]([[:alnum:] .()§/-]*[[:alnum:])])?$' AND fact_key !~ '  '`. Or, since the key is "the law's citation code", require the citation-code pattern the law tables already use.

### T1. Mutations the battery and races do not catch (my runner, frozen patch, fresh clone each)

| # | Mutation | Result |
|---|---|---|
| X1 | close floor counts **voided profiles** (drop `u.voided_at IS NULL`, patch:427) | **survives** (N17 covers memberships only) |
| X3 | rate range `<` → `<=` at `value_max` (patch:515) | **survives** (N12a tests 5, not 1) |
| X4 | jurisdiction may point at a place **not yet begun** (drop patch:980) | **survives** |
| X9 | `no_repeat` counts voided rows (drop `WHERE (voided_at IS NULL)`, patch:645) | **survives**. N4 replaces with a *different* place. The commonest void (a wrong start date for the same place, Q11) is untested. |
| X15 | profile state check by existence only, not range (patch:884) | **survives** (N6a uses a state that does not exist) |
| X19 | evidence dated *today* refused (`>` → `>=`, patch:759) | **survives** (boundary untested) |
| X10 / X28 | state change / pointer not pinned to RC | caught by races R8 / R6 |
| X13, X16, X30, X31 | stamp, state pointer, owning-place range, specificity | caught |

There is also no `NaN` case (B1).

---

## 1. Does it hold the spec?

| Req | Status |
|---|---|
| P1 state | **Held.** It is a state place plus the premise's own column, read normalised. Write validation is residual R10. |
| P2 county | **Held** (kind; `time_zone` and `weather_station` facts; tax and regulatory axes). Notice and cap rules are law rows later. |
| P3 city | **Held** (kind; population, retained jurisdiction, taxable and sales-tax-rate facts). Franchise text is residual R4. |
| P4 limited-purpose | Kind **held**; the law's answer is residual R6. |
| P5 ETJ | **Held.** |
| P6 utility rate area | **Residual** R3. |
| P7 sales-tax jurisdictions | **Held** (transit is exclusive, districts stack, rate fact with quarter dates). |
| P8 time zone | **Held**, apart from S2. |
| P9 weather | **Held** (fact plus the existing `wna_zones`). |
| P10 inside/outside with distance | **Held, apart from B1.** Cross-state is residual R16. |
| A1 owner type | **Held** (7 types). |
| A2 commission jurisdiction | **Held**, as a separate fact. |
| A3 | Residual R7. |
| A4 local adoption | **Held** (keyed fact), apart from S3. |
| A5 / A6 / A7 | Residuals R11 / R12 / R8. |
| D1 | **Held** (per-axis dates). |
| D2 | **Held** (evidence kind, reference and date). |
| D3 | **Held** (groups: one county, one municipal status, one transit; districts stack). |

**Modelling against what comes next.** Law rows keyed on owner type and jurisdiction status fit the profile directly. A utility in two states gets one profile per state. A city system serving outside its limits is an `outside` membership with a distance (fix B1). Annexation is two axis rows. Points to note:
- `utility_owner_types.owning_place_kinds` is immutable, so if Kansas's "any political subdivision" later needs townships or districts under `political_subdivision`, that is a new owner-type row or a reviewed repair (N-5).
- The single-row state containment in S1 matters for any future state-row succession.

## 2. Integrity: other attacks that held
- **RLS:** stamps cannot cross tenants, because RLS derives the tenant from `app.user_id` itself (tu.sql:21190). The lookups refuse invisible premises and profiles. Exclusions are keyed per premise or per tenant, so they give no cross-tenant oracle. Places are shared by design.
- **State guard:** respelling is not a change. A NULL or `'Texas'` target with TX memberships is refused. The only other trigger on `service_locations` is `set_updated_at`, so nothing else rewrites `state`.
- **Advisory protocol and RC:** both sides take the lock and pin RC; the volatile trigger functions re-snapshot per statement. Races R1-R12 cover the orders.
- **Close floor:** memberships, profiles, facts, children and pointers, with the end-of-day boundary correct (N16).

## Notes
- **N-1** City-over-county precedence is silent: a city fact that disagrees with its county's answers without a refusal (Q4). This is by the "most specific" design, but a city's parent is the state, so nothing ties the two.
- **N-2** "Evidence no later than today" uses `CURRENT_DATE` in the session's `TimeZone`. A session set to `Pacific/Kiritimati` gains a day.
- **N-3** "One unincorporated area per state" (findings r2 S-c) is not enforced (Q8). Either enforce it or drop the claim.
- **N-4** There is no lower bound on evidence dates (`0001-01-01` is accepted, Q3). `census_population` accepts `3.5` and has no maximum (Q9).
- **N-5** Owner-type vocabulary rows are immutable, including `owning_place_kinds` (see modelling).
- **N-6** A jurisdiction may point at an `unincorporated_area` or a transit authority. That is probably fine, but it is not stated.
