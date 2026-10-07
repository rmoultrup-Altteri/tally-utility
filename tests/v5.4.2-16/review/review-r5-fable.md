# Review round 5 — v5.4.2-16 places and applicability (Fable)

**Frozen artefacts checked:** patch `24757cfc95fb3be08e416f8504c0dbc1`, battery `3add58b717852d9d5d4804cc934c3150` — both match the brief. `sql/v5.4.2-16-places-and-applicability.sql` and `tests/v5.4.2-16/battery-16.sql` carry the same hashes, so the mutation harness (which reads the repo files) ran against the frozen text.

**Clone:** `fable16r5` (TEMPLATE tally, TEMP revoked, strict apply with `search_path=''`, `check_function_bodies=on`: clean). Races on `fable16r5race`. Mutations on `fm16` via a copy of the harness pointed at the frozen files.

**Verified on the clone**
- battery-16: **90/90**, no FAIL or ERROR lines;
- races R1–R20: **19/19 PASS**, each two-session leg seen waiting;
- round-4 mutations M134–M147 plus my own: see §3;
- 60-odd single-session probes (`probe-a.sql`, `probe-b.sql` in this directory) and five extra two-session legs (`race-x.sh`).

## Verdict: **ready**

No blocking item. Three should-fix items: a residual to state (one system kind per tenant/service/state), a missing race leg for a municipal profile under a state close, and three battery gaps my mutants exposed; the rest are notes. Every one of round 4's fixes held under live attack.

---

## 0. Did round 4's fixes hold?

### B1 — the profile's state handshake (patch-16-frozen-r5.sql:977-994)

**Holds.** The profile selects the row that covers it (unlocked), takes that row's advisory lock shared, then re-reads *that row by id* with the containment predicate; a NULL after the re-read is refused with the "closed while this waited" message. I attacked it from every direction the brief lists:

| probe | result |
|---|---|
| R19 (successor committed while it waited) | PASS, B seen waiting |
| R20 (two rows, covering one not first by id) | PASS, B seen waiting |
| X1: closer closes FA at 2030 and holds; profile [2021,2025) waits, re-reads, **accepted** (still covered) — both commit, consistent | as designed |
| X2: profile [2021,2025) held; close at 2030 waits, then **succeeds** (profile ends before the close) | as designed, symmetric with X1 |
| X3: closer closes FD at 2030 **and inserts a successor from 2030** in one transaction, holds; profile [2021,open) waits on the old row, re-reads it, **refused** | the successor is never trusted unlocked |
| X4: afterwards a profile [2031,open) locks the successor and is accepted | as designed |
| P2a/P2b: a gap between state rows ([1950,2000) and [2010,open)): a profile inside the gap, or spanning it, refused | as designed |
| P2c: a profile spanning two **contiguous** rows ([1999,2001) over [1950,2000)+[2000,open)) refused; P2d from the successor's first day and P2e ending on the old row's end accepted | R19 residual holds exactly at the boundary |
| P10: the close floor's "governed by it" leg fires on the covering row of a two-row state | yes |

**New hole from the fix?** None found. One observation, not a hole: the lock order "state place, then owning place" (patch:975-976) is only stated for the profile; a platform transaction that closes a city and then its state in one transaction, racing a profile owned by the city, **deadlocks** (I reproduced it: `ERROR: deadlock detected` on the closer; the profile committed; the database is consistent). PostgreSQL detects it, so it ends one writer, as residual R18 already says for memberships. Worth one clause in R18 ("or a migration closing two places a profile cites, in the other order"). Note.

### S-own — owner vs system (patch:294-328, 995-1000)

**Holds.** Probes P4a–P4j: master meter refused for sewer, piped propane refused for electric, unknown and NULL system kinds refused by the service check (the NULL one before NOT NULL fires — harmless), a co-op piped-propane system and a city-owned master meter accepted; a special_district owned by a county, a political_subdivision owned by a city, and a municipal owned by its own ETJ all refused.

**Do five owner types and three system kinds hold `application/places-sources/`?** Owner types: municipal, political_subdivision, special_district, investor_owned, cooperative. Against the sources:
- Arkansas's "municipal system leased to a nonprofit corporation" (§23-4-201(b)) and Illinois's "operated by lessees or operating agents" (3-105(b)(1)) are **municipal**: the vocabulary row says "owned *or operated* by a city or town", and the statutes exclude on ownership. Holds.
- Louisiana gas utility districts, NM gas associations, OK public trusts, CA districts → **special_district**. Holds.
- Texas "river authority" (Utilities Code §101.003(7): a gas utility *includes* a river authority) → special_district with commission_jurisdiction true. Holds.
- **Illinois 3-105(b)(1) also excludes a "public institution of higher education"** (utility-type-10-states.md:660). A university-owned gas system is none of the five. It is not a customer we will have, and the vocabulary takes a new row, but the inventory's A1 says "≥7 kinds" and this one is in the sources. Note; a sixth row `state_institution` or a one-line residual.
- System kinds: distribution / piped_propane_distribution / master_meter cover NM 62-3-3(G)(2), OH 4905.90(K), OH 5117.01(D), TX 121.211(d). Nothing else in the sources keys on the system. Holds.

**Modelling consequence, should-fix (state it):** `utility_service_profiles_no_overlap` keys on (tenant, service_type, state_code) — **not** system_kind. Probe P3: a tenant with a `gas / distribution / TX` profile cannot record a `gas / piped_propane_distribution / TX` profile for the same days (exclusion violation), nor a master-meter one. A city that runs natural-gas distribution in town and a piped-propane system in an outlying subdivision — real, if uncommon — has one profile. The law keys on the system (NM takes piped LPG in; OH leaves master meters out), so the second system's law would be unreadable. This is the right shape *now*: the lookup returns one row per (tenant, service, state, date) and nothing yet says which system serves a premise. But it should be a stated residual (R21): "one system kind per tenant, service and state at a time; a utility running two kinds of gas system in one state records its primary; when a premise (or meter) names its system, system_kind joins the exclusion key and the lookup takes it" — so the next step knows this is an additive change with a lookup-signature change, not a surprise.

### S-tax — ETJ and limited-purpose areas on the tax axis (patch:195-198)

**Holds.** P5a–P5c: on the tax axis ETJ + LPA, ETJ + unincorporated, ETJ + city each refused by `premise_place_memberships_exclusive`; P5d ETJ (tax) + city (regulatory) over the same days accepted (D1); P5f outside-ETJ + outside-city + within-unincorporated on tax accepted. Time zone: with only the ETJ (tax) recorded the lookup refuses (P5e: ETJ is not a zone-carrying kind, Texas not uniform); with a county on regulatory it answers Central. The state guard: ETJ places carry the parent's state_code, so a premise in another state is refused as before (M3 covers the kind-agnostic path). Close floors: an ETJ closes neither under a tax membership (P11a) nor does the city close under its open ETJ child (P11b).

**Test gap (should-fix):** the battery proves the ETJ takes the tax axis (U7) and the LPA the regulatory axis, but **never puts an LPA on the tax axis**. My mutant X14 (`limited_purpose_area` membership_axes → `['regulatory']` only) survives the whole battery (§3). One `mem(..., 'austin_lpa', 'tax', ...)` line in U7 closes it.

### S-key — the key rule (patch:554-556)

**Holds** for everything round 4 asked: `§` alone, `16 TAC § 7.45`, ` §7.45`, `§7.45 `, `§ 7.45`, `--`, the en dash, and `(a)` refused; `§7.45`, `305 ILCS 20/13(k)`, `HB 1-2`, `x/y`, `a:b;c,d`, `HB_1`, `a' b` accepted. Edge cases the shape admits (notes, all R20 territory): `§§7.45`, `7.45§`, `§-1`, `a(`, `a--b`, `é7`, and the full-width digit `７` (PostgreSQL's `[[:alnum:]]` is Unicode-aware under a UTF-8 locale, so `７` and `7` are two keys). None is a wrong answer; each is a spelling the loader must not produce.

### T — the round-4 test cases

U1–U10 are each refused by the guard they name (I read every one; U4, U5, U9 check the message). Fine.

### T-attr — the mutation harness

Read `caught()` (mutations-16.py:409-420): a battery catch needs `FAIL <check>[a-z]?:` or the run stopping inside the target with every earlier check's PASS present; a race catch needs `FAIL Rn`; setup errors are a miss. Regex boundaries are right (`FAIL M1[a-z]?:` does not match `FAIL M10:`). Two properties worth knowing, neither a hole:
- a mutation that makes an **earlier** check fail is reported MISSED (strict, correct);
- a mutation that makes the target block raise a *different* SQLSTATE than its handler expects stops the run inside the target and counts as caught — that is a genuine failure of that check, so the attribution is honest.
The harness reads the repo files, not the frozen copies; their hashes match today, so the "146/146" claim is for the frozen text.

---

## 1. Does it hold the spec?

| req | held / residual / missed |
|---|---|
| P1 state | held (kind `state`, membership from the premise's own column) |
| P2 county | held (kind + time_zone, weather_station, sales_tax_rate facts) |
| P3 city | held (census_population, gas_rate_jurisdiction_retained, residential_gas_taxable, sales_tax_rate); franchise/street charge stays text (R4) |
| P4 limited-purpose area | held as a kind on both axes; gas-rate treatment R6 |
| P5 ETJ | held, both axes |
| P6 utility rate area | residual R3 (jurisdictions, undated, pointer added) |
| P7 tax jurisdictions | held (transit_authority, special_purpose_district + type + rate facts, quarter-dated) |
| P8 time zone | held (lookup, refuses rather than guesses; seed for TX) |
| P9 weather station | held (county fact) + existing wna_zones |
| P10 inside/outside with distance | held (relation + positive finite distance; absence = unknown) |
| A1 owner type | held (five) + system kind separate; note the IL higher-education owner |
| A2 commission jurisdiction | held, dated, separate boolean |
| A3 size thresholds | residual R7 |
| A4 local adoption | held (keyed fact) |
| A5 enforcing body | residual R11 |
| A6 customer attributes | residual R12 |
| A7 market role | residual R8 (out, as the inventory says) |
| D1 dates per axis | held (one annexation = two memberships) |
| D2 evidence | held (kind, reference, date ≤ today) |
| D3 many units, per-kind cardinality | held (exclusivity groups; districts stack) |

**Modelling choices for where this goes next:** law rows keyed on owner type — the vocabulary is a stable text key, and system_kind sits beside it on the same row, so a law row can key on either; tax jurisdictions on their own axis with quarter-dated rates — right; annexation — right; a utility in two states — per-state profiles, an owning place in any state — right (P4i); a city system serving outside its limits — "outside the owning city" is derivable from the premise's municipal_status membership vs the profile's owning place, or recorded explicitly as an outside relation with distance — right. The one choice to state is the single system kind per tenant/service/state (above).

## 2. Integrity

Nothing found that puts the records in a refused state or makes a lookup answer wrongly. What I tried beyond §0:
- **Void/close edits** (P7): close then void keeps the close and stamps the void; reopen, un-void, and re-close of a voided row refused. Client-sent closed_at/closed_by on a close are overwritten (P8).
- **app.user_id garbage or empty** (P9, P12): refused upstream by `get_user_tenant_id()`'s uuid cast inside the RLS policy (22P02) — fail closed, pre-existing tu.sql behaviour, not this patch's.
- **Fact succession boundary** (P13): a county zone closed 2026-01-01 with a successor from that day reads the old zone on 2025-12-31 and the new one on the day.
- **Jurisdiction pointers** (P14): at an ETJ or a county accepted (the column comment says "a city" but the guard allows any non-state open place — fine, R3); unpointing to NULL accepted; a pointer at a **nonexistent** place is refused, but with the "is a state, has a close date, or has not begun" message (patch:1091-1095) because `v_place` is a null row. The FK would refuse too. Membership got a "not found" name in round 4 (U9); the pointer did not. Note.
- **Parent kinds** (P15): ETJ under an LPA, SPD under an ETJ, city under a county, LPA under the unincorporated area, unincorporated under a county — all refused. **Two ETJ rows for one city at once, different codes, accepted** (P15d); an ETJ with the city's own code accepted (P21, the overlap exclusion is per kind). A city has one ETJ; nothing enforces it. Loader discipline; note.
- **Close date checks** (P16): a close before the start and a zero-length close are refused by `places_range_check`.
- **State guard** (P23): → ZQ and → NULL refused under memberships (the NULL message prints an empty state name; cosmetic); respelling accepted.
- **GA premise on a date in the state gap** (P19): places lookup refuses; on a covered date it answers; a county under the new row takes memberships; the new row does not close under its open county (P20).
- **Two-lock deadlock** (above): detected, one writer aborted, state consistent.
- RLS: lookups are invoker-rights (L8 proves another tenant's premise and profile are not found); the close needs BYPASSRLS/superuser (C6); the six platform tables carry no tenant. `jurisdictions.place_id` is a bare id to shared data — R3, as before.

## 3. Tests

Battery 90/90, races 19/19, every round-4 case checked that only its guard refuses it. Mutation results (my harness copy, frozen files, DB `fm16`):

Round-4 mutations **M134–M147: 14/14 caught, each at its named check** (M134 at R19, M135 at R20 — reported as `FAIL R2` because the mutant breaks the R2 leg's wait too, and the harness then stops; M141/M142 at U6, M143 at U7, M144/M145 at U8, M146 at U9, M147 at U10, M136–M140 at U1–U5).

My extra mutants (12), against the frozen battery and races:

| mutant | what it does | result |
|---|---|---|
| X1 | drop the profile's re-read after the lock (patch:982-987) | **caught** at R19 (R14 also fails) |
| X2 | governed-profile leg keyed on `OLD.place_code` | survives — equivalent (a state's code is its state_code) |
| X3 | `master_meter` allowed for water | caught at U6 |
| X19 | system-kind check against any vocabulary row of the service | caught at U6 |
| X15 | ETJ exclusivity group NULL | caught at M5 |
| X20 | void unstamped (shared function) | caught — at N4, the membership void, so the harness reports it MISSED for N5; same as M88 |
| X18 | pointer trigger lets a nonexistent place through (FK still refuses) | survives — refused either way |
| X21 | drop `p.state_code = v_state` in `premise_places_as_of` (patch:1145) | survives — defence in depth; the trigger and state guard already hold it |
| **X16** | the profile takes the **owning place's** lock in place of the state's when it has one (`coalesce(NEW.owning_place_id, v_state_place)`, patch:981) | **survives** — R13, R14, R19, R20 all use `investor_owned`; no race leg has a profile **with an owning place** governed by the state being closed. A municipal profile is the launch case. |
| **X14** | `limited_purpose_area` on the regulatory axis only (patch:195) | **survives** — U7 puts only the ETJ on tax |
| X6 | every within-place is a time-zone candidate, zone-carrying kind or not (patch:1185) | survives — no case has an LPA (specificity 20, no zone) at the city level beside a zoned city on the other axis |
| X17 | the first state select ignores the range (the re-read still checks) (patch:979) | survives — a **false refusal**: in a two-row state the first select may pick the wrong row and the re-read then refuses a covered profile with "closed while this waited"; R20 greps for that message and passes. No positive case records a profile on the successor row of a two-row state (my P2d does, and is accepted on the real patch). |

Caught 18/26; the eight survivors are two equivalents (X2, X18), one defence-in-depth (X21), one mis-attributed by my own mutant (X20), and **four test gaps** (X16, X14, X6, X17), none of which is a defect in the patch — I checked each path by hand on the clone and it behaves as the header says.

**Missing cases** (none blocking):
1. A race leg R13/R14 with a **municipal** profile (owning place + governing state) — the lock on the state must be taken even when an owning place is (X16).
2. An LPA on the tax axis in U7 (X14).
3. Time zone: a premise within an LPA on regulatory and a zoned city on tax answers the city's zone (X6).
4. A profile on the successor row of a two-row state is **accepted** (X17; the race fixture RV already has the rows).
5. A second ETJ of the same city at once, if a rule is wanted.

## Findings, classified

**Blocking:** none.

**Should-fix**
0. Race legs: every profile in R13/R14/R19/R20 is `investor_owned`; mutant X16 (state lock replaced by the owning place's lock when one exists) survives. Add one leg with a **municipal** profile owned by a TX city and governed by a race state, closed while the profile is in flight — the launch customers' shape. The patch itself is right (the state lock precedes the owning-place branch, patch:981 vs 1014); the suite does not pin it.
1. State residual **R21**: one system kind per tenant, service and state at a time (`utility_service_profiles_no_overlap`, patch:940-943); a utility with two kinds of gas system in one state is a later, additive change (system_kind into the key, the premise naming its system, the lookup taking it). Reproduced: P3.
2. Battery: put a limited-purpose area on the **tax** axis once (U7 only puts the ETJ there); mutant X14 survives today. Two smaller positives worth a line each: an LPA beside a zoned city answers the city's zone (X6); a profile on the successor row of a two-row state is accepted (X17 — a false-refusal mutant R20 cannot see).

**Notes**
- IL 3-105(b)(1) "public institution of higher education" is an owner the five types do not name (source line 660); a sixth row or a sentence in A1's residual.
- `enforce_jurisdiction_place` names a nonexistent place as "a state, has a close date, or has not begun" (patch:1091-1095); say "not found", as the membership does.
- Two ETJ rows for one city at once are accepted (P15d); loader discipline or an exclusion on (parent, kind) for ETJ.
- R18: add the two-place close order deadlock (reproduced).
- Key shape admits `§§7.45`, `7.45§`, `§-1`, `a--b`, full-width digits — all R20 (spelling is the loader's).
- The state-guard message prints an empty name for a NULL state (patch:886).
