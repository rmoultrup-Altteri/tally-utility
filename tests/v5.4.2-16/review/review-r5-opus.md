# v5.4.2-16 review round 5 — Opus

**Verdict: ready.** No blocking item. Round 4's six items hold under live attack. Three should-fix items: one modelling choice to settle now because changing it later costs more, two tests the mutations show are missing, and one wording/residual pair.

## Frozen artefacts

| file | md5 (brief) | md5 (measured) |
|---|---|---|
| `patch-16-frozen-r5.sql` | `24757cfc95fb3be08e416f8504c0dbc1` | same |
| `battery-16-frozen-r5.sql` | `3add58b717852d9d5d4804cc934c3150` | same |
| `sql/v5.4.2-16-places-and-applicability.sql`, `tests/v5.4.2-16/battery-16.sql` | — | identical to the frozen pair |

## What I ran

- Clone `opus16r5` (TEMP revoked; strict apply with `search_path=''` and `check_function_bodies=on`): applied cleanly, AC-32 tail passes.
- Battery: **90/90 PASS**, no FAIL or ERROR.
- Races on a second clone `opus16r5r`: **R1–R20 all PASS**. R15 runs inside the other legs.
- Mutation harness: a copy of `mutations-16.py` pointed at the frozen pair and its own database (`opus16r5h`). Result: __HARNESS__.
- 10 extra mutations of my own (X1–X10), each on a fresh clone with the full battery. X9 was also run against the race script.
- Probe scripts, run as `tally_app` with `SET LOCAL app.user_id` wherever the guard concerns the application. They are in `scratchpad/review16/p5/`.
- All of my databases were dropped at the end.

---

## 0. Did round 4's fixes hold?

### B1: the profile's state handshake. **Holds.**

The code is at patch:971-994. The profile selects the one state row that covers its range, share-locks that row's key, and then re-reads that same row with `PERFORM ... @>` in a new statement. Under READ COMMITTED (asserted at :964) that re-read takes a fresh snapshot. Two state rows can never cover the same range: `places_no_overlap` (:381) together with "a state's place_code is its state_code" (:442). So `SELECT INTO` cannot pick between two rows. On the close side (:490-501), the exclusive lock is taken on `OLD.id`, and governed profiles are counted by `state_code` across every tenant, under the role that sees all (:483-488).

Cases I attacked:

| case | result |
|---|---|
| A state of two rows, QQ [1900,2025) closed and [2025,∞). Profile [2020,∞) spans both | refused (R19 as designed): "QQ is no state with a place in force over 2020-01-01..open" |
| Profile [2026,∞) inside the successor row | accepted. The owner's later close of that row at 2027 is refused: "a utility profile governed by it … is in force after 2027-01-01" |
| Profile [2020,2024-06) inside the closed old row | accepted (correct: the close at 2025 does not cut it) |
| A gap, with no row covering | refused, by the same message |
| Successor committed while the profile waited (R19); the covering row is not first by id (R20); both orders (R13/R14) | PASS on my clone |
| **X9**: take the lock *after* the re-read instead of before | **caught** by R14, R19 and R20 ("the profile said: …"), so the race legs depend on the order of lock and re-read |
| Reopened range | not reachable: `effective_to` is set once (:475-480), and places are never deleted (:470) |

The fix adds no hole I could find. The lock order is still state, then owning place (:975, :1014). A reviewed migration that closes an owning place and then its state, in one transaction, can deadlock against a profile insert. PostgreSQL aborts one of the two, so this is benign; R18 already states the general case.

### S-own: owner type vs system kind. **Holds**, with one new modelling consequence (should-fix SF1)

- Vocabulary: the table and its rows are at :301-328. It is immutable, cannot be truncated, and the application cannot write it. I probed all three live: UPDATE refused by the vocabulary trigger, TRUNCATE refused by `no_truncate`, and an INSERT as `tally_app` refused with "permission denied". **None of these is tested** (SF2: mutations X2–X4).
- Service check (:995-1000): a water master-meter system is refused (U6a). A water piped-propane system is not tested (X7 MISSED, see SF2).
- Owner and system are separate facts: a city-owned piped-propane profile reads back as municipal / piped_propane_distribution (U6c). Editing `system_kind` on a stored profile is refused by the whole-row close/void rule (:782). Probe: `UPDATE … SET system_kind='master_meter'` → "never edited".
- **Do five owner types and three system kinds hold the sources?** For the categories the sources name, yes:
  - TX river authority → special_district.
  - NM class A/B/H county → political_subdivision.
  - NM municipally owned corporation → municipal.
  - LA gas utility district (33:4306) → special_district.
  - OK and NM cooperatives → cooperative.
  - OH 4905.90(K) and TX 121.211(d) → master_meter.
  - NM 62-3-3(G)(2) and OH 5117.01(D) → piped_propane_distribution.

  Two shapes do not fit cleanly. Both are in SF3:
  - *Owners that are not territorial places.* The special_district description (:287) names "gas association, public trust", but such an owner must name a `special_purpose_district` place. An Oklahoma 60 O.S. §176 public trust (utility-type-10-states.md:63, 121) and a New Mexico 3-28 gas association (:263, 273) have no territory. Recording one as a district place creates a place that premises can join on both axes, which means nothing. Texas §101.003(8) (texas.md:21) also counts "a nonprofit corporation the directors of which are appointed by one or more municipalities" as municipally owned.
  - *Joint municipal ownership.* `owning_place_id` is a single id (:913). The same §101.003(8) wording, "one or more municipalities", cannot be recorded when there are two cities.

### S-tax: ETJ and limited-purpose areas on the tax axis. **Holds.**

- The kinds now take both axes and stay in the `municipal_status` group (:195-198). Probes:
  - A limited-purpose area within on tax: accepted.
  - An ETJ on tax plus Unincorporated Texas on tax for the same premise: refused by `premise_place_memberships_exclusive`, so "in no city" keeps one meaning.
  - City plus ETJ on tax: refused (U7).
- Annexation gap (D1), modelled end to end. A premise is in the ETJ (regulatory to 2024-02-15, tax to 2024-04-01), then in Town A (regulatory from the ordinance date, tax from the quarter). `premise_places_as_of(…, 2024-03-01, 'regulatory')` returns municipality TOWNA, the county and TX. The same call with 'tax' returns the extraterritorial_area and TX. That is correct, and it could not be recorded before round 4.
- Time zone: ETJ, limited-purpose and unincorporated areas are not `time_zone` kinds (:243), so the candidate filter (:1185) never sees them. A tax-only ETJ cannot change the answer. Probe: county with no zone + ETJ + city with no zone, in Texas (not uniform) → refused "no time zone can be read", as it should be.
- State guard (:880-889): it counts tax-axis memberships too, because it joins on place state whatever the axis.
- **Test gap:** a limited-purpose area on the tax axis is never exercised. U7 uses the limited-purpose area on *regulatory* (battery:1242). Mutation **X1**, `('limited_purpose_area', ARRAY['regulatory'], …)`, **survives the battery at 90/90** (SF2).

### S-key. **Holds as scoped.**

`§` alone and `§§` are refused (no letter or digit). `16 TAC § 7.45` is refused (U8b). A trailing blank is refused (N13b; my X8 dropped the look-ahead and was caught there).

Accepted, consistent with R20 ("spelling is the loader's") but worth naming there:
- `16 TAC ７.45` (full-width digit)
- `16 TАC 7.45` (Cyrillic А)
- `§7.45 §`

`[[:alnum:]]` under `en_US.utf8` (the clone's ctype) is Unicode-wide, so look-alikes make distinct keys. This is note N1: either add "ASCII letters and digits only, plus §" to R20, or put `[A-Za-z0-9]` in the check. It costs nothing now, and repairing keys later means rewriting rows.

### T (U1–U10). **Hold.** All ten pass. I checked each against the refusing guard named in the findings.

### T-attr: stricter attribution. **Holds, with a residual weakness (N2)**

`caught()` (mutations-16.py:409-420) now needs `FAIL <check>`, or the run stopping inside the target with every earlier check passed. A race leg needs its own `FAIL Rn`, and setup failures count as misses. The weakness: "stopping inside the target" accepts *any* error raised inside that DO block, including one from a fixture statement rather than the guard. Checks that also match `SQLERRM` (U4, U5, U9) are immune. Checks that only trap a SQLSTATE are not. I found no mutation that this mis-attributes. It is a note.

---

## 1. Does it hold the spec?

| req | status |
|---|---|
| P1 state | held: the premise's own column, normalised (:812, :1128); a state place per row; R10 for validation |
| P2 county | held: kind, FIPS pattern; time zone and weather station facts; county sales tax via `sales_tax_rate` |
| P3 city | held: kind and facts (population, rate jurisdiction retained, residential taxable, sales tax rate) |
| P4 limited-purpose | held: kind on both axes now; gas-rate treatment residual R6 |
| P5 ETJ | held: kind on both axes now |
| P6 utility rate area | residual R3 |
| P7 tax jurisdictions | held: transit authority (exclusive), districts stack, district type, quarter-dated rates |
| P8 time zone | held: lookup that refuses (non-uniform state, unzoned peer, disagreement) |
| P9 weather | held (station fact); the WNA zone stays the utility's |
| P10 inside/outside | held: relation plus distance; R15 for the law's predicate; R16 cross-state |
| A1 owner type | held, as five owner types plus three system kinds; see SF1/SF3 |
| A2 commission jurisdiction | held: a separate dated fact on the profile |
| A3 size | residual R7 |
| A4 local adoption | held: keyed fact |
| A5 enforcing body | residual R11 |
| A6 customer attributes | residual R12 |
| A7 market role | out (R8) |
| D1 dates per axis | held, and now held for the ETJ → city transition on both axes (probe above) |
| D2 evidence | held: kind, reference, date ≤ recording |
| D3 many-to-many with cardinality | held: groups (county; municipal status; transit) and district stacking; "one rate area" is R3 |

Fit for what comes next:
- Law rows keyed on owner type: fine. Owner type and system kind are now separate columns, so a law row can key on either.
- Tax jurisdictions: fine.
- Annexation: fine (D1 probe).
- A utility in two states: profiles are per state. An owning place may be in another state (S3).
- A city system serving outside its limits: the outside relation with distance (P10).
- The one choice that is wrong for where this goes is SF1.

---

## 2. Integrity: no new hole found

Attacked without result:
- The state handshake (above).
- The tenant FK on memberships blocks a premise moving tenants.
- No trigger on `service_locations` rewrites `NEW.state` behind the `UPDATE OF state` guard. I grepped tu.sql: only `set_updated_at`, :8462.
- RLS on the lookups (invoker rights, unchanged).
- The vocabulary and grants on the new table (live probes above).
- Edits to `system_kind`.
- The time-zone precedence with tax-only ETJ memberships.

---

## 3. Tests

Mutations of my own, each on a fresh clone of the frozen patch with the full battery:

| # | mutation | result |
|---|---|---|
| X1 | limited-purpose area back to the regulatory axis only | **MISSED** (90/90) |
| X2 | `utility_system_kinds` dropped from the immutable-vocabulary trigger list (:656) | **MISSED** |
| X3 | `utility_system_kinds` dropped from the no-truncate list (:662) | **MISSED** |
| X4 | `tally_app` granted INSERT, UPDATE on `utility_system_kinds` (:313-314) | **MISSED** |
| X5 | `system_kind` nullable (:911) | **MISSED** |
| X6 | master_meter allowed for water and electric | caught, U6a |
| X7 | piped_propane_distribution allowed for water | **MISSED** (U6a tests only master_meter) |
| X8 | fact-key look-ahead removed | caught, N13b |
| X9 | state lock taken after the re-read | caught, R14/R19/R20 |
| X10 | ETJ in its own exclusivity group | caught, M5b |

A1 and A3 (battery:120-162) predate the new table and do not mention it. M04 and M05 were re-anchored to the new lists, but M04 drops only `place_kinds` and M05 drops every table at once, so neither shows that `utility_system_kinds` itself is guarded.

---

## Findings

### Blocking
None.

### Should-fix

**SF1. One system kind per tenant, service and state (modelling; settle now).**

`utility_service_profiles_no_overlap` keys on `(tenant_id, service_type, state_code, range)` (:940-943), and `utility_service_profile_as_of` takes no system kind (:1231). So a utility that runs a natural-gas distribution system *and* a piped-propane system in the same state cannot record both. Reproduced: a municipal/distribution TX gas profile, then a municipal/piped_propane_distribution TX gas profile over the same days → `utility_service_profiles_no_overlap`.

Round 4 split system kind from owner precisely because the law keys on it (NM 62-3-3(G)(2) reaches the propane system and not the city's gas system). After that split, "one profile per service and state" makes the system kind a property of the whole utility rather than of the system that serves a premise. Changing this later changes the key, the lookup's signature and what "the profile" means to the core; that is a meaning-changing migration. Now it is additive. Two options:
- (a) Add `system_kind` to the exclusion and to the lookup's arguments now. Which system serves a premise becomes a later service-point fact, stated as a residual.
- (b) Keep one system per tenant, service and state, and **state it as a residual** with the cost of reversing it.

My preference is (a), because it is cheap now, but either is defensible if written down.

**SF2. Tests for round 4's new surfaces.** X1–X5 and X7 survive. Add:
- a limited-purpose-area membership on the tax axis that only the axis check can refuse when the axis is removed;
- `utility_system_kinds` in A1 (application write), A3 (owner edit/delete) and a truncate;
- a NULL `system_kind` insert that expects `not_null_violation`;
- piped propane for a non-gas service (U6a covers only master_meter).

**SF3. Owners that are not a place, and joint municipal ownership (wording plus residual).**
- The special_district description invites recording an Oklahoma public trust or a New Mexico gas association as a `special_purpose_district` place, which premises could then join.
- Texas §101.003(8) treats a nonprofit corporation appointed by one or more cities as municipally owned.
- Suggested fix: say in `utility_owner_types` that a trust or nonprofit operating for a city records as `municipal` with the beneficiary city as owning place, and drop "public trust" and "gas association" from the special_district text. Add a residual that one owning place is recorded even where several cities own the system jointly.
- No source in hand puts a launch customer in either shape, so this is should-fix, not blocking.

### Notes
- **N1.** Fact keys accept Unicode look-alikes (full-width digits, Cyrillic letters) and a trailing `§`. Extend R20 or put ASCII classes in the check.
- **N2.** Mutation attribution "stopped inside the target" accepts any error raised in that block. Checks that trap only a SQLSTATE could credit a fixture error. No case found.
- **N3.** `political_subdivision` takes only a county. Kansas 12-808c's "other political or taxing subdivision" (townships) has no place kind. Extending it later means a new owner-type row, because vocabulary rows are immutable. That is fine, but worth knowing.
- **N4.** A migration that closes an owning place and its state in one transaction can deadlock against a profile insert (lock order state, then owner). It is benign, and R18 states the general case.
- **N5.** The header's profile paragraph (:136, :140) and the What-changes bullet (:83) carry over-long lines from the round-4 edit. Cosmetic.
