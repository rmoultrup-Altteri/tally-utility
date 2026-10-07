# Review v5.4.2-16 round 3 — places and applicability (Fable)

**Artefacts verified.** patch md5 `c49b1ec5075e9b7eee16cdb9ad23603e`, battery md5 `af1013f9e2a4150afe986ab3a43903da` — both match the brief. The working copies (`sql/v5.4.2-16-places-and-applicability.sql`, `tests/v5.4.2-16/battery-16.sql`) are byte-identical to the frozen ones, so `mutations-16.py` tests the frozen revision.
**Environment.** clone `fable16r3` (TEMPLATE tally, TEMP revoked); strict apply clean (search_path '', check_function_bodies on; the AC-32 tail passed). Battery **68/68 PASS**. Races **R1–R12 PASS**, each two-session leg seen waiting. My own work: `scratchpad/review16/fable/probes.sql` (Q1–Q12), `race_excl.sh` (E1–E3), `mut_extra.py` (12 extra mutations against the frozen files, own clone `fable16m`, dropped). Line numbers are the frozen r3 patch. No repo file was touched.

## Verdict: **not yet** — one blocking item (one line), the rest should-fix and test gaps

Every round-2 fix I could attack holds, with one exception: the S-e disposition "distance must be finite" was recorded as folded but is not in the patch. `'NaN'` is accepted as a distance, stored, and returned by the lookup (B1). Everything else is a should-fix or a test gap.

---

## 0. Did round 2's fixes hold?

| # | Fix in r3 | Holds? | How I tried to break it |
|---|---|---|---|
| **N1** zone conflict | `premise_time_zone_as_of` 1057–1072: both axes, `max(specificity) OVER ()` among within-places carrying a `time_zone` fact in force, `array_agg(DISTINCT)` at the top, refuse if >1 | **Yes** | Battery N1 (two counties, two axes). My X6 (DISTINCT dropped: agreeing duplicates would refuse) is caught; X12 (top computed before the within filter) is caught by N2b. Window is over the filtered set, so a city *without* a zone fact never becomes "top". Probe Q2: regulatory City A (Denver fact) + tax City B (no fact) + Travis (Chicago) → `America/Denver`, silently. That is the stated design (candidates = places carrying a zone), not a tie; see note N3. |
| **S-a** pointer needs an open place | `enforce_jurisdiction_place` 979–984 | **Yes** | Q4a: a place beginning tomorrow → refused; Q4b: beginning today → accepted (`<=`, right). N9 + R10/R11 cover the close date and both race orders. **Test gap:** the not-yet-begun leg (980) is untested — my X1 drops it and the battery passes 68/68. |
| **S-b** VOID | `place_citation_close_or_void` 669–706; exclusions 645, 652, 855 ignore voided; lookup 1029; state guard 796; close floor 424, 427; profile lookup 1114 | **Yes** | Q3a–g: `voided_by` alone, `closed_by` alone, void+`closed_at`, void+close in one statement, close after void, un-void — all refused (23001). A caller-supplied `voided_by` of another tenant's user is stripped and restamped from the session (Q3e). Q3h: the same place is re-recorded after a void (no_repeat ignores it). Q3i: a void *after* a close is accepted (row keeps `valid_to` and both stamps) — reasonable; say so in the comment (N1). Q11: T2 voiding T1's rows touches 0 rows (RLS). E3: a void in flight does not make the close wait (the void takes no lock); the close reads the unvoided row and refuses — conservative, right. **Test gaps:** X2 (close floor counts voided *profiles*, 427) and X3 (no_repeat's `WHERE voided_at IS NULL`, 645) are both MISSED by the battery: no voided profile has an owning place, and no case re-records the *same* place after a void (N4 voids Unincorporated and then records Austin). |
| **S-c** unincorporated kind | row 172–173, group `municipal_status`, axes both, parent state, specificity 5; seeded 1149–1153 | **Yes** | N3c; Q12: outside City B + within Unincorporated on one axis is accepted (coherent). M86 covers the group. |
| **S-d** profile's state | 882–888: a state place in force over the whole range | **Yes at insert; not at close** | N6a (no state). Q6: YY closed 2025, profile 2020–2030 → refused (the `@>` leg). **But** my X4 (`@>` → `&&`) is MISSED: the battery has no profile that runs past its state's end. And the invariant is not kept by the close floor (S1 below, probe Q5). |
| **S-e** ranges, finite distance, evidence ≤ today | `place_fact_kinds.value_min/max` 186–187, 198–200, check 513–515; `distance_miles > 0` 638; evidence 759–763, 889–893 | **Ranges yes; distance NO** | N12 (rate 5, −0.01, population −3; rate 0.02, population 0). Q7a: rate exactly 1 refused (`<`). Q7b: population `1e400` accepted (max open — fine). **Q1a: `distance_miles = 'NaN'` is accepted** (B1). `'Infinity'` is refused by numeric(8,3) overflow (Q1b), so only NaN gets through. **Test gaps:** X5 (`<` → `<=` on value_max) and X7 (`> 0` → `>= 0`) MISSED; X8 (profile `evidence_date` made nullable, r2 T-gap 7) still MISSED. |
| **S-f** Etc/ zones | 517–521 | **Yes** | N13a; Q7d `posix/America/Chicago` refused by the `[A-Z]` first letter. |
| **S-g** key whitespace | `place_facts_key_check` 475 (`fact_key = btrim(fact_key)`) | **Yes** | N13b. Inner double blanks (`'HB  1'`) still coexist with `'HB 1'`; cosmetic. |
| **S-h** state-change pin | 790–793 | Stated | R8/R9. |
| **S-i / S-j** | R17 / R18 | Residuals | — |
| **T** races assert the wait | `place-close-16.sh` 63–92 | **Yes** | R1–R12 all report the second session seen waiting on my clone. My E1/E2 (two memberships racing the county exclusion; two profiles racing no_overlap): the second session waits on the index entry, then gets `exclusion_violation` — PostgreSQL's guarantee, holds. |

**Did a fix introduce a new hole?** The VOID is the only fix with reach, and every reader I could find (two exclusions per table, both lookups, the state guard, both close-floor legs) filters `voided_at IS NULL`; the stamp is session-derived; a voided row is frozen. Nothing new. The jurisdiction rule's `CURRENT_DATE` is the session's date — a client in a UTC+14 zone can point at a place a day "early"; trivial.

Round-1 fixes touched by round 2 (B1 pins, B2 share-lock, B3 both-axes read, B4 narrowed close) rechecked via R1–R12 and the battery: hold.

---

## 1. Does it hold the spec?

| Req | Held? | Where |
|---|---|---|
| P1 state | held; R10 | kind 162; `upper(btrim(state))` 729, 1016 |
| P2 county | held | kind 164; `time_zone`, `weather_station`, `sales_tax_rate` |
| P3 city + unit facts | held; R4 | kind 166; `census_population`, `gas_rate_jurisdiction_retained`, `residential_gas_taxable`, `sales_tax_rate`, `local_adoption` |
| P4 limited-purpose area | held; R6 | kind 168, exclusive with city, regulatory axis only (city taxes barred — right) |
| P5 ETJ | held | kind 170 |
| — unincorporated (r2 S-c) | held | kind 172 |
| P6 rate areas | residual R3 | `jurisdictions.place_id`, undated |
| P7 tax jurisdictions, rate history | held | tax-axis kinds; `sales_tax_rate` dated per place; `residential_gas_taxable` on districts |
| P8 time zone | held | fact + lookup, refuses on conflict (N1) |
| P9 weather | held | `weather_station` on counties; WNA zone stays on `jurisdictions` |
| P10 inside / outside N miles | held, flawed | `relation`, `distance_miles` — NaN (B1) |
| A1 owner type | held | 7 rows 258–264 with `owning_place_kinds` |
| A2 jurisdiction status | held | `commission_jurisdiction`, dated, per governing state |
| A3 size | residual R7 | |
| A4 local opt-in | held | keyed `local_adoption` |
| A5 enforcing body | residual R11 | |
| A6 class / attributes | residual R12 | |
| A7 marketers | residual R8 | |
| D1 dates per axis | held | L6 |
| D2 evidence | held | kind, reference, date; dated ≤ today |
| D3 cardinality | held | exclusivity groups; districts stack |

**Modelling for what comes next** (unchanged from r2 — all sound): law rows key on `utility_service_profile_as_of(tenant, service, state, date)`'s (owner_type, commission_jurisdiction); tax jurisdictions are tax-axis memberships plus per-place rate facts; annexation is two memberships with two dates and the exclusion forces the old city to be closed first; a utility in two states has one profile per governing state with the owning place in any state; a city system serving outside its limits records `outside` rows (with distance) and its rate areas as `jurisdictions` (R3). One new observation: `political_subdivision` takes only a `county` as owner (259). A township or parish system (Louisiana parishes are counties by another name — fine; Ohio/Illinois townships are not) will need a kind; a vocabulary row later, no schema change.

---

## 2. Integrity

### B1 (blocking, one line). `NaN` is accepted as a distance; the lookup returns it; a distance predicate over it answers "false", not "unknown"

`premise_place_memberships_relation_check` 636–638 requires `distance_miles > 0` for an outside relation. In PostgreSQL `'NaN'::numeric > 0` is **true** (NaN sorts above every number), and `numeric(8,3)` accepts NaN (it refuses Infinity by overflow — Q1b). Probe Q1a, as `tally_app`:

```
Q1a HOLE: NaN distance accepted: NaN
Q1c lookup returns outside distance = NaN ; (distance <= 3) = f
```

So the row the findings file says is refused ("Distance must be finite", r2 S-e) is stored, `premise_places_as_of` hands it back, and the Kansas 66-104f predicate the core will write (`distance_miles <= 3`, R15) evaluates false — "more than three miles outside", a wrong answer rather than a refusal. Fix: add `AND distance_miles <> 'NaN'::numeric` (NaN equals NaN in numeric, so this works) to the relation check at 638, a case (`'NaN'` refused, `check_violation`), and a mutation. Blocking because it is a round-2 disposition recorded as folded that is not in the patch, and the brief's first question is whether the fixes held; it is also the only way left to put a membership in a state the record says is refused.

### Nothing else broke. What I tried and could not break
- The void edit rule from every direction (Q3a–i); its stamps; its invisibility to every reader (section 0).
- Both exclusions under a real race (E1, E2); a void in flight against a close (E3).
- The pointer rule at both boundaries (Q4a/b) and both race orders (R10, R11).
- NULL legs: `void_reason` NULL on a close path, a NULL `app.user_id` on a void (`voided_by` NULL — r1 N1 stands), a pointer at a non-existent place (refused by the coalesced not-begun leg before the FK).
- Tenant leakage: T2 cannot see, void or close T1's rows (Q11, G1–G2); lookups are invoker-rights and refuse an invisible premise; shared tables carry no tenant data.
- A premise's state under closed (N15), voided (N18) and open memberships; a respelling.
- Isolation pins on every citing write and the close (R3–R6, R8).

---

## 3. Tests

The 110 mutations in `mutations-16.py` plus the battery catch everything in the trigger bodies that round 1 and 2 named. With 12 extra mutations against the frozen files (`mut_extra.py`: 5 caught, 7 missed), the misses are all real gaps:

| Gap | Mutation missed | Why | Cheap case |
|---|---|---|---|
| T1 | X1: pointer at a place not yet begun (980) | N9 tests only the close-date leg | a place from `CURRENT_DATE + 1`; pointer refused |
| T2 | X2: close floor counts voided profiles (427) | no voided profile has an owning place (N5's is investor-owned) | void a municipal profile, close its city |
| T3 | X3: `no_repeat` counts voided rows (645) | N4 re-records a *different* place after the void | re-record the same place after a void (my Q3h) |
| T4 | X4: profile's state in force only *somewhere* in the range (884) | no state closes under a profile in the battery | a state closed at 2025, profile 2020–2030 refused (my Q6) |
| T5 | X5: `value_max` inclusive (515) | N12 tests 5, not 1 | `sales_tax_rate` = 1 refused |
| T6 | X7: zero distance (638) | no case tries 0 | `outside` with distance 0 refused |
| T7 | X8: profile `evidence_date` nullable | r2 T-gap 7 was listed as folded but no case sends NULL | the profile twin of M7b |
| — | B1 | no guard exists | `'NaN'` refused |

Caught (for the record): X6 (DISTINCT dropped) at L-section, X9 (state guard reads open rows only) at N15, X10 (close-date leg) at J1b, X11 (void unstamped) at N4c, X12 (top before the within filter) at N2b.

---

## Should-fix

- **S1. The close floor does not count profiles keyed on a state place's `state_code`** (422–437). Probe Q5: state YY (no children), an open gas profile for YY; the owner closes YY at 2025 — accepted; `utility_service_profile_as_of(…, 'YY', 2026)` still answers while `premise_places_as_of` for a YY premise refuses. The S-d invariant ("a profile's state is a state place in force over its range", header 112–113) holds at insert only. A state does not dissolve in practice, but the header claims the close refuses "a profile … in force after it". One UNION leg: `OLD.kind_code = 'state' AND u.state_code = OLD.state_code AND u.voided_at IS NULL AND (u.effective_to IS NULL OR u.effective_to > NEW.effective_to)`; and a case. (Memberships are safe: every non-state place is a child of its state, so a state with any place under it cannot close under them.)
- **S2.** Test gaps T1–T7 above. T2 and T3 are the only two VOID readers nothing pins; T7 was recorded as folded in r2.
- **S3.** `assert_place_read_committed` raises `serialization_failure` (353). Drivers and pools that auto-retry 40001 (Npgsql with a retry policy, most ORMs' "transient error" lists) will retry a transaction that can never succeed at that isolation. `invalid_transaction_state` (25000) or `feature_not_supported` says what it is. Pre-existing from r1; noting it before the C# core inherits it.

## Notes

- **N1.** A void after a close is accepted (Q3i): the row keeps `valid_to`, `closed_*` and `voided_*`. Sensible (the close was itself a mistake); say so in the comment at 665–668, which reads as if close and void were alternatives.
- **N2.** A close refuses if the caller echoes any column imprecisely (Q9: `created_at` rounded to milliseconds → 23001). An ORM that writes the whole row back will trip this; the fix is on the app side (`UPDATE … SET valid_to = …` only), worth a line in the HANDOFF for the core.
- **N3.** The zone lookup's candidate set is "within-places carrying a zone fact": a city with a fact on one axis outranks a county on the other silently (Q2). Right by the design, but the comment at 1053–1056 says "the most specific candidates must agree" without saying a place without a fact is not a candidate. One clause.
- **N4.** `evidence_date` has no lower bound (Q10: `0001-01-01`); `census_population` no upper (Q7b: `1e400`). Neither matters.
- **N5.** Texas is seeded from 1900-01-01 (1139) and a child must lie within its parent, so a county dated from its creation (Texas counties: 1836–1931) is refused (Q8: 1846 → 23514). The Census loader (R2) will have to date counties ≥ 1900 or the TX row must be re-seeded earlier. Worth a sentence in R2 before the loader is written.
- **N6.** The pointer accepts any non-state kind, including Unincorporated Texas (Q4c). r2 N1 stands (a kind list when R3 is done).
- **N7.** `closed_by` / `voided_by` are stamped from the session without `assert_same_tenant_user` (only `created_by` is, 726). RLS makes it moot for `tally_app`; a platform admin's id lands on a tenant's row, which is -05's own convention.
- **N8.** `US/Central` is refused (Q7c, 23514) — the regex requires an Area/Location of ≥2 letters before the slash, which `US` satisfies, so the refusal comes from `pg_timezone_names` lacking the backward link on this build. Conservative, fine; a loader should write canonical ids anyway.

Clone `fable16r3` dropped after this review.
