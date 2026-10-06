# Review v5.4.2-16 round 1 — places and applicability (Fable)

**Artefacts verified.** patch md5 `a87f2e9fa2c716073d6b462bd7638f91`, battery md5 `3c1d2f05fe64b25dc4122a03fbc27f3f` — both match the brief; the unfrozen copies (`sql/v5.4.2-16-places-and-applicability.sql`, `tests/v5.4.2-16/battery-16.sql`) are byte-identical to the frozen ones.
**Environment.** clone `fable16` (TEMPLATE tally, TEMP revoked), patch strict-applied clean (search_path '', check_function_bodies on). Battery: 38 PASS, 0 FAIL. Race script R1–R3: PASS. Probe scripts: `scratchpad/review16/{fixtures,probes1,probes2}.sql`, `race_rr.sh`. Line numbers below are the frozen patch unless marked.

## Verdict: **not yet**

Two blocking items, both on the close floor — the patch's central integrity claim (header lines 60–62: a close is refused while a membership or profile runs past it; line 71: a membership is refused when the place is not in force over it).

---

## Blocking

### B1. A membership or profile inserted under REPEATABLE READ outlives its place's close; the lookup then returns the closed place as in force
The lock handshake is one-sided. The close checks `transaction_isolation` (patch 330–334) because its check after the wait must see committed rows. The shared side has no such check: `enforce_premise_place_membership` takes the shared lock (557) and then reads the place (558) — under REPEATABLE READ that read comes from the transaction's snapshot, which can predate a close that already committed. Same shape at 669–670 for profiles.

Reproduction (`race_rr.sh`): session A `BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT count(*) FROM places;` (snapshot), sleeps; session B (owner) closes FROUNDROCK `effective_to = 2025-01-01` — nothing cites it, close accepted and committed; A then inserts a membership `valid_from 2020-01-01, valid_to NULL` in FROUNDROCK. The shared lock is free (B committed), the range check at 574 sees the pre-close row, the insert commits. Result in the database:
```
place FROUNDROCK effective_to=2025-01-01
membership in it: valid_from=2020-01-01 valid_to=NULL
premise_places_as_of(L, 2026-06-01, 'regulatory') -> municipality:FROUNDROCK, state:TX
```
The lookup (740–759) does not re-check the place's range against `p_on` for the membership leg, so a place closed eighteen months earlier is reported as the premise's city — a wrong answer, not a refusal. The header's refusal is therefore conditional on an isolation level the application side is never told about.

Fix: the INSERT paths of memberships and profiles refuse under anything but READ COMMITTED (the same guard the close has, 330–334), or — if the application wants RR — the lookup's membership leg also requires `daterange(p.effective_from, p.effective_to) @> p_on` so a stale row at least cannot answer. Add race R4 (a REPEATABLE READ membership insert after a close is refused) and a mutation for it. Note the -15 accrual side (2663) has the same one-sided shape; worth a parity look there too.

### B2. The close floor is blind to a role that row-level security narrows — the -13 `v_sees_all` guard was dropped
`enforce_place` reads `premise_place_memberships` and `utility_service_profiles` (336–348), both FORCE RLS with the tenant policy. -13's close floor refuses a closer that is not superuser/BYPASSRLS for exactly this reason (`sql/v5.4.2-13-backbilling-caps.sql` 872–880). -16 omits it. In this build `tally` is superuser+bypassrls, so the battery's C1–C4 cannot see the hole.

Reproduction (`probes2.sql` P-B): T1 commits an open membership in FCLOSEME; a role `fable_mig` (NOSUPERUSER NOBYPASSRLS, UPDATE on places) with no `app.user_id` set closes the place:
```
fable_mig sees 0 memberships citing the place
place closed: effective_to=2025-01-01 closed_by=tally   (session_user)
owner sees membership still open past the close: valid_to=NULL
T1 lookup 2026-06-01 regulatory -> municipality:FCLOSEME, state:TX
```
A side effect seen in `probes1.sql`: if `app.user_id` was ever set in the session and then RESET, the floor's SELECT errors with `invalid input syntax for type uuid: ""` from `get_user_tenant_id()` — a refusal, but an accidental one. Port the -13 guard verbatim (six lines, `insufficient_privilege`), and add a battery case that runs the close as a non-bypass role and expects the refusal.

---

## Should-fix

### S1. `service_locations.state` is editable after memberships exist; the lookups then mix two states
No trigger on `service_locations` but `set_updated_at`/`no_hard_delete`; `state` is not validated on write (R10). P-C: a premise with an El Paso County membership has its state set to `NM`:
```
premise_places_as_of -> TX:county:48141, NM:state:NM
premise_time_zone_as_of -> America/Denver   (from the TX county)
```
The header's "a place of another state than the premise's" (73) holds only at insert. Either a BEFORE UPDATE guard on `service_locations` refusing a change of `upper(btrim(state))` while a membership is in force, or state it as a residual next to R10.

### S2. Municipality, limited-purpose area and ETJ are not mutually exclusive — a premise can be inside a city, in its ETJ and in a limited-purpose area at once
`single_per_premise` is per kind (523–526), so three kinds that are by definition disjoint on the ground stack. P-F accepted all three on the regulatory axis for one premise, same dates. Later law rows keyed on "inside the municipality" will pick one silently. Replace the boolean with an exclusivity group on `place_kinds` (e.g. `exclusive_group = 'municipal_boundary'` for the three; `'county'`, `'transit'`, NULL for districts) and key the exclusion on the group. The spec's D3 says "≤1 city"; this is the same requirement stated for what a city boundary means.

### S3. A municipal system serving a second state cannot record its profile for that state
`enforce_utility_service_profile` requires the owning place to be of the profile's `state_code` (671). The owner of a city system is one city whatever state the premises are in. P-G: a Texas-city-owned profile for `NM` is refused (`not a place below the state in NM`). The brief asks about "a utility in two states"; this is the case where the model refuses the truth rather than a bad row. Drop the state equality for the owning place (keep "not a state" and "in force over the range"); the profile's own `state_code` is the served state.

### S4. `local_adoption` is one-per-place-at-a-time, so a city that adopts two opt-in laws is refused
`place_facts_no_overlap` keys on (place, fact_code, range) (387–388). A4's fact is multi-valued by nature. P-E: a second `local_adoption` on FAUSTIN with a different value → `exclusion_violation`. Either a `multi_valued` flag on `place_fact_kinds` that the exclusion honours (key on the value too), or one fact code per adopted law.

### S5. Time zone is read on the regulatory axis only; a county recorded on the tax axis yields the state's zone (wrong, not refused)
`premise_time_zone_as_of` (771) passes `'regulatory'`. P-D: El Paso premise, county membership on `tax` only → `America/Chicago`. A county is geographic; its membership on either axis is equally evidence. Read both axes (UNION, DISTINCT on place), or document that the regulatory county membership is mandatory for the zone. Related design note: a county never changes by annexation, so requiring two county memberships with two evidences per premise is pure cost; a `geographic` axis for county, or treating the county as axis-free, would fit D1 better.

### S6. `jurisdictions.place_id` is unguarded, and the close floor does not count it
P-I, as `tally_app`: a jurisdiction may point at the state place, at another state's city, and may be repointed at will; a place then closes under a jurisdiction pointing at it (floor at 336–348 lists memberships, profiles, facts, children only). The header lists exactly those four, so this is not a contradiction, but R3 says these rows become the dated rate areas — so the pointer will carry law weight. Add a trigger (kind not `state`; place in force; same state as the utility's profile where one exists) and either count jurisdictions in the floor or say in R3 that they are not counted.

### S7. The lookups accept inputs that make them answer wrongly
- `premise_places_as_of(L, d, 'bogus')` returns the state row only (P-H) — the axis is a free text parameter; a typo reads as "no memberships". Validate against the CHECK list and raise.
- `p_on NULL` returns no rows; `premise_time_zone_as_of(L, NULL)` then raises "no time zone is recorded for premise … on " — a refusal with the wrong diagnosis. tu.sql 19181 (-07) refuses a NULL date explicitly; do the same.
- A premise that does not exist or is not visible returns an empty set, not an error; for a tenant-2 session on a tenant-1 premise the time-zone lookup refuses (good, P-M) but `premise_places_as_of` silently returns nothing. Consider raising when the premise itself is not visible (the membership trigger already does, 552–554).

### S8. Spec items held neither in the patch nor in the residuals
- **P7 "rate history at quarter-start dates"** — the tax place kinds exist; no tax-rate rows, no residual. Add an R-row.
- **P10 "outside within N miles"** — the profile comment (648) says inside/outside is a membership question; the distance leg (KS 3 mi, NM 5 mi) is neither modelled nor listed. Add an R-row.
- **D2 "ordinance number and date"** — one free-text `evidence_reference`; the date of the evidence is not a column. Minor; state it.
- **Parent kind hierarchy** — a county under a city and a city under a transit authority are accepted (P-L). The floor uses the parent link for closes, so a wrong parent blocks a legitimate close later. A per-kind `allowed_parent_kinds` on `place_kinds` is cheap.

### S9. Tests: guards without a case only they can refuse, and cases that would miss a mutation
- **Profile close stamp is never asserted.** P5 (battery 373–383) closes a profile and reads only `commission_jurisdiction`; a mutation dropping `closed_at/closed_by` at 689–694 (the profile twin of M25/M42) is not in `mutations-16.py` and would be MISSED.
- **No REPEATABLE READ case on the shared side** (B1): no guard exists, so no test; add R4 with the guard.
- **No non-bypass closer case** (B2): add one that creates a NOBYPASSRLS role inside the rolled-back transaction.
- **Close floor across tenants.** Every C case cites T1 rows only. Add: T2's membership alone blocks a close run by the owner — this is the case B2 is about and a policy-narrowed read would fail it.
- **Precedence city > county** is not exercised (L2 covers county > state; M34's `ASC` is caught by that). Fine as is, but a municipality `time_zone` fact over a county fact is the only case that checks the `specificity` numbers rather than the sort direction.
- **Tenant spoof.** G3 has T2 record a membership *as T2* for T1's premise; the other spoof — T2 session, `tenant_id = T1` on T1's premise — is refused (P-J, "not found (or not visible)") but untested; it is the write-side inverse of G2 and worth one line.
- **M7b / P4b / G3** accept `restrict_violation OR insufficient_privilege` / `foreign_key_violation OR insufficient_privilege`. Each passes on whichever guard fires first; a mutation removing one of the two is still caught by the other, which is acceptable here, but say so in the case text.
- **`mutations-16.py` hard-codes `DB = "m16"`** — three reviewers running it concurrently would clobber each other's clone; take the name from argv like the race script does.

---

## Notes

- **N1.** Memberships/profiles closed by the owner with no `app.user_id` carry `closed_by = NULL` (P-W); places and facts stamp `session_user` text. The owner leaves no actor on a tenant row. If owner closes of tenant rows are expected, consider a text `closed_by_role` twin; if not, say owner closes are not a path.
- **N2.** A place or fact inserted already closed (`effective_to` set at insert) carries no `closed_at/closed_by` (P-X); the "stamped, once" claim holds for closes, not for pre-closed rows. Fine; worth a sentence in the comment.
- **N3.** A profile for a state with no state place (`QQ`) is accepted (P-V). The lookups refuse for premises in such a state, so nothing is answered wrongly; but a profile is the only row that names a state the platform does not know.
- **N4.** A membership on a demolished premise is accepted (P-AB). Not a law question; noting the status is not read.
- **N5.** `premise_places_as_of` membership leg does not filter by the place's own range (relies on the floor). Cheap belt-and-braces: add the range predicate; it also makes B1's stale row unable to answer.
- **N6.** Advisory-lock key space is shared with -15's `deposit_rate_lock_key`; both use `hashtextextended` with distinct prefixes — collision only serialises, never corrupts.
- **N7.** `places.closed_by` (session_user text) is readable by `tally_app`, exposing the migration role's name. Trivial.
- **N8.** `txid_current()` is the deprecated spelling of `pg_current_xact_id()`; tu.sql uses it elsewhere, so parity wins.
- **N9.** The single-per-premise exclusion and the no-repeat exclusion are GiST EXCLUDE constraints; two memberships racing them are serialised by the index (one waits on the in-progress tuple, then conflicts) — PostgreSQL's own guarantee, not re-tested here.
- **N10.** Two parallel battery runs on one clone are safe (one transaction, rolled back, fixed ids); the race script commits and is not re-runnable on the same clone (fixed tenant/place ids).

## Spec coverage (P1–P10, A1–A7, D1–D3)

| Req | Held? | Where / gap |
|---|---|---|
| P1 state | held | place kind + premise column read normalised (485–486, 753–758) |
| P2 county | held | kind; `time_zone`, `weather_station` facts |
| P3 city + facts | held | kind; `census_population`, `gas_rate_jurisdiction_retained`, `residential_gas_taxable`; franchise fee → R4 |
| P4 limited-purpose | held + R6 | kind; see S2 (not exclusive with city) |
| P5 ETJ | held | kind; see S2 |
| P6 rate areas | residual R3 | jurisdictions undated; `place_id` unguarded (S6) |
| P7 tax jurisdictions | partly | kinds + `residential_gas_taxable`; **rate history not held, not a residual** (S8) |
| P8 time zone | held | fact + lookup; axis issue S5 |
| P9 weather | held | `weather_station` fact; WNA zone stays |
| P10 inside/outside | partly | inside = membership; **distance leg not held, not a residual** (S8) |
| A1 owner type | held | 7 rows, `requires_owning_place` |
| A2 jurisdiction status | held | boolean, dated, separate from owner; S3 for two states |
| A3 size | residual R7 | |
| A4 local opt-in | held, flawed | `local_adoption` one-at-a-time (S4) |
| A5 regulator per rule set | not here | belongs to law rows (R1 implicitly); say so |
| A6 class/attributes | not here | existing rows; out of this patch |
| A7 marketers | residual R8 | |
| D1 dates per axis | held | axes; battery L4 |
| D2 evidence | held | kind + reference; date not a column |
| D3 many-to-many, per-kind cardinality | held | S2 for the boundary kinds |

Modelling direction otherwise sound for what follows: law rows keyed on (state, owner_type, commission_jurisdiction) read from the profile in force; tax axis separate per R-26; annexation as new memberships with the city row unchanged; a city system serving outside its limits as a profile with an owning place plus premises without a municipality membership.

Clone `fable16` dropped after this review.
