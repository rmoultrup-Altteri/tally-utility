# Review v5.4.2-16 round 2 — places and applicability (Fable)

**Artefacts verified.** patch md5 `24998853c2a18e4c49ab0325a4a8ad4e`, battery md5 `ef1c7da0baa64ee8cf727fb931e40b07` — both match the brief. The working copies (`sql/v5.4.2-16-places-and-applicability.sql`, `tests/v5.4.2-16/battery-16.sql`) are byte-identical to the frozen ones, so `mutations-16.py` (which reads the working files) tests the frozen revision.
**Environment.** clone `fable16r2` (TEMPLATE tally, TEMP revoked), strict apply clean (search_path '', check_function_bodies on). Battery **50/50 PASS, 0 FAIL**. Races **R1–R9 PASS**. My own probes: `scratchpad/review16/{probes_tz,probes_misc}.sql`, `race_jur.sh`, `race_state_rev.sh`, `mut_extra.py` (18 extra mutations against the frozen files, own clone `fable16m`). Line numbers are the frozen r2 patch unless marked. Clone dropped after the review.

## Verdict: **not yet** — one blocking item, cheap; the rest are should-fix and test gaps

Round 1's fixes all hold and I could not break any of them (section 0). The one blocking item is a hole the B3 fix opened: reading the time zone on both axes creates ties between places of equal specificity, and the lookup resolves a tie by picking one rather than refusing (B1 below). The header's own claim is "Lookups that REFUSE rather than guess" (line 63).

---

## 0. Did round 1's fixes hold?

| # | Fix in r2 | Holds? | How I tried to break it |
|---|---|---|---|
| B1 READ COMMITTED pins | `assert_place_read_committed` 320–331; called by membership 641, profile 794, jurisdiction pointer 890, close 395, state change 718 | **Yes** | R3–R6, R8 pass. The pin reads `transaction_isolation`; under RR it cannot be set after the first statement, and setting it before one *is* READ COMMITTED, so there is no spoof. The shared side's read of the place (659, 810, 892) is a VOLATILE trigger's own command, so under RC it takes a fresh snapshot after the lock wait; R1/R2 prove it empirically. Both orders of the race hold: R1 (membership first) and the close-first order (the membership waits on the shared lock, reads the closed row, refuses by the range check 675). |
| B2 premise share-lock | `FOR SHARE` 650–652; `enforce_service_location_state_vs_places` 708–737 | **Yes** | R7 (membership first) passes. I ran the reverse order (`race_state_rev.sh`): the state change holds the row lock, the membership's `FOR SHARE` waits, and under RC re-reads the updated row — refused with "place … is in TX; the premise is in OK". The guard counts closed memberships too (line 721 has no `valid_to` filter), which is the right choice given the HINT "memberships are never rewritten" — but the battery does not pin it (T-gap 6). `tenant_id` of a premise cannot change under memberships: the composite FK is NO ACTION. `state` is NOT NULL, so the NULL leg cannot occur. |
| B3 time-zone refusal | `time_zone_uniform` fact 193–194; lookup 957–1000 reads both axes, refuses when only a non-uniform state answers | **Refusal holds; a new hole** | L3, L4, L5 pass; a Texas premise without a county is refused. But the both-axes read creates ties at one specificity (B1 below). |
| B4 RLS-narrowed close | `v_sees_all` 389–394 | **Yes** | C6 passes with a NOBYPASSRLS role under a T2 session. `rolbypassrls`, like `rolsuper`, is not inherited through membership, so `current_user` is the right thing to test. The check precedes the lock and the conflict query, so a narrowed role never reaches the count. |
| B5 P7 / P10 / A5 / A6 | `sales_tax_rate` fact 201–202; `relation` + `distance_miles` 575–576, 602–604; R11, R12 | **Held / stated** | M6 and L6 cover relation and distance. The rate has no range check (N2). |
| S1 outside relation | 602–604; exclusion ignores outside rows 617 | Yes | M6: within and outside one city at once refused by no-repeat; outside rows leave the group free. |
| S2 exclusivity groups | `place_kinds.exclusivity_group` 122, copied 662, exclusion 614–617 | Yes | M5a/M5b. Groups are copied from an immutable vocabulary, and the close-only UPDATE rule covers the copied columns. **Test gap:** the battery never records a limited-purpose-area or a second county (T-gap 1, 2). |
| S3 owner/place kinds, cross-state owner | 215, 221–222, 811–815; no state equality | Yes | P1, P2, P3. My regression mutation X17 (re-adding state equality) is caught at P3. |
| S4 keyed facts | 170, 480–485, exclusion on `coalesce(fact_key,'')` 454 | Yes | F6. Keys are not normalised: `'HB 1'` and `'HB 1 '` coexist (probe Q2; N3). |
| S5 lookups refuse bad arguments | 923–937, 1010–1022 | Yes | L1b, L7a–c, L8a. An invisible premise has no state and is refused by the state check (r2 note 928–929) — correct. |
| S6 jurisdiction pointer | 880–907; counted by the close 410–411 | **Yes** | J1, J2, R6. I raced a pointer in flight against a close (`race_jur.sh`): the close waits on the shared lock, then sees the pointer and refuses — so the lock at 891 works. **But nothing in the suite tests that lock**: removing line 891 is MISSED by every battery case and race leg (my X03). A pointer can be removed by `DELETE` as `tally_app` (jurisdictions has no `no_hard_delete`, DELETE is granted; probe Q6) — that only lifts the close block, which is the same as setting it NULL, so not a hole. |
| S7 created_by | 643–647, 796–800 | Yes | M1, M9, P3. Owner inserts without `app.user_id` carry NULL (probe Q3; r1 N1 stands). |
| S8 parent kinds | 123, 354–369 | Yes | A5a–d. |
| S9 evidence dates | 583, 755 | Yes | M7b. The profile's NOT NULL is untested (X04 MISSED). The date is not checked against `valid_from` (probe Q8: evidence dated 2099 for a 2020 membership; N4). |
| S10 TRUNCATE | 553–557 | Yes | A3c. Dropping `places` alone from the list is MISSED (X06), minor. |
| S14 zone names | 491–493 | Yes | F2b, F2c. |
| S11–S13 residuals | R13, R14, R15 | Stated | — |

No fix other than B3 introduced a hole I could find.

---

## 1. Does it hold the spec?

| Req | Held? | Where / gap |
|---|---|---|
| P1 state | held; R10 | state kind 149; premise column read `upper(btrim())` 650, 930; not validated on write (R10, stated) |
| P2 county | held | kind 151; `time_zone`, `weather_station`, `sales_tax_rate` facts |
| P3 city + facts | held; R4 | kind 153; `census_population`, `gas_rate_jurisdiction_retained`, `residential_gas_taxable`, `sales_tax_rate`; franchise fee stays text (R4) |
| P4 limited-purpose | held; R6 | kind 155, exclusive with city; rate treatment open (R6) |
| P5 ETJ | held | kind 157, exclusive with city |
| P6 rate areas | residual R3 | `jurisdictions.place_id` undated; "same state as the utility's premises" not checked (N6) |
| P7 tax jurisdictions with rate history | held | tax-axis kinds; `sales_tax_rate` dated per place (r1 B5); the combined rate is a sum the core takes over the tax-axis places plus the state — fine |
| P8 time zone | held, flawed | fact + lookup; **tie (B1)** |
| P9 weather | held | `weather_station`; WNA zone stays on `wna_zones` |
| P10 inside / outside N miles | held | `relation`, `distance_miles`; law predicate later (R15) |
| A1 owner type | held | 7 rows 230–241 with `owning_place_kinds` |
| A2 jurisdiction status | held | boolean, dated, separate; per governing state |
| A3 size | residual R7 | |
| A4 local opt-in | held | keyed `local_adoption` |
| A5 enforcing body | residual R11 | |
| A6 class / attributes | residual R12 | |
| A7 marketers | residual R8 | |
| D1 dates per axis | held | L6, M5 |
| D2 evidence | held | kind, reference, date on memberships; reference and date on profiles |
| D3 many-to-many, per-kind cardinality | held | exclusivity groups; districts stack |

**Modelling for what comes next.**
- *Law rows keyed on owner type and jurisdiction status:* `utility_service_profile_as_of(tenant, service, state, date)` gives exactly the (owner_type, commission_jurisdiction) pair a law row will key on, per governing state; Louisiana 45:850 (ownership after an opt-in) is answerable because the owner type survives the election. Sound.
- *Tax jurisdictions:* tax-axis memberships plus per-place `sales_tax_rate` facts is the Comptroller's shape (one rate per jurisdiction per quarter). Sound. A premise "within" a county on the tax axis but a different county on the regulatory axis is accepted — geography recorded twice, with no consistency rule — which is the root of B1 and the cost r1 noted (a county never changes by annexation). Not wrong, but worth a stated decision: either a county is axis-free, or the lookups treat a disagreement as a refusal.
- *Annexation:* two memberships, two dates; the exclusion forces the old city's membership to be closed before the new one is recorded on that axis. Right.
- *A utility in two states:* one profile per governing state, the owning place in any state (P3). Right.
- *A city system serving outside its limits:* `outside` rows with distance, the city's inside/outside rate areas as jurisdictions (R3). Right.
- *Districts under a parent:* `special_purpose_district` takes one parent of state / county / municipality (161). Districts cross city and county lines, so the parent is a fiction for many of them; and nothing ties a premise's memberships to the parent chain (probe Q4: within a district whose parent is City P, recorded outside City P — accepted). Fine for close ordering, but say that the parent of a district is for close ordering only, not geography (N5).

---

## 2. Integrity

### B1 (blocking). The time-zone lookup resolves a tie between two in-force places of equal specificity by picking one — a wrong answer where it should refuse
`premise_time_zone_as_of` (968–976) unions both axes, joins the `time_zone` facts, and takes `ORDER BY specificity DESC LIMIT 1`. Two places at the same specificity with different zones are a tie, and `LIMIT 1` without a further key returns whichever the planner yields. Two ways to get there, one of them legitimate data:

1. **The annexation window (D1, legitimate):** a premise within City A on the regulatory axis from the ordinance date and still within City B on the tax axis until the Comptroller's quarter — exactly the shape L6 tests. Both are municipalities (specificity 20). With A carrying `America/Chicago` and B `America/Denver` (probe `probes_tz.sql`, T2):
   ```
   rows at top specificity | CITYA | 20 | "America/Chicago"
   rows at top specificity | CITYB | 20 | "America/Denver"
   premise_time_zone_as_of(..., 2026-02-01) -> America/Chicago
   ```
2. **Two counties, two axes (operator error the schema allows):** El Paso County on the regulatory axis and Travis on the tax axis (T1) → `America/Denver`, no refusal.

In Texas the municipal case needs a zone boundary between two adjacent cities, which is rare today; the schema is general (ten states, three of which have intra-state zone lines), and the county case is a contradiction the database can see. Either way it is the one place in the patch where a visible contradiction is resolved by a guess, and it was introduced by the B3 fix (reading both axes). Fix, three lines: take the top specificity, select `DISTINCT` the zone values at it, refuse when there is more than one (`no_data_found`, "the premise's places disagree"). Add a case (two cities, two zones, in the annexation window) and a mutation that drops the distinct-count check.

### Nothing else broke. What I tried and could not break
- Both orders of the membership-vs-close and state-change-vs-membership races (section 0).
- A close under REPEATABLE READ or SERIALIZABLE; a membership, profile, pointer or state change under either: all refused by the pin.
- NULL legs: an unknown `kind_code` on a place, an unknown `place_id` on a membership, a NULL `fact_key`, a NULL `p_on`, a NULL axis, a NULL premise, a NULL `app.user_id` — each refuses (with a misleading message in two cases, N7) or falls to the FK.
- Tenant leakage: the lookups are invoker-rights and refuse an invisible premise via its state; profiles for another tenant are "not found"; the shared tables carry no tenant data; `jurisdictions.place_id` is a shared id. `places.closed_by` still exposes `session_user` (r1 N7, trivial).
- A premise with memberships cannot change tenant (composite FK NO ACTION) or state (B2); a respelling passes.
- The exclusion constraints serialise racing memberships at the index (PostgreSQL's guarantee).
- The close floor counts outside rows too, so a city with premises recorded outside it must have those rows closed first (probe Q5) — conservative, and right: an `outside` row is a dated fact about that place.
- A pre-closed place or fact (effective_to at insert) carries no close stamp (probe Q7; r1 N2 stands).
- `pg_timezone_names` is read by the owner only (facts are platform writes), so the view's cost is irrelevant to the application.

---

## 3. Tests

Every guard that the brief's round-1 list named now has a case, and the 79 mutations in `mutations-16.py` cover the trigger bodies well. Gaps I found with 18 extra mutations against the frozen files (`mut_extra.py`; 8 caught, 10 missed — of the missed, X07, X09, X11, X16 are untestable or redundant and are not gaps):

| T-gap | Mutation missed | Why | Cheap case |
|---|---|---|---|
| 1 | X02: `limited_purpose_area` moved out of `municipal_status` | no LPA membership anywhere in the battery; M5b only tests ETJ | a city and an LPA at once, refused by the exclusion |
| 2 | (X01 is caught, but only by M1's facet assertion `exclusivity_group = 'county'`) | no case records a second county on one axis | two counties at once, refused |
| 3 | X03: the jurisdiction pointer takes no place lock (891) | no race leg for the pointer; R6 only tests the RR pin; `mutations-16.py` M72–M74 cover the other three locks | race leg R10: a pointer in flight, then a close — waits and is refused (my `race_jur.sh` is the shape) |
| 4 | X08: the time zone ignores `relation = 'within'` (974) | L1 is outside Lonely, but Lonely has no `time_zone` fact | a premise outside a city whose zone differs from its county's reads the county's |
| 5 | X09: the state leg ignores the state's range (932) | TX is open; ZZ cannot close under zcity | a state `YY` closed 2000-01-01, a premise in YY, lookup 2026 → refused |
| 6 | X18: the state-change guard counts only in-force memberships (721) | S1 uses a premise with open memberships | a premise whose only membership is closed still cannot change state |
| 7 | X04: profile `evidence_date` nullable | only the membership NOT NULL is tested (M7b) | the profile twin |
| 8 | X14: a boolean accepted for a number fact | F2 tests text-for-number and text-for-boolean only | `census_population` = `true` |
| 9 | X06: `places` alone dropped from the TRUNCATE list; X05: vocabulary data (`political_subdivision` → municipality) | the vocabulary rows are data; the battery asserts the facets of two kinds only | one assertion over the seeded rows (axes, groups, parents, owning kinds) — a data-mutation case |

Also: `mutations-16.py` still hard-codes `DB = "m16"` (r1 S9 note), so two reviewers cannot run it concurrently; and the battery's `CREATE ROLE b16_closer` (662) is transactional but cluster-wide, so two batteries at once on different clones collide on the name.

---

## Should-fix

- **S1.** Decide the county-per-axis cost: a county membership must be recorded twice with two pieces of evidence, or once on an axis the zone happens to read. Either make `county` axis-free (geographic), or state in the table comment that both axes are expected and that the lookups refuse when they disagree (which B1's fix gives you for the zone). r1 raised it; it has no disposition in the findings file.
- **S2.** T-gaps 1–6 above; T-gap 3 is the only untested lock in the protocol.
- **S3.** `fact_key` is not normalised (probe Q2): `btrim` it in the exclusion, or require a form (`^[A-Za-z0-9][A-Za-z0-9 ./()-]*$`), so a padded citation code is not a second adopted law.
- **S4.** `sales_tax_rate` and `census_population` take any number (probe Q1: rate 5, population −3). A `value_range` on `place_fact_kinds` (or a per-kind check in the trigger: rate in [0,1], population ≥ 0) is cheap and matches "a value not of the declared type".
- **S5.** `evidence_date` is unconstrained against `valid_from` / `effective_from` (probe Q8: evidence dated 2099). An ordinance is dated before or on the day it takes effect; an address lookup after. If no rule is wanted, say so in the column comment.

## Notes

- **N1.** `enforce_jurisdiction_place` accepts a pointer at a place of a state the utility has no profile or premises in, and at any non-state kind (probe Q6: a special-purpose district). R3 says these rows become rate areas; a rate area is a city or a county. Worth a kind list when R3 is done.
- **N2.** The membership trigger's "service location not found" branch (653–655) is redundant: with it removed, the state check refuses with "the premise is in NULL" (X16). Same shape as the r2 note on the lookups; keep it for the message, or fold it.
- **N3.** `assert_same_tenant_user` lets a platform_admin user of another tenant record a membership for T1 (probe Q9) — by -05's design, noted for completeness.
- **N4.** Owner closes of memberships and profiles without `app.user_id` carry `closed_by = NULL` (r1 N1 stands).
- **N5.** A district's parent is a close-ordering link, not geography (probe Q4); say so in the `place_kinds` row or the table comment.
- **N6.** `jurisdictions` has no `no_hard_delete` and `tally_app` may DELETE (pre-existing; CI-014's set does not include it). The pointer's close block can therefore vanish by deletion as well as by NULLing — equivalent, not a hole.
- **N7.** Two refusals carry a misleading message: a membership in a non-existent place says "a <NULL> takes …" (665), a pointer at a non-existent place says "is a state, or not in force today" (896). Both refuse; the FK would also.
- **N8.** `premise_time_zone_as_of` evaluates `premise_places_as_of` three times (two axes, then the uniform check). Fine at this scale; a CTE would read once.
- **N9.** The B1 fix's shared-side reads rely on VOLATILE trigger functions taking fresh snapshots per command under READ COMMITTED. True, documented, and proven by R1/R2 — but it is the load-bearing assumption of the whole protocol, and the comment at 305–309 says "each reads, after the wait, what the other committed" without naming why. One sentence ("a VOLATILE function's commands take fresh snapshots under READ COMMITTED") would save the next reader the derivation.

Clone `fable16r2` dropped after this review.
