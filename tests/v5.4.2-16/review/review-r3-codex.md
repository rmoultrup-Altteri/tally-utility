**Verdict: not yet.** Two blocking integrity gaps remain: the new governing-state check is not preserved by place closure, and distance still accepts `NaN`.

Both frozen hashes match exactly:

- Patch: `c49b1ec5075e9b7eee16cdb9ad23603e`
- Battery: `af1013f9e2a4150afe986ab3a43903da`

This was a static review. I did not execute PostgreSQL, Docker, races or mutations, and changed no files. SQL below gives executable repros; their results are predicted from the code.

References below use **P** = `tests/v5.4.2-16/review/patch-16-frozen-r3.sql`, **B** = `tests/v5.4.2-16/review/battery-16-frozen-r3.sql`, **M** = `tests/v5.4.2-16/mutations-16.py`, and **R** = `tests/v5.4.2-16/races/place-close-16.sh`.

**Blocking findings**

**B1 — S-d’s governing-state invariant holds only at insertion.**

P:882–888 requires a state place covering the profile’s complete range. However:

- The profile takes a shared advisory lock only on `owning_place_id`, not its governing state (P:901–903).
- Place closure counts profiles only by `owning_place_id` (P:426–427).
- The profile lookup reads the profile without checking whether its governing state remains in force (P:1112–1120).

Consequently, insert an open investor-owned profile for an otherwise uncited state, then close that state before the profile ends. Both writes succeed, and the lookup still returns the profile after the state closes. This directly defeats the newly stated invariant at P:112–113.

There is also a race: a profile can read the still-open committed version of a state while its close is uncommitted. Neither side participates in a shared lock protocol for this relationship. READ COMMITTED alone does not fix that.

**Required:** serialize governing-state citations with state closure and include active governing-state profiles in the close floor. If state-place identity remains implicit through `state_code`, define how the floor distinguishes successive state-place versions. Voided profiles must be ignored. Add sequential and both-order race tests.

**B2 — S-e’s promised finite distance is missing.**

`distance_miles` is `numeric(8,3)` (P:604), and the outside-distance guard checks only `distance_miles > 0` (P:636–638). PostgreSQL accepts numeric `NaN` and orders it above ordinary numeric values. Thus `NaN` passes this check and is returned unchanged by `premise_places_as_of` (P:1025–1030). A later `distance_miles > 3` predicate would evaluate true rather than refuse an unknown distance. See PostgreSQL’s [numeric special-value semantics](https://www.postgresql.org/docs/current/datatype-numeric.html).

The precision constraint rejects infinity but does not substitute for rejecting `NaN`. No finite-value guard appears in the frozen patch.

**Required:** explicitly reject `NaN`; retain positive finite distances and NULL for unknown distance. Add a negative application-role test.

The following single script demonstrates both blockers in a disposable clone with the patch applied. It also demonstrates the whitespace issue below. Run as the database owner; application writes and lookups explicitly switch to `tally_app`.

```sql
\set ON_ERROR_STOP on
BEGIN;
SELECT public.uuid_generate_v4() AS t,
       public.uuid_generate_v4() AS u,
       public.uuid_generate_v4() AS c,
       public.uuid_generate_v4() AS l,
       public.uuid_generate_v4() AS s,
       public.uuid_generate_v4() AS city
\gset

INSERT INTO public.tenants(id, name, slug)
VALUES (:'t', 'R3 review', 'r3-' || :'t');

INSERT INTO public.users(id, tenant_id, display_name, email, role)
VALUES (:'u', :'t', 'Reviewer', :'u' || '@review.test', 'operator');

INSERT INTO public.customers(id, tenant_id, customer_number, customer_type)
VALUES (:'c', :'t', 'R3-C', 'residential');

INSERT INTO public.service_locations
  (id, tenant_id, customer_id, location_number,
   address_line1, city, state, zip)
VALUES
  (:'l', :'t', :'c', 'R3-L', '1 Main', 'Review City', 'TX', '78701');

-- No children or facts: only the forthcoming profile cites this state.
INSERT INTO public.places
  (id, kind_code, state_code, place_code, name,
   effective_from, source_note)
VALUES
  (:'s', 'state', 'QZ', 'QZ', 'Review State',
   DATE '1900-01-01', 'Fictional review fixture');

INSERT INTO public.places
  (id, kind_code, state_code, place_code, name,
   parent_place_id, effective_from, source_note)
SELECT :'city', 'municipality', 'TX', 'R3_REVIEW_CITY',
       'Review City', id, DATE '1900-01-01', 'Review fixture'
FROM public.places
WHERE kind_code = 'state' AND state_code = 'TX'
  AND effective_to IS NULL;

SET LOCAL app.user_id = :'u';
SET LOCAL ROLE tally_app;

INSERT INTO public.utility_service_profiles
  (tenant_id, service_type, state_code, owner_type,
   commission_jurisdiction, effective_from,
   evidence_reference, evidence_date)
VALUES
  (:'t', 'gas', 'QZ', 'investor_owned', true,
   DATE '2020-01-01', 'Review evidence', DATE '2020-01-01');

RESET ROLE;

-- B1: expected refusal; frozen patch permits this.
UPDATE public.places SET effective_to = DATE '2025-01-01'
WHERE id = :'s';

SET LOCAL ROLE tally_app;

-- B1: still answers after its governing state has ended.
SELECT *
FROM public.utility_service_profile_as_of(
  :'t', 'gas', 'QZ', DATE '2026-01-01');

-- B2: expected refusal; NaN satisfies the positive-distance check.
INSERT INTO public.premise_place_memberships
  (tenant_id, service_location_id, place_id, axis,
   relation, distance_miles, place_kind, valid_from,
   evidence_kind, evidence_reference, evidence_date)
VALUES
  (:'t', :'l', :'city', 'regulatory',
   'outside', 'NaN'::numeric, 'municipality', DATE '2020-01-01',
   'utility_record', 'Review evidence', DATE '2020-01-01');

SELECT distance_miles, distance_miles > 3 AS beyond_three_miles
FROM public.premise_places_as_of(:'l', DATE '2026-01-01', 'regulatory')
WHERE place_id = :'city';
-- Predicted: NaN, true.

RESET ROLE;

-- S1 below: both keys pass and coexist.
INSERT INTO public.place_facts
  (place_id, fact_code, fact_key, value, effective_from, source_note)
VALUES
  (:'city', 'local_adoption', 'HB 1', '"Ord. 1"',
   DATE '2020-01-01', 'Review fixture'),
  (:'city', 'local_adoption', E'HB 1\t', '"Ord. 2"',
   DATE '2020-01-01', 'Review fixture');

SELECT fact_key, length(fact_key)
FROM public.place_facts WHERE place_id = :'city';

ROLLBACK;
```

**Should-fix findings**

**S1 — S-g rejects surrounding spaces, not surrounding whitespace.**

P:475 uses `fact_key = btrim(fact_key)`. Default `btrim` removes spaces; a trailing tab or newline survives. Thus `'HB 1'` and `E'HB 1\t'` coexist for the same place and dates. The script above demonstrates the bypass.

B:902–905 tests only an ordinary trailing space. Reject leading/trailing whitespace explicitly, or narrow the documented promise to ordinary spaces. Given these are selection keys, I recommend rejection.

**S2 — New guard coverage is incomplete; the mutation total does not establish coverage of every leg.**

Specific missing discriminating cases:

- **Governing-state range:** N6a tests an absent state, not an existing state that begins too late or ends too early (B:809–812). Removing only the containment clause at P:884 should survive this case. M94 removes the whole existence check (M:242–243), so it does not establish containment coverage.
- **Voided membership, same-place replacement:** N4 replaces an unincorporated membership with an Austin membership (B:772–784). That tests the group exclusion, but not removal from `premise_place_memberships_no_repeat`. Removing only its `WHERE (voided_at IS NULL)` at P:645 would still permit N4’s different-place replacement.
- **Voided owning profile, place close:** N5 tests profile lookup and replacement (B:797–807); N17 tests the membership close-floor filter (B:952–961). There is no corresponding close after voiding the sole owning profile. Removing `u.voided_at IS NULL` at P:427 should survive.
- **Finite distance:** no NaN case.
- **Whitespace:** no tab/newline key case.
- **Concurrency:** the supplied races do not exercise two conflicting membership inserts, overlapping profile inserts, or a profile insert after waiting for an owning-place close. The exclusions are structurally appropriate, but those requested race scenarios are not demonstrated by R1–R12.

For N1, add the actual two-city annexation-window conflict alongside the existing two-county conflict, plus a conflict removed by voiding one membership. The implementation is generic, but these protect the intended composition.

**Round-2 disposition audit**

| Item | Result and attempted break |
|---|---|
| **N1** | **Fixed statically.** P:1057–1072 aggregates distinct zones only among maximum-specificity candidates and refuses disagreement. Agreeing duplicates remain valid; lower-specificity disagreement does not override a more specific answer. Outside memberships are excluded. N1/N2 exercise conflict and agreeing candidates (B:733–753). |
| **S-a** | **Fixed.** P:979–980 requires a begun, non-state place with no close date, including future scheduled closes. The shared lock is acquired before reading it; closure counts jurisdiction pointers. N9 and R10–R11 cover the new restriction and both pointer/close orders. Removing a pointer need not take the shared lock because it only removes a dependency. |
| **S-b** | **Fixed in the current implementation, with coverage gaps above.** P:686–704 freezes voided rows, stamps the void, requires an alphanumeric reason, and excludes changes to other columns. A previously closed row can be voided without changing its close. Insert paths clear caller-supplied void metadata (P:767–769, 918–920). Both membership exclusions, the profile exclusion, both relevant lookups, state guard and membership/profile close-floor legs ignore voided rows (P:424, 427, 645, 652, 796, 855, 1029, 1114). Time-zone lookup inherits that filtering. |
| **S-c** | **Fixed for membership applicability.** The new kind belongs to `municipal_status` (P:172–173), so it conflicts with a city, ETJ or limited-purpose membership on the same axis. Texas is seeded at P:1149–1152. **Note:** “one per state” is a loading convention, not a database invariant: different codes for this kind can coexist under P:319–321. |
| **S-d** | **Partial; B1 blocks.** Unknown and out-of-range governing states are refused at insertion, but closure can invalidate accepted profiles, sequentially or concurrently. |
| **S-e** | **Partial; B2 blocks.** Sales-tax `[0,1)` and population `≥0` checks are implemented (P:210–213, 513–515). Future evidence is refused for both row types (P:759, 889). Finite distance is not implemented. |
| **S-f** | **Fixed.** The explicit `!~ '^Etc/'` check closes the identified bypass (P:520). Server recognition plus the lexical gate remains in force. |
| **S-g** | **Partial; S1.** Ordinary surrounding spaces are refused, other surrounding whitespace is not. |
| **S-h** | **Accurately stated.** The normalized-state early return precedes isolation enforcement (P:790–793); all actual normalized changes require READ COMMITTED, including premises with no memberships. Header P:105–108 states this. |
| **S-i** | **Explicit residual R17**, P:1237–1240. FIPS/state-prefix consistency and alternate publisher codes are not claimed as database guarantees. |
| **S-j** | **Explicit residual R18**, P:1241–1244. Share-lock upgrade deadlocks remain possible; abort/retry preserves integrity. |

**Inventory requirement mapping**

“Holds” below means the foundation represents and guards the stated data, not that the future law engine is implemented.

| Requirement | Assessment |
|---|---|
| **P1 State** | **Partial.** Known dated state places and normalized premise reads exist (P:1016–1022); address validation is R10. Governing-profile lifetime has B1. |
| **P2 County** | **Holds foundation.** County kind, memberships, time-zone/weather facts and rate facts (P:164–165, 216–231). Publisher loads are R2/R17. |
| **P3 City/full-purpose limits** | **Holds foundation.** Municipality kind and population, retained jurisdiction, gas-taxability/rate facts (P:166–167, 220–227). Franchise integration remains R4. |
| **P4 Limited-purpose area** | **Holds kind; explicit residual R6** for unresolved gas-rate treatment (P:168–169, 1191–1193). |
| **P5 ETJ** | **Holds**, P:170–171; regulatory-only membership and municipal-status exclusion. |
| **P6 Utility rate area** | **Explicit residual R3**, P:1179–1182. Existing tenant jurisdictions remain undated; place pointer added. |
| **P7 Sales-tax jurisdictions** | **Holds representation; loading residual R2.** Separate tax memberships, transit and stacking districts, dated sales-tax facts (P:174–177, 224–229). Quarter-start publication discipline is not enforced by a dedicated constraint. |
| **P8 Time zone** | **Holds lookup foundation**, P:1043–1097, including N1 refusal. Existing consumer replacement is R5. |
| **P9 Weather reference** | **Holds representation**, county `weather_station` at P:230–231; existing WNA settings retained (P:951–962). |
| **P10 Municipal relation/distance** | **Partial.** Explicit within/outside and unknown-by-absence exist; finite distance fails B2. Cross-state distance is explicitly R16. |
| **A1 Owner type** | **Holds dated foundation**, seven types and compatible owning places (P:255–264, 819–927). Actual law keys remain R1. |
| **A2 Commission jurisdiction** | **Holds separate dated field**, P:825, 864; actual law keys remain R1. Profile validity is affected by B1. |
| **A3 Size thresholds** | **Explicit residual R7**, P:1194–1196. Population fact exists; utility counts and reproducible evaluation are deferred to core. |
| **A4 Local adoption** | **Holds keyed dated representation**, P:232–233, 478–480; key hygiene has S1. |
| **A5 Enforcing body** | **Explicit residual R11**, P:1211–1214. |
| **A6 Customer/meter attributes** | **Explicit residual R12**, P:1215–1218. |
| **A7 Retail role** | **Explicitly out, R8**, P:1197–1199. |
| **D1 Dates per axis** | **Holds**, P:602, 607–608, 642–652. No derivation between regulatory and tax dates. |
| **D2 Membership evidence** | **Holds**, P:609–611, 625–626, 639, 759–762. |
| **D3 Many simultaneous units/cardinality** | **Holds foundation**, P:642–652: exclusions for grouped within memberships, stacking districts, independent axes. Dated utility rate-area cardinality remains R3. |

The main modeling choices fit the planned work: ownership and commission status remain separate, multi-state utilities get profiles per governing state, an owning city may be in another state, and premise membership is independent of ownership. Thus a city utility can serve outside its limits or inside another city. Annexation does not rewrite the place or conflate tax and regulatory dates.

The residual boundary is substantial but explicit: this patch alone does not make existing state-only law readers safe for municipal utilities. Rule-terms §9 is deferred through R1, not completed.

**Other integrity conclusions and notes**

- **NULL legs:** required inputs are covered by NOT NULL constraints or explicit lookup refusals; membership state comparison uses `IS DISTINCT FROM`. The void helper does not provide a route to set only `voided_at` and bypass its reason rule. Its table CHECK alone has a NULL weakness, but the always-enabled trigger closes the write path.
- **Tenancy:** the new lookups are invoker-rights functions; both tenant tables have FORCE RLS and the canonical policy (P:657–660, 858–861). The composite premise/tenant FK and visible-premise read prevent cross-tenant membership insertion. Shared place facts are intentionally globally readable. I found no new tenant-data exposure through `jurisdictions.place_id`.
- **Security assumptions:** the new guards do not use trigger-depth exemptions or SECURITY DEFINER. They still depend on the platform’s existing trusted `app.user_id` identity convention. That is not a new authentication boundary.
- **Closure protocol:** for direct memberships, owning profiles and jurisdiction pointers, the shared-lock/read and exclusive-lock/close sequences are coherent under READ COMMITTED (P:420–437, 737–738, 902–903, 975–976). Governing states are the omitted relationship. Platform fact/child races remain explicitly covered by serialized migrations, R9.
- **Exclusion races:** GiST exclusions enforce membership and profile overlap independently of the ordinary snapshot reads. Close/void only shrinks active coverage and cannot extend a row past its place.
- **House patterns:** the all-tenants close-role check matches `sql/v5.4.2-13-backbilling-caps.sql:875–878`; the advisory-lock/isolation pattern follows the draft -15 rate guard at `sql/v5.4.2-15-deposits-law-to-core.sql:1102–1115`.
- **Race harness qualification:** R:71–97 checks for any lock-waiting session in the database, rather than identifying B’s PID and blocker. This is useful under the stated isolated, serial harness discipline; it is not proof of the expected wait if unrelated sessions share that database.

Approval is blocked on **B1 and B2**, with discriminating tests for their fixes. The remaining round-2 changes largely hold; whitespace normalization and the identified VOID test gaps should also be corrected before freezing the next revision.