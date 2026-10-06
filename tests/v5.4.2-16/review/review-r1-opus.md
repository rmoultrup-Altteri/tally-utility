# v5.4.2-16 review, round 1 (Opus)

**Hashes match the brief.** patch `a87f2e9fa2c716073d6b462bd7638f91`, battery `3c1d2f05fe64b25dc4122a03fbc27f3f`. `sql/v5.4.2-16-places-and-applicability.sql` (the file the mutation script reads) has the same hash as the frozen patch, and `tests/v5.4.2-16/battery-16.sql` is identical to the frozen battery.

**Baseline.** I cloned `tally` into `opus16`, revoked TEMP and strict-applied the patch: it applies cleanly. All battery checks pass (A1–G6), and so do R1–R3 in `races/place-close-16.sh`. `opus16` has been dropped.

## Verdict: **not yet**

There are three blocking items. Each one has a reproduction against the frozen patch.

---

## Blocking

### B1. A membership or profile written under REPEATABLE READ (or SERIALIZABLE) gets past the close floor
Only the closing side enforces READ COMMITTED (patch 330–334). The membership trigger takes the shared lock and then reads the place (557–558), and the profile trigger does the same (669–670). Those reads use the writer's transaction snapshot. Under RR or SERIALIZABLE, that snapshot was taken before the close committed. The lock does wait correctly, but the read that follows it is stale.

Reproduction (committed rows in `opus16`):
```
A: BEGIN ISOLATION LEVEL REPEATABLE READ; SET LOCAL app.user_id=<T1 user>; SET ROLE tally_app;
   SELECT count(*) FROM places;           -- snapshot taken
   SELECT pg_sleep(3);
B: UPDATE places SET effective_to='2024-01-01' WHERE id=<OCITY2>;   -- succeeds, nothing cites it yet
A: INSERT membership (OCITY2, valid_from 2020-01-01, open);         -- accepted
   INSERT profile (municipal, owning_place OCITY2, 2020-01-01, open); -- accepted
   COMMIT;
```
Result: `places.effective_to = 2024-01-01`, with an open membership and an open profile citing it. `premise_places_as_of(L1, 2026-06-01, 'regulatory')` then returns OCITY2, a place that has been closed for two years. The header's claims "a place not in force over the whole membership" (71) and "a membership racing the close waits on a lock" (61–62) are both false here. SERIALIZABLE does not save it either: the close is forced to READ COMMITTED, so SSI never sees a cycle.

**Fix.** Two options:
- Refuse non-READ-COMMITTED in both insert paths, using the same guard as the close.
- Or read the place through a SECURITY DEFINER helper that does `SELECT … FOR KEY SHARE`/`FOR SHARE`. That raises a serialization error under RR when the row was updated concurrently.

Add an R4/R5 to the race script that runs the writer under RR.

### B2. Changing a premise's state leaves its memberships in another state, and the time-zone lookup answers from the old state's county
The state-of-premise guard (569) runs only when a membership is inserted. Nothing stops `UPDATE service_locations SET state = …` afterwards, and tally_app holds UPDATE on that table.

Reproduction (as tally_app, T1):
1. Insert a membership of El Paso-area premise L2 in county 48141 (El Paso County, TX).
2. Run `UPDATE service_locations SET state='OK'`.

Results:
- `premise_places_as_of(L2, 2026-06-01, 'regulatory')` returns `county|TX|48141` **and** `state|OK|OK`.
- `premise_time_zone_as_of(L2, …)` returns **America/Denver** for an Oklahoma premise. This is a wrong answer, not a refusal.

The header lists "a place of another state than the premise's" (71) as refused, but that only holds at insert.

**Fix.** Either option works:
- A trigger on `service_locations` that refuses a change of the normalised state while any membership is in force on or after the change.
- Or have `premise_places_as_of` and `premise_time_zone_as_of` refuse when any membership's place state differs from `upper(btrim(l.state))`.

The lookup-side check is cheap and keeps R10 intact. Both are additive.

### B3. For a premise in a split-zone state with no county row, the time-zone lookup guesses from the state
`premise_time_zone_as_of` (763–784) takes the most specific place that has a `time_zone` fact. It falls back to the state's fact, and the seed (827–828) gives Texas America/Chicago. Its source note says "Central time, **except** the counties in Mountain time".

Reproduction: El Paso premise L2 (city El Paso, zip 79902), with no county membership recorded, returns **America/Chicago**. The correct answer is Mountain, or a refusal. That is exactly the "lookup returns a wrong answer instead of refusing" case the brief asks about. It is also the "no live fallback" rule: the state value is used as a fallback for a missing county coordinate.

The same thing happens in two other cases:
- The county membership is recorded on the **tax** axis only. The lookup reads only `'regulatory'` (771).
- A county's tz fact is closed without a successor.

**Fix.** Either option works; both are additive:
- A state-level fact (for example `time_zone_uniform boolean`, or `time_zone_varies_by = 'county'`). When the state's zone is not uniform, the lookup requires the county's fact and refuses without it.
- Or give a split state no state-level tz fact, so its counties must carry one, and seed all TX counties (R2 already plans the county load).

Also decide whether the county read should be axis-independent. A county is one county on either axis.

---

## Should-fix

**S1. "Outside the city" cannot be told apart from "not recorded" (P10).** The only representation of a premise being outside a city is the absence of a municipality membership. A law keyed on inside or outside would therefore guess on any premise whose memberships were never entered. Examples: TX §103.053 outside-city appeal class, KS 66-104(b) 3 miles, NM 3-25-3 5 miles.

The inventory says P10 is "derived from place membership **plus distance** where the law needs it" (inventory line 59). The patch claims P10 in the membership comment (537), but there is no distance, and distance is not listed as a residual. Two things are needed:
- A positive record, for example a per-premise, per-axis "places recorded as of" attestation or an explicit unincorporated marker, so the lookup can refuse instead of reading absence as "outside".
- A stated residual for distance.

Both are additive, but the "refuse rather than guess" promise depends on the first.

**S2. A premise can be in the city and in its ETJ (or limited-purpose area) on the same day.** `single_kind` is per kind (523–526), so `municipality` + `extraterritorial_area` + `limited_purpose_area` stack. Probe: L1 in OCITY + OETJ1 on 2022-01-01, accepted. These are one dimension (full-purpose, limited-purpose, ETJ, or none) and should be mutually exclusive per axis. A shared "exclusion group" column on `place_kinds`, used in the exclusion in place of `place_kind`, would do it. This is a schema change and costs more to add later.

**S3. `local_adoption` (A4) can hold only one adopted law per place.** `place_facts_no_overlap` (387–388) allows one row per place, fact and range, and `local_adoption` is a single text value (174). Probe: a second adoption on the same county was refused with `exclusion_violation`. A city that adopts two opt-in laws cannot be recorded. Fix: key the fact by the adopted law (for example `local_adoption:<citation>` as boolean facts), or add a `qualifier` column to the exclusion. Either is meaning-changing for A4, so settle it now.

**S4. The owner type does not constrain the owning place's kind.** 668–677 checks only "not a state". Probes accepted:
- a `municipal` profile owned by a **transit authority**;
- a `municipal` profile owned by an **ETJ**.

`utility_owner_types` should carry the allowed place kinds (municipal → municipality; political_subdivision → county or municipality; special_district → special_purpose_district). Law rows will key on this pair, so a wrong pair produces a wrong law.

**S5. `premise_places_as_of` accepts any axis.** A NULL or unknown axis (`'zoning'`) returns just the state row, which is a confident partial answer (probe: 1 row each). It should refuse an axis outside `('regulatory','tax')`.

**S6. One tenant can block every other tenant's memberships in a shared place.** `place_lock_key` is executable by tally_app, and so are the advisory-lock built-ins. Probe:
- T1, as tally_app, takes `pg_advisory_lock(place_lock_key(county))` at session level.
- T2's membership insert in that county then waits until `lock_timeout` ("canceling statement due to lock timeout … pg_advisory_xact_lock_shared").

Because places are shared, this is a cross-tenant availability coupling that -15's per-tenant key did not have. Mitigations: revoke EXECUTE on `place_lock_key` from tally_app and call it only from SECURITY DEFINER code (tally_app can still compute the hash with `hashtextextended`, so this is partial). Alternatively, state it as a residual and set `lock_timeout` in the app.

**S7. A membership or profile can be closed retroactively, which silently rewrites history.** The close path (584–596, 683–695) accepts any `valid_to > valid_from`. Probe: a membership from 2020-01-01 was closed today with `valid_to = 2020-01-02`, and it was accepted. That rewrites which city a premise was in for periods already billed or taxed. Either bound a close (`valid_to >= current_date`, with a separate stamped correction path), or say in the header that a close may be backdated and why.

**S8. `created_by` is not stamped from the session.** The membership and profile triggers check `created_by` only when it is supplied (550, 660). Probe: a membership with `created_by` NULL was accepted. -13 stamps from `app.user_id` (`NEW.opened_by := v_user`, -13 2235). Stamp it the same way, and stamp `closed_by`. A malformed `app.user_id` currently becomes a silent NULL (591–595, 690–694).

**S9. `jurisdictions.place_id` is unchecked and undated (728–731).** Probes accepted:
- a pointer to a **closed** place;
- a pointer to **another state's** state place (`OK`);
- an UPDATE that **re-points** an existing row to a county.

The close floor (336–348) also does not count jurisdictions that point at the place. At minimum: the place must be in force (or open) when it is set, it must not be a state, it should be immutable once set, and it should either be counted in the close floor or the gap should be stated as a residual next to R3.

**S10. Tests.** I ran 11 extra mutations of my own against the frozen battery. Nine survive with the battery reporting all PASS:

| # | Mutation | Result |
|---|---|---|
| X1 | close floor `m.valid_to > NEW.effective_to` → `>=` (no boundary case) | MISSED |
| X2 | membership `created_at := now()` removed (caller back-dates it) | MISSED |
| X3 | `place_fact_kinds` dropped from the immutability list (A3 tests only `place_kinds` and `utility_owner_types`) | MISSED |
| X4 | membership insert no longer nulls `closed_at` and `closed_by` (pre-stamped close) | MISSED |
| X5 | profile close not stamped (P5 never reads `closed_*`) | MISSED |
| X6 | `premise_places_as_of` range `[)` → `[]` (no read on a `valid_to` day; L4 reads 02-01 and 05-01, not 04-01) | MISSED |
| X7 | profile `assert_same_tenant_user` removed | MISSED |
| X9 | membership `assert_same_tenant_user` removed | MISSED |
| X10 | profile range check `>` → `>=` (no zero-length profile close) | MISSED |
| X8 | membership containment `@>` → `&&` | caught (M4a) |
| X11 | place close isolation check relaxed | caught by R3 (not the battery) |

Also:
- **G3 is not unique to one guard.** It accepts `foreign_key_violation OR insufficient_privilege`. The trigger's "not visible" lookup fires first, so the RLS WITH CHECK leg is never the guard under test.
- **Missing boundary cases** (memory: test the boundary): membership `valid_to` = place `effective_to` is allowed; close = membership `valid_to` is allowed; a fact ending on the place's close.
- **No test** for profile cross-tenant write, profile close stamp, `place_membership_evidence_kinds` and `place_fact_kinds` privileges or immutability, or the RR writer race (B1).
- **No test** for a state change after a membership (B2) or the El Paso no-county case (B3).

---

## Notes

- **N1. `commission_jurisdiction` is one boolean per utility, service and state.** KS 66-104(b)/66-104f puts a municipal system under the KCC for premises more than 3 miles outside its limits only. TX §103.053 gives outside-city ratepayers an RRC appeal. So jurisdiction status is partly a function of the premise, not just the utility. That is fine if law rows key on (owner type, status, premise inside/outside or distance), but then S1 is required. State this in R1.
- **N2. Odd tz names pass the time_zone type check.** `pg_timezone_names` accepts `Factory`, `posixrules`, `EST5EDT` and `Etc/GMT+6` (probe: `"Factory"` accepted). Consider a canonical-zone check (`'^[A-Z][a-z]+/'`), or a vocabulary list. tzdata changes on a server upgrade are not re-checked.
- **N3. Place hierarchy is unchecked.** A county whose parent is a transit authority was accepted, and so was a municipality with no parent. Neither is refused or stated.
- **N4. The close floor relies on the closer bypassing RLS.** It runs with invoker rights against a FORCE-RLS table (336–341). `tally` is a superuser (`rolsuper=t`), so it sees every tenant. A non-superuser migration role would see only its own tenant (or none) and would close over other tenants' memberships. State that platform closes run as a BYPASSRLS role, or make the floor SECURITY DEFINER.
- **N5. TRUNCATE is unguarded for the owner.** `places`, `place_facts` and the four vocabularies have no `no_truncate` (statement) trigger, while -13 adds one to its tables. Owner-only, but `TRUNCATE place_kinds CASCADE` empties everything except the tenant tables.
- **N6. Caller-supplied dummies.** Callers must supply `place_kind` and `single_per_premise` (NOT NULL, overwritten), so the battery passes `'x'`/`'state'`. A default, or documenting "ignored", would be cleaner.
- **N7. Negative `census_population` is accepted** (the `number` type has no range).
- **N8. Membership evidence (D2) has no date column.** The ordinance date or Comptroller quarter lives in free-text `evidence_reference`.
- **N9.** The 49 CFR 71.7(e) citation matches `places-sources/texas.md:224`.

---

## Spec coverage (inventory §2)

| Req | Status |
|---|---|
| P1 state | Held as a place kind. The premise's state is unvalidated (R10, stated). B2 breaks consistency after a change. |
| P2 county | Held (kind, FIPS pattern, tz and weather facts). |
| P3 city facts | Held (census, rate jurisdiction, taxability facts). |
| P4 limited-purpose area | Kind held; R6 stated. Exclusivity with the city is missing (S2). |
| P5 ETJ | Kind held; exclusivity is missing (S2). |
| P6 utility rate area | Residual R3, stated. |
| P7 sales-tax jurisdictions | Kinds and axis held. "Rate history at quarter-start dates" is not modelled and not stated as a residual. |
| P8 time zone | Held, but B3 (guesses from the state) and B2. |
| P9 weather | Station fact held; WNA zone stays. |
| P10 inside/outside, distance | **Missed.** Absence is not "outside" (S1); distance is not stated. |
| A1 owner type | Held (7 types). Owning place kind is unconstrained (S4). |
| A2 commission status | Held as a dated boolean. Premise-dependent cases need N1 and S1. |
| A3 size | Residual R7. It deviates from inventory §4.3 ("the customer count" as a utility fact), but the deviation is stated. |
| A4 local adoption | Held for one law only (S3). |
| A5 regulator per rule set | **Not mentioned.** Belongs to law rows; state it with R1. |
| A6 customer class and attributes | **Not mentioned.** Out of this patch, but state it. |
| A7 market role | R8, stated. |
| D1 dates per axis | Held (L4 shows it). |
| D2 evidence | Held (kind and reference), without a date (N8). |
| D3 many memberships with cardinality | Held per kind. Cross-kind cardinality is missing (S2). |

## Modelling for where this goes next
- **Law rows keyed on owner type and status:** sound, given S4 and N1.
- **Tax jurisdictions:** kinds and axis are fine. Rates and quarter history need a home, and S1 matters for tax too (an unrecorded city tax is a silent under-collection).
- **Annexation:** the close-and-open pair per axis is right. S2 is needed so the ETJ membership must close first, and S7 so annexation history cannot be backdated.
- **A utility in two states:** profiles are per state. Fine.
- **A city system serving outside its limits:** needs S1 and N1.
