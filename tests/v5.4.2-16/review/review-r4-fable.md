# Review v5.4.2-16 round 4 — places and applicability (Fable)

**Artefacts verified.** patch md5 `a0b43c01bda36c127707100c9726643f`, battery md5 `15eea127cf8d34da55d917325d947659` — both match the brief; the working copies `sql/v5.4.2-16-places-and-applicability.sql` and `tests/v5.4.2-16/battery-16.sql` are byte-identical to the frozen files, so `mutations-16.py` exercises the frozen revision.
**Environment.** Clone `fable16r4` (TEMPLATE tally, TEMP revoked; strict apply with `search_path=''`, `check_function_bodies=on`: clean, AC-32 tail passed). Battery **80/80 PASS**. Races `place-close-16.sh` on a second clone `fable16r4r`: **R1–R18 all PASS**, exit 0, each two-session leg with the second session seen waiting. My own work (scratchpad `review16/`): `fable-r4-probes.sql` (Q1–Q7, 90 probes as `tally_app` or owner, one transaction, rolled back) and `fable-r4-mut.py` (17 extra mutations against the frozen files on clone `fable16m4`). Line numbers below are the frozen r4 patch. No repo file touched; all three clones dropped.

## Verdict: **ready**

Every round-3 fix holds under attack, no fix opened a new hole, and I could not put the records in a refused state or make a lookup answer wrongly. What remains is three cheap test gaps (cases only, no patch change) and notes.

---

## 0. Did round 3's fixes hold?

| Item | Fix (r4 lines) | Holds? | How I tried to break it |
|---|---|---|---|
| **B** NaN distance | `premise_place_memberships_relation_check` 667–671: `> 0 AND <> 'NaN'` | **Yes** | Q1a `'NaN'` → 23514. `'Infinity'`/`'-Infinity'` → 22003 overflow of `numeric(8,3)` (Q1b/c); `'-NaN'` is not even numeric syntax (22P02, Q1d); `-1` and `0` → 23514 (Q1e, T1b); `0.0004` rounds to `0.000` **before** the check and is refused (Q1g — the right order); `1e6` overflows; `99999.999` stored and returned (Q1i). No non-finite or non-positive value reaches storage. |
| **S-d′** state close floor + profile's state lock | close floor 452–454; profile insert locks every state row 920–924, then re-reads 925–931 | **Yes** | Q2: state WW as two rows (A 1900–2010 closed, B 2010–open). A profile spanning A and B is refused (Q2a, R19 as stated); one inside B accepted (Q2b); one inside the closed row A, 1990–2000, accepted (Q2c — right: the law was in force then). Close B at 2020 under the gas profile → 23001 "governed by it" (Q2f). Boundary: a profile ending exactly on the close day does not hold the state (Q2e+Q2k, T2b). Voided: T2c. Succession path works end to end: app closes the profile at 2030 → owner closes B at 2030 → owner adds C from 2030 → profile inside C accepted, one across B\|C refused (Q2j–Q2n). Both lock orders: R13 and R14. The over-refusal I feared (a later-inserted *earlier* state row blocked by a profile outside its range) cannot arise: an earlier row must be born closed (it would otherwise overlap), and a born-closed row cannot be closed again (Q2g, 23001). |
| **S-tz** answering level | `premise_time_zone_as_of` 1107–1154 | **Yes** | Q3a outside Harris (no zone) + within El Paso → Denver (outside rows are not candidates, 1114). Q3b outside El Paso (Denver) + within Harris (none) → refuses (state only, Texas non-uniform). Q3c city Denver within Travis Chicago → Denver (the stated design; now pinned by L5a — my mutation XA flipping precedence is caught there). Q3d the same county on both axes → one answer. Q3e Travis + Dallas, both Chicago → Chicago (agreeing duplicates). Q3f a county whose zone fact ended → "carries none" refusal at level 10 even though Travis answers (a partial load refuses). Q3g a voided city with a zone falls through to the county. Q3h no zone below the state → refuses. Q3i El Paso (reg) + a zoneless city (tax) + Harris (tax): level 20 has no zone so falls through; level 10 has one zoned and one unzoned → refuses, correctly. Q3j a uniform state with an unzoned county answers by the state. Q3n the state's own zone fact closed: a county still answers; a premise with nothing below the state refuses. Q3m two zone facts in force on one place is impossible (`place_facts_no_overlap`). |
| **S-key** citation form | `place_facts_key_check` 505–506 | **Yes** | Q4, 38 keys. Pass: `16 TAC §7.45`, `305 ILCS 20/13(k)`, `Tex. Util. Code §101.003(7)(A)`, `R.S. 45:850`, `N.Y. Pub. Serv. Law § 32`, `Ord. No. 2020-14`, `Art. IX, §2`, `§§ 7.45-7.46`, `HB 1/2`. Refused: trailing/leading space, tab, newline, no-break space, thin space (U+2009), zero-width space (U+200B), doubled space, `(k)` (leading bracket), `-` alone. **Real forms it refuses:** `Ord. #2020-1` (#), `Res. 20-1 & 20-2` (&), `Title 16 [TAC]`, `§§7.45–7.46` (en dash, as copied from most statute sites), `Pub. L. 95–617`, quotes, `%`, `+`, `=`, `@`. Acceptable for a key that is a *code* — but the loader must normalise en dashes to hyphens. What still passes that could alias: NFC `é` passes while NFD `e`+U+0301 is refused (no silent duplicates, good); Arabic-Indic digits pass; case is significant (`hb 1` ≠ `HB 1`). Note N3. |
| **S-err** 25000 | `assert_place_read_committed` 365–378 | **Yes** | R3–R6, R8 each require `ERROR:  25000`; tu.sql's four guards (19966, 19993, 20459, 22113) use the same code. Not in any driver's transient list. |
| **S-uninc** one per state | `places_one_unincorporated` 339–341 | **Yes** | Q5a a second Texas area → 23P01; another state's → accepted (Q5b); the seeded area closes (nothing cites it) and a successor from the close date is accepted (Q5c/d) — succession is not blocked. |
| **T** | battery T1–T12, races R13–R18, M112–M133 | **Yes** | 80/80, 18/18 on my clones. My 17 extra mutations: 13 caught, 4 missed (section 3); none of the misses is a hole. |

**Did a fix introduce a new hole?** The reach of round 3's changes is the close floor's state leg (owner-only path), the profile's lock loop (shared locks; cannot deadlock against other shared takers; closes are migration-serial per R9), the lookup's candidate set (reads only), the key regex (narrower than before) and the exclusion (narrower). I found nothing new. The lookup's candidate filter `pl.kind_code = ANY (time_zone place_kinds)` (1115) is near-inert because `limited_purpose_area` is the only non-zone kind sharing a specificity with a zone kind, and it is exclusive with the city — correct either way.

Rounds 1–2 fixes touched by round 3 (B1 pins, B2 share-lock, B3 both-axes read, S-b void, S-a pointer) re-checked through R1–R12 and the N group: hold.

---

## 1. Does it hold the spec?

Unchanged from my round-3 table; every requirement is held or a stated residual:

| Req | Held? | Where |
|---|---|---|
| P1 state | held; R10 | kind 177; `upper(btrim(state))` 762, 1059 |
| P2 county | held | kind 179; `time_zone`, `weather_station`, `sales_tax_rate` |
| P3 city + unit facts | held; R4 | kind 181; `census_population`, `gas_rate_jurisdiction_retained`, `residential_gas_taxable`, `sales_tax_rate`, `local_adoption` |
| P4 limited-purpose area | held; R6 | kind 183, regulatory only |
| P5 ETJ | held | kind 185 |
| unincorporated (r2 S-c) | held, one per state | kind 187, 339–341 |
| P6 rate areas | residual R3 | `jurisdictions.place_id`, undated |
| P7 tax jurisdictions, rate history | held | tax-axis kinds; dated `sales_tax_rate`; `residential_gas_taxable` on districts |
| P8 time zone | held | fact + lookup that refuses (section 0) |
| P9 weather | held | `weather_station`; WNA zone stays on `jurisdictions` |
| P10 inside / outside N miles | held | `relation`, finite positive `distance_miles` |
| A1 owner type | held | 273–279 with `owning_place_kinds` |
| A2 jurisdiction status | held | `commission_jurisdiction`, dated, per governing state |
| A3 size | residual R7 | |
| A4 local opt-in | held | keyed `local_adoption` |
| A5 enforcing body | residual R11 | |
| A6 class / attributes | residual R12 | |
| A7 marketers | residual R8 | |
| D1 dates per axis | held | L6 |
| D2 evidence | held | kind, reference, date ≤ today (T11) |
| D3 cardinality | held | exclusivity groups; districts stack |

**Modelling for what comes next.** Law rows key on `utility_service_profile_as_of(tenant, service, state, date)` → (`owner_type`, `commission_jurisdiction`); where a law reaches "any political subdivision" (KS 12-808c) the predicate is over `owner_type IN (…)`, no schema change. Tax jurisdictions: tax-axis memberships plus per-place facts, the core joins them. Annexation: close the ETJ membership at the ordinance date, add the city from it (regulatory), add the tax membership from the Comptroller's quarter; the exclusion forces that order (M5). A utility in two states: one profile per governing state, the owning place in either (Q6l: a Texas city governing a UU service accepted). A city system serving outside its limits: `outside` rows with distance, rate areas via `jurisdictions` (R3). Nothing here forces a meaning-changing migration later.

---

## 2. Integrity — what I tried and could not break

- **NULL legs / bad arguments:** NULL date (Q3l, 22023), NULL state under memberships refused (Q6f, 23001), NULL state without memberships refused by NOT NULL (Q6g), a membership of a nonexistent place refused before the FK (Q6b; the message reads "a  takes ;" — cosmetic, note N5), a state as owning place (Q6n), a city as a district's owner (Q6m), a membership in a state (Q6o), before its place begins (Q6p).
- **Edits:** a no-op update of a membership is refused (Q6h); close then widen is refused (Q6i); a close before the start is refused by the range check (Q6j); a place born with `closed_at` set is stamped clean (Q7a, A7).
- **Tenancy:** T2 sees none of T1's rows (Q6q), cannot read T1's premise through either lookup (Q6r/Q6s refuse), voids 0 rows (Q6t), cannot record a membership naming T1's tenant (Q6u, refused by `created_by`; RLS would refuse it next). A platform admin can record for a tenant (Q6v) — -05's convention. Changing a premise's `tenant_id` under memberships is refused by RLS for the app and by the composite FK for the owner (Q6e).
- **Close floor:** an `outside` membership holds its place open (Q6w); a membership on the close day does not (C5, XU caught); the owner is superuser on this build (`rolsuper = t`) so the BYPASSRLS gate passes; the app cannot close (Q6y, 42501).
- **Advisory protocol:** the app can still take the exclusive key (Q6z) — residual R13, unchanged. 64-bit keys do not collide with tu.sql's `(int, int)` advisory space.
- **Isolation:** every citing write and the close pin READ COMMITTED (R3–R6, R8, 25000).
- **Exclusions under race:** R16, R17 (second session waits on the index entry, then `exclusion_violation`). A void in flight against an insert into the same group: the insert waits on the old tuple version, then succeeds once the void commits — PostgreSQL's partial-index semantics, correct.
- **Facts:** a numeric given as a JSON string is refused (Q7b); `UTC` accepted, `GMT` refused (Q7d/e); a fact on a kind not listed (Q7f/g).

---

## 3. Tests

17 extra mutations against the frozen files (`fable-r4-mut.py`): **13 caught** (precedence of city over county at L5a; owning-place `@>`; profile lookup's state and service predicates; the places lookup's axis and voided filters; born-with-stamps; fact `@>`; profile `no_overlap`'s void filter; the void-is-final rule; exclusion's axis; both close-day legs). **4 missed:**

| Gap | Mutation | Why missed | Cheap case |
|---|---|---|---|
| T1 | XO: `no_repeat` gains `relation` (within **and** outside the same place at once pass) | M6b *looks* like this case but is masked: L1 is already within El Paso city, so "within Lonely" trips the **group** exclusion, not `no_repeat` — the case passes with the guard it names removed | within then `outside` one place with no competing group member (a county for a premise with none, or a district), same axis and days → 23P01 `premise_place_memberships_no_repeat` |
| T2 | XY: a no-op `UPDATE` of an **open** place passes and stamps `closed_at` with `effective_to` NULL | A2 tests edits and a second close, not a no-op on an open row | `UPDATE places SET name = name WHERE id = austin` → 23001 |
| T3 | XS: the profile's state-lock loop locks only the first row of the state (`EXIT` after one) | R13/R14 use states with one row (`RQ`, `RS`); the loop over "every place of that state" (970) is untested | a race leg with two rows of one state, the open row sorting second by id; the close of the open row must wait on the profile |
| — | XW: the uniform fact read from any place | inert: `time_zone_uniform` is declared for states only (233) | none needed |

None is a hole in the patch; T3 is the one worth doing, since the loop is the round-3 fix's load-bearing half.

---

## Should-fix

- **S1.** The three cases above (T1, T2, T3), T3 as a race leg (R19 in the harness's numbering) with two rows of one state.

## Notes

- **N1.** Within a county on the tax axis and `outside` it (3 miles) on the regulatory axis, the same days, is accepted (Q6a). A consequence of D1 (axes dated separately) and right for the annexation window (the Comptroller's quarter lags the ordinance), but worth one sentence in the memberships comment (696), which reads as if the relation were a property of the place.
- **N2.** Memberships are not checked against each other's parents: within a district whose parent is City N while within City D is accepted (Q6d). By design (evidence, not geometry — R8); say so in the same comment.
- **N3.** The key form refuses `#`, `&`, `[ ]` and the en dash; the loader must normalise citations copied from statute sites (`§§7.45–7.46`). Keys are case-sensitive and NFC-only; fine for codes.
- **N4.** `political_subdivision` takes only a `county` as owner (274); a township or parish system needs a vocabulary row later (from r3, stands).
- **N5.** The refusal for a nonexistent place reads "a  takes ; not the tax axis" (Q6b): `v_kind` is NULL. Cosmetic; a `coalesce` in the message.
- **N6.** A city's zone outranks its county's (Q3c) — Texas's zones are county facts (49 CFR 71.7(e)); the loader should not write city time zones in Texas. Stated in the lookup's comment; one line in R2 would reach the loader.

Clones `fable16r4`, `fable16r4r`, `fable16m4` dropped.
