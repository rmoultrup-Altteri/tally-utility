**Verdict: not yet.** Blocking items are the stale-snapshot insert path, lookups that return partial or contradictory applicability instead of refusing, and inventory requirements that are neither implemented nor explicitly deferred.

Both frozen MD5s match:

- Patch: `a87f2e9fa2c716073d6b462bd7638f91`
- Battery: `3c1d2f05fe64b25dc4122a03fbc27f3f`

This was a static review. No repository files or databases were changed. SQL below is an exact proposed reproduction, **not an executed result**.

References below use:
`P` = `tests/v5.4.2-16/review/patch-16-frozen-r1.sql`;
`B` = `tests/v5.4.2-16/review/battery-16-frozen-r1.sql`;
`R` = `tests/v5.4.2-16/races/place-close-16.sh`;
`M` = `tests/v5.4.2-16/mutations-16.py`.

**Requirement coverage.** “Held” here means the foundation represents the requirement; it does not mean its downstream law evaluator exists.

| Requirement | Assessment |
|---|---|
| P1 State | **Partial; residual plus defect.** State kind/code equality exists (`P:122,294`). Address validation is deferred by R10 (`P:875`), but its promised lookup refusal is false; see blocking finding 2. |
| P2 County | **Held.** County kind, independent memberships, weather/time-zone facts (`P:124,162,172,488`). |
| P3 Full-purpose city | **Held as foundation.** Municipality and population/jurisdiction/taxability facts (`P:126,164–169`). Franchise migration is residual R4 (`P:859`). |
| P4 Limited-purpose area | **Held; stated residual.** Regulatory-only kind (`P:128`); gas-rate meaning deferred in R6 (`P:867`). |
| P5 ETJ | **Held.** Regulatory kind (`P:130`); downstream rules must not infer gas-rate authority merely from membership. |
| P6 Utility rate area | **Stated residual R3.** Existing undated jurisdictions retained, optional shared-place pointer added (`P:728,855`). |
| P7 Tax jurisdictions | **Partial/miss.** Kinds, type/taxability facts and tax memberships exist (`P:124–175,488`). No tax-rate history or quarter-start rate constraint, and no explicit residual for that requirement. |
| P8 Time zone | **Partial; residual.** Typed dated facts and precedence exist (`P:162,413,763`). Consumer replacement is R5 (`P:863`). Missing-county fallback can guess incorrectly; see below. |
| P9 Weather reference | **Held as foundation.** County weather-station fact (`P:172`); existing utility WNA settings retained (`P:723–733`). |
| P10 Boundary relation/distance | **Partial/miss.** Membership plus owning city can establish recorded inside membership (`P:488,618`). No dated distance or explicit outside/unknown fact, and no stated distance residual. |
| A1 Owner type | **Held as dated fact; law keys residual R1.** Seven types and profiles (`P:198–204,611,845`). Owner-place compatibility needs improvement. |
| A2 Commission status | **Held as dated fact; law keys residual R1.** Separate boolean, per-state profile and exclusion (`P:615–639,845`). |
| A3 Size thresholds | **Stated residual R7.** Census population exists; utility counts delegated to the future core (`P:164,870`). Reproducible historical counts remain a downstream obligation. |
| A4 Local adoption | **Partially held.** Dated cited text fact (`P:174`), but only one simultaneous `local_adoption` per place (`P:387`); multiple independently adopted laws need a better key. |
| A5 Enforcing body | **Missed disposition.** Neither represented here nor expressly listed as a residual. R1 addresses owner/status keys, not enforcing bodies (`P:845–883`). |
| A6 Customer/meter attributes | **Missed disposition.** No mapping of existing facts to this requirement and no explicit residual (`P:845–883`). This is not a claim that all existing customer attributes are absent. |
| A7 Retail role | **Stated residual/out of scope R8** (`P:873`). |
| D1 Independent dates | **Held.** Separate axis rows and date ranges (`P:493–497`); tested with differing annexation/tax dates (`B:245–268,404–413`). |
| D2 Evidence | **Held at text-reference level.** Required evidence kind/reference (`P:498–515`). Ordinance date and retrieval date can be written in the reference; they are not structurally required. |
| D3 Concurrent memberships | **Held for implemented kinds; partial overall.** Race-safe exclusions (`P:518–526`), stacking districts. Rate-area dating is R3; missing versus known-outside remains unresolved. |

The owner/status law-key deferral is explicit and compatible with the staged rebuild in convention §12. It must not be mistaken for existing law lookups already distinguishing municipal systems (`P:51–55,845–850`).

**Blocking 1 — the advisory protocol protects the close’s snapshot, but not the insert’s snapshot.**

Only `enforce_place()` restricts isolation (`P:330–335`). Membership and profile inserts take an advisory lock and then perform ordinary reads (`P:557–574,669–672`), without restricting isolation or forcing a row-version conflict.

A REPEATABLE READ transaction can establish its snapshot, let another transaction close the place, then insert an open membership/profile using the old open-place version. The close saw no citation; the insert sees no close. Waiting for the advisory lock does not refresh its transaction snapshot.

Do not count on the foreign key to validate the range: the place ID still exists. PostgreSQL’s key-share locking specifically permits following updates that did not change the key. This is a source-based inference requiring the reproduction below on the deployed PostgreSQL version. [PostgreSQL locking implementation](https://github.com/postgres/postgres/blob/REL_17_STABLE/src/backend/access/heap/heapam.c#L4661-L4707)

Fix by rejecting unsupported isolation on **both citation insert paths**, or using a protocol that detects stale versions. Test both operation orders. The existing race script tests only citation-first/close-second and REPEATABLE READ **closing** (`R:39–50,74–84`).

**Blocking 2 — “unrecognised state means every lookup refuses” is not true.**

`premise_places_as_of()` independently unions memberships with a state lookup (`P:745–758`). Its membership branch does not join the current premise state or check that a valid state place exists. It also does not recheck the place’s validity.

Consequences:

- After recording an El Paso County membership, updating `service_locations.state` to `Texas` still produces that membership and `America/Denver`. This directly contradicts R10 (`P:875–879`).
- Changing state to another seeded state can return that new state **and old-state memberships** together.
- Missing premise, missing state or NULL date produces an empty set, not a refusal.
- NULL or misspelled axis can return the state alone, because the state branch ignores `p_axis`.

The base state column is editable; its existing update trigger only stamps `updated_at` (`sql/tu.sql:4440,8462`). R10’s deferral of write validation does not justify incorrect reads.

The resolver should validate premise visibility, arguments, normalized state resolution and membership consistency, then refuse inconsistent/incomplete data. A write-side state-change protocol is also needed; checking state only on membership insertion permits subsequent changes and races (`P:551,569`).

**Blocking 3 — the inventory completion claim omits required dispositions.**

The header promises every requirement is held or explicitly residual (`P:11–13`). P7’s rate history, P10’s distance, and A5/A6’s disposition do not satisfy that promise.

At minimum, explicitly defer each missing item with its intended representation and consumer boundary. In particular, “boundary geometry is out of scope” (`P:873`) is not a deferral of recording a cited distance fact: the inventory already distinguishes determination of geography from storing the resulting facts (`application/places-source-inventory-2026-10-06.md:59,89`).

**Should-fix — applicability modelling before downstream keys depend on it.**

1. **Unknown membership is not outside-city evidence.** There is no completeness or explicit outside assertion. A city-owned system can correctly serve premises outside its own municipality, including inside another municipality, but absence of its city membership cannot distinguish that situation from incomplete onboarding. Do not implement P10 as `NOT EXISTS(owning-city membership)` without additional evidence (`P:488–537,648`).

2. **Public ownership is incorrectly tied to the service state.** Per-state profiles correctly support different commission status in two states, but `P:671` prohibits the same city owning a profile for service across a state line. Ownership location and the state whose rules govern service are different dimensions. Conversely, a `municipal` profile may name a county, ETJ or district: only `state` is forbidden. Add an explicit owner/place-kind compatibility model and decide cross-state ownership rather than forcing invented owners (`P:180–204,662–674`).

3. **Time-zone fallback can silently be wrong.** Texas gets an unconditional Chicago fact (`P:827–828`). An El Paso premise without a recorded county membership therefore gets Chicago. This is an onboarding omission, not evidence that it lies outside the exception counties. The seeded exception scheme needs required county evidence, an explicit completeness contract, or refusal. City-over-county precedence is implemented (`P:774`), but only county-over-state is tested (`B:392–397`).

4. **Local adoption lacks a law identifier in its uniqueness key.** Two different concurrently adopted laws conflict under `(place_id, fact_code, range)` (`P:174,387–388`). A delimited text list would lose independent effective dates. Use a keyed adoption relation or explicitly registered per-law fact kinds.

5. **Vocabulary NULL elements can weaken guards.** `place_fact_kinds.place_kinds` only checks nonempty cardinality (`P:151`). For example, `ARRAY['municipality',NULL]` makes a county’s `kind = ANY(...)` NULL, so `IF NOT (...)` does not reject it (`P:408`). These are platform-written rows, but the advertised structural validator should reject NULL elements and unknown kind codes. Seeded arrays do not currently exhibit this defect.

**Integrity observations that are not additional blockers.**

- The membership single-kind/no-repeat and profile-overlap rules are actual exclusion constraints, with required discriminator columns and trigger-derived facets (`P:488–526,611–639`). They are substantially stronger than snapshot-based “does another row exist?” guards and should arbitrate concurrent conflicts.
- The patch introduces no SECURITY DEFINER functions or trigger-depth bypass. Lookups remain invoker-rights; new tenant tables have canonical forced RLS (`P:531–534,642–645`). Shared places are intentionally visible to all tenants.
- `jurisdictions.place_id` references shared data, so its single-column FK is not itself a tenant leak (`P:728–733`). The existing premise-to-jurisdiction FK was already tenant-bound in -13 (`sql/tu.sql:23728`). The pointer is undated and can name a closed place; that must remain outside historical applicability until R3 is addressed.
- Sequential closes check all four declared dependent classes (`P:336–347`). Facts and children do not acquire the place lock (`P:300–307,405–424`), so their concurrent insertion remains unsafe, but this is **explicit residual R9** (`P:880–883`). State clearly that reviewed platform writes must be serialized; “reviewed” alone is not synchronization.
- Compared with house patterns, -13 explicitly requires no concurrent evaluations during platform closes (`sql/v5.4.2-13-backbilling-caps.sql:2545`). Its row-version technique for another race explicitly handles REPEATABLE READ (`same file:1117`). Copying -15’s advisory-lock shape does not supply that guarantee.

**Tests: no, not every guard has an isolated negative case.**

The battery does useful isolation work: M5c uses a stacking district to isolate no-repeat (`B:263–267`), and C1–C4 provide separate dependent classes for close floors (`B:420–454`). Nonetheless:

- Add the reverse-order stale-snapshot probes below, plus simultaneous single-kind memberships and overlapping profiles. The current race suite has neither exclusion race.
- Add state mutation/race, invalid/NULL axis/date, nonexistent/foreign-tenant premise, and foreign-tenant profile **lookup** tests. G2 checks direct tables, not the lookup functions (`B:480–487`).
- Add place/fact/profile nonpositive ranges, membership/fact/profile reopen and second-close attempts, successful profile-close stamps, and positive lookup results exactly at close/successor boundaries. Only place second-close is explicit (`B:459–462`).
- Independently exercise all four vocabularies’ immutability and all six shared tables’ write ACLs. A1/A3 sample only some tables and operations (`B:86–123`).
- Boolean fact typing and JSON `null`/array/object values are not exercised by F2 (`B:156–171`).
- Replace nullable success assertions with `IS DISTINCT FROM` and explicit row-existence checks. For example, `IF v <> 'America/Denver'` accepts NULL (`B:394`); a mutation returning NULL only for TX can evade L2 while preserving L3’s expected refusal.
- The mutation runner reads **working**, not frozen, artifacts (`M:18–19`). They currently compare equal, but the harness does not establish frozen provenance.
- It can count an unrelated earlier `ERROR` as a catch when the target PASS never appeared (`M:199–205`). Printing the first error is useful but does not prove the named guard caught its mutation.
- Race coordination uses sleeps, checks only the closer’s message, and does not assert an observed wait or successful writer completion (`R:39–53`). A scheduling delay can turn the supposed race into an ordinary sequential refusal.

**SQL reproduction for findings 1 and 2.** Run only in a disposable patched clone. Setup as migration owner:

```sql
INSERT INTO public.tenants(id,name,slug)
VALUES ('00000000-0000-4000-8000-000000001691','Review16','review16');

INSERT INTO public.users(id,tenant_id,display_name,email,role)
VALUES ('00000000-0000-4000-8000-000000001692',
        '00000000-0000-4000-8000-000000001691',
        'Reviewer','review16@example.test','operator');

INSERT INTO public.customers(id,tenant_id,customer_number,customer_type)
VALUES ('00000000-0000-4000-8000-000000001693',
        '00000000-0000-4000-8000-000000001691','R16','residential');

INSERT INTO public.service_locations
(id,tenant_id,customer_id,location_number,address_line1,city,state,zip)
VALUES ('00000000-0000-4000-8000-000000001694',
        '00000000-0000-4000-8000-000000001691',
        '00000000-0000-4000-8000-000000001693',
        'R16','1 Main','El Paso','TX','79901');

INSERT INTO public.places
(kind_code,state_code,place_code,name,effective_from,source_note)
VALUES
('municipality','TX','REVIEW16A','Review A','2000-01-01','fixture'),
('municipality','TX','REVIEW16B','Review B','2000-01-01','fixture');
```

Session A, execute and pause:

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL ROLE tally_app;
SET LOCAL app.user_id = '00000000-0000-4000-8000-000000001692';

SELECT place_code,effective_to
FROM public.places
WHERE place_code IN ('REVIEW16A','REVIEW16B');
-- Snapshot now established; leave transaction open.
```

Session B, owner, commit the closes:

```sql
BEGIN ISOLATION LEVEL READ COMMITTED;
UPDATE public.places SET effective_to = DATE '2030-01-01'
WHERE place_code IN ('REVIEW16A','REVIEW16B');
COMMIT;
```

Resume session A:

```sql
INSERT INTO public.premise_place_memberships
(tenant_id,service_location_id,place_id,axis,place_kind,
 single_per_premise,valid_from,evidence_kind,evidence_reference)
SELECT l.tenant_id,l.id,p.id,'regulatory','x',true,
       DATE '2026-01-01','utility_record','fixture'
FROM public.service_locations l CROSS JOIN public.places p
WHERE l.id = '00000000-0000-4000-8000-000000001694'
  AND p.place_code = 'REVIEW16A';

INSERT INTO public.utility_service_profiles
(tenant_id,service_type,state_code,owner_type,
 commission_jurisdiction,owning_place_id,effective_from,evidence_reference)
SELECT '00000000-0000-4000-8000-000000001691',
       'gas','TX','municipal',false,id,DATE '2026-01-01','fixture'
FROM public.places WHERE place_code = 'REVIEW16B';
COMMIT;
```

Predicted defect: both inserts commit open-ended references to places closed in 2030. Verify as owner:

```sql
SELECT m.valid_to,p.effective_to
FROM public.premise_place_memberships m
JOIN public.places p ON p.id=m.place_id
WHERE p.place_code='REVIEW16A';

SELECT u.effective_to AS profile_end,p.effective_to AS place_end
FROM public.utility_service_profiles u
JOIN public.places p ON p.id=u.owning_place_id
WHERE p.place_code='REVIEW16B';
```

Independent state/axis probe, using the same setup:

```sql
BEGIN;
SET LOCAL ROLE tally_app;
SET LOCAL app.user_id = '00000000-0000-4000-8000-000000001692';

-- Wrong: an invalid axis still returns the TX state.
SELECT * FROM public.premise_places_as_of(
 '00000000-0000-4000-8000-000000001694','2026-06-01','typo');

INSERT INTO public.premise_place_memberships
(tenant_id,service_location_id,place_id,axis,place_kind,
 single_per_premise,valid_from,evidence_kind,evidence_reference)
SELECT l.tenant_id,l.id,p.id,'regulatory','x',true,
       DATE '2026-01-01','utility_record','fixture'
FROM public.service_locations l CROSS JOIN public.places p
WHERE l.id='00000000-0000-4000-8000-000000001694'
  AND p.kind_code='county' AND p.place_code='48141';

UPDATE public.service_locations SET state='Texas'
WHERE id='00000000-0000-4000-8000-000000001694';

-- Wrong: returns Denver despite an unrecognised normalized state.
SELECT public.premise_time_zone_as_of(
 '00000000-0000-4000-8000-000000001694','2026-06-01');
ROLLBACK;
```