**Verdict: not yet.** Two blocking gaps remain: ambiguous time-zone resolution across axes, and cross-state ownership that cannot represent the premise’s outside relation to its owning city.

Both frozen hashes match exactly:

- Patch: `24998853c2a18e4c49ab0325a4a8ad4e`
- Battery: `ef1c7da0baa64ee8cf727fb931e40b07`

The working patch and battery also match those hashes. This was a static review; I did not run Docker, change files, or independently verify the reported test results.

References below use **P** = `tests/v5.4.2-16/review/patch-16-frozen-r2.sql`, **T** = `tests/v5.4.2-16/review/battery-16-frozen-r2.sql`, **R** = `tests/v5.4.2-16/races/place-close-16.sh`, and **M** = `tests/v5.4.2-16/mutations-16.py`.

**Blocking findings**

**N1 — The time-zone fix introduces an ambiguous lookup that guesses.** Membership exclusivity is per axis (P:614–617). Consequently, the same premise can have Travis County on one axis and El Paso County on the other. Both are valid inputs to the revised time-zone lookup. It combines both axes, sorts only by specificity, and takes one row (P:968–976). Equal-specificity, different-zone candidates produce an arbitrary answer instead of refusal.

This also affects municipalities: independently dated regulatory and tax memberships can legitimately differ during a transition—the battery explicitly demonstrates this at T:557–571. The comment that geography is the same on both axes (P:966) does not make tax-effective membership equivalent to current physical geography.

Required change: define how physical geography resolves across axes; at minimum, refuse conflicting zone values among equally preferred candidates. Adding a deterministic tie-breaker merely makes the guess repeatable. Preserve tax-only county support and permit duplicate, agreeing candidates.

**N2 — Cross-state ownership and outside-distance relations do not compose.** A municipal utility may now have a profile governed by another state (P:808–819; tested at T:464–471). But a premise in that other state cannot record `outside` plus distance relative to its owning city: the membership trigger requires identical states for *every* relation (P:670–674).

Changing that trigger alone is insufficient. The lookup discards every cross-state relation (P:947), and the premise-state guard treats outside relations as evidence that the premise belongs to the referenced state (P:719–727).

Thus the exact cross-state utility supported by the new profile fixture cannot express P10’s premise-to-owner boundary fact. This is an undisposed foundation gap, not a missing future law predicate. Keep same-state enforcement for geographic containment; define separate validation and lookup treatment for outside relations, including their interaction with state changes.

These are exact SQL probes to append **after T:748 and before its existing `ROLLBACK`**, using the frozen battery’s fixtures. They require no changes to repository files. Expected outcomes below are static predictions, not observed runs.

```sql
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000016b1';
SET LOCAL ROLE tally_app;

-- N1: L1 already has El Paso County on the regulatory axis.
-- Its tax axis has no county. Both inserts/lookups are application operations.
SELECT pg_temp.mem(
  '00000000-0000-4000-8000-0000000016d1',
  pg_temp.id('travis'), 'tax', DATE '2020-01-01'
);

-- Shows two county candidates with conflicting time zones.
SELECT pl.place_code, f.value
FROM (
  SELECT * FROM public.premise_places_as_of(
    '00000000-0000-4000-8000-0000000016d1',
    DATE '2026-06-01', 'regulatory')
  UNION ALL
  SELECT * FROM public.premise_places_as_of(
    '00000000-0000-4000-8000-0000000016d1',
    DATE '2026-06-01', 'tax')
) pl
JOIN public.place_facts f ON f.place_id = pl.place_id
WHERE pl.kind_code = 'county'
  AND f.fact_code = 'time_zone'
  AND daterange(f.effective_from, f.effective_to, '[)')
      @> DATE '2026-06-01';

-- Defect: returns a zone instead of refusing the conflict.
SELECT public.premise_time_zone_as_of(
  '00000000-0000-4000-8000-0000000016d1',
  DATE '2026-06-01'
);

-- N2: the battery already creates a ZZ gas profile owned by El Paso.
-- L3 is a ZZ premise. Record its distance outside its owning city.
DO $probe$
BEGIN
  PERFORM pg_temp.mem(
    '00000000-0000-4000-8000-0000000016d3',
    pg_temp.id('elpaso'), 'regulatory',
    DATE '2022-01-01', NULL, 'outside', 2.5
  );
  RAISE NOTICE 'Cross-state outside relation accepted';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'Cross-state outside relation refused: %', SQLERRM;
END
$probe$;

RESET ROLE;
-- Then execute the battery's original ROLLBACK.
```

**Round-one disposition audit**

“Fixed” below means the implementation holds under static analysis and its stated operating assumptions, not that I reran its tests.

| Item | Assessment and attempted break |
|---|---|
| B1 | **Fixed.** Membership/profile inserts pin READ COMMITTED before taking shared locks and reading places (P:641,658–659,794,809–810). Close pins it before its exclusive lock and citation query (P:395–412). The trigger functions are volatile, so their subsequent queries can refresh snapshots. RR/SERIALIZABLE cannot take the old snapshot path. |
| B2 | **Fixed for within relations; overbroad for outside.** `FOR SHARE` conflicts with the premise update; reverse ordering makes the inserting query read the updated premise (P:650–652). State changes inspect all historical memberships, preventing historical relabelling (P:715–727). N2 identifies the relation-sensitive gap. |
| B3 | **Original failures fixed; new blocker N1.** Nonuniform or missing uniformity refuses state fallback (P:980–994); tax-only membership contributes. Conflicting axes are not resolved safely. |
| B4 | **Fixed.** Explicit superuser/BYPASSRLS requirement precedes citation reads (P:389–394), matching `sql/v5.4.2-13-backbilling-caps.sql:875`. FORCE RLS table ownership alone cannot bypass this guard. |
| B5 | **Disposition complete, implementation partial.** Rate fact added (P:201); relation/distance added (P:575–604); A5/A6 residuals explicit (P:1109–1116). Distance representation still has N2. |
| S1 | **Fixed for same-state places.** Explicit outside rows distinguish unknown from known outside; same-place exclusion prevents simultaneous within/outside on one axis (P:602–610). N2 limits coverage. |
| S2 | **Fixed as specified per axis.** City/limited-purpose/ETJ share `municipal_status` (P:153–158); derived group cannot be spoofed (P:661–662); exclusion handles concurrent inserts (P:614). Cross-axis coexistence remains intentional. |
| S3 | **Profile fix holds, integration incomplete.** Owner-kind compatibility and cross-state owning place work (P:801–819). Outside relation to that owner fails: N2. |
| S4 | **Fixed.** Key required exactly for keyed facts; exclusion includes normalized key (P:450–455,480–484). Blank keys cannot bypass it. |
| S5 | **Fixed.** Explicit argument checks plus absent/invisible-state refusal; profile lookup refuses missing arguments/results (P:923–936,1010–1021). No new SECURITY DEFINER lookup bypass. |
| S6 | **Close/state-pointer fixes hold; repoint history remains residual.** New pointer locks/checks place; close counts pointers (P:410–411,887–897). Clearing remains allowed outside RC, safely removing a dependency. Repointing remains mutable and undated under R3; this was not turned into historical identity. |
| S7 | **Fixed.** Both insert paths stamp `created_by` and validate tenant (P:643–647,796–800). Nullable/missing session attribution remains possible for privileged migration writes, consistent with the helper. |
| S8 | **Fixed.** Parent required exactly when applicable, with allowed kind/state/range checks (P:354–368). Missing parent cannot pass the kind check. |
| S9 | **Fixed.** Required evidence dates on memberships/profiles (P:583,755). |
| S10 | **Fixed.** Platform TRUNCATE triggers cover all six tables and are ALWAYS (P:553–556); inherited hard-delete helper raises unconditionally (`sql/tu.sql:13250`). |
| S11 | **Explicit residual R13** (P:1117). Advisory-lock denial of service remains; no integrity bypass found from lock-key collisions. |
| S12 | **Explicit residual R14** (P:1122). Backdated closes still change past answers; no decision rows yet cite these facts. |
| S13 | **Explicit residual R15** (P:1125). Later law predicates must interpret relation/distance, not blindly use the profile boolean for every premise. N2 must be resolved first. |
| S14 | **Fixed for the reported case.** `Factory` fails the syntax check; accepted zones also require server recognition (P:491–493). This is deliberately a lightweight identifier filter, not geographic verification. |

**Inventory coverage**

The inventory is `application/places-source-inventory-2026-10-06.md:49–69`. “Held” denotes the record shape; it does not mean all real-world data or future law enforcement is supplied.

| Requirement | Result |
|---|---|
| P1 State | **Held with residual.** State places and normalized lookup (P:149,930–936); dirty premise writes explicitly deferred by R10. Profile state validation is weaker; see should-fix below. |
| P2 County | **Held.** County kind/axes and county facts (P:151,191,205). |
| P3 Full-purpose city and facts | **Held.** Municipality, population, retained jurisdiction, residential taxability, rate (P:153,195–202). Franchise consumer migration is R4. |
| P4 Limited-purpose area | **Held + residual R6.** Kind exists; unresolved legal treatment remains explicit (P:155,1089). |
| P5 ETJ | **Held.** P:157; regulatory membership only. |
| P6 Utility rate area | **Residual R3.** Existing jurisdictions remain undated; dated utility rate-area foundation is not delivered (P:1077). |
| P7 Tax jurisdictions/rate history | **Held as representation.** Kinds and dated rate fact exist (P:151–162,201,435). Publisher loading/quarter correctness remain migration responsibilities under R2. |
| P8 Time zone | **Miss: N1.** Facts and ordinary lookup exist, but conflicting candidates return an answer. Constant replacement remains R5. |
| P9 Weather | **Held as representation.** County weather-station fact; existing utility WNA configuration retained (P:205,867–878). |
| P10 Boundary relation/distance | **Partial/miss: N2.** Same-state within/outside works; cross-state owner relation cannot be recorded. |
| A1 Owner type | **Held as utility fact; law keys residual R1.** Seven owner types, dated profiles (P:230–239,744). |
| A2 Commission status | **Held as dated profile fact; law keys R1, premise-dependent interpretation R15.** P:750,1125. |
| A3 Size/count | **Residual R7.** Count deferred to reproducible core derivation; not stored here (P:1092). Population fact exists. |
| A4 Local adoption | **Held.** Keyed, dated local-adoption facts (P:207,453–455). |
| A5 Enforcing body | **Residual R11.** P:1109. |
| A6 Customer/meter attributes | **Residual R12.** P:1113. |
| A7 Retail market role | **Explicitly out, R8.** P:1095. |
| D1 Independent effective dates | **Held.** Axis is part of membership keys; battery demonstrates different dates (P:608–617; T:557). |
| D2 Evidence | **Held.** Required kind/reference/date (P:581–583,605). |
| D3 Many simultaneous units/cardinality | **Held per axis, partial overall.** Exclusions permit districts to stack; time-zone uniqueness has N1, rate-area dating is R3. |

The foundation follows convention §9’s direction, but does not yet provide the composite law-selection key. R1 states that honestly. Separate governing-state profiles, ownership, jurisdiction status, and independent annexation dates are suitable foundations once N1/N2 are corrected.

**Should-fix findings**

1. **Profile lookup accepts an unknown governing state.** The profile’s only state constraint is two uppercase letters (P:768); neither insertion nor lookup requires a corresponding state place (P:793–825,1015–1023). Thus `QQ` can produce a successful profile while premise-place lookup refuses it. R10 specifically explains dirty *premise* state, not this successful profile result. Validate governing-state existence/validity or explicitly document and test the weaker contract.

   Using the same battery insertion point and application identity:

   ```sql
   SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000016b1';
   SET LOCAL ROLE tally_app;
   SELECT pg_temp.prof(
     'gas', 'QQ', 'investor_owned', true, NULL, DATE '2020-01-01'
   );
   SELECT * FROM public.utility_service_profile_as_of(
     '00000000-0000-4000-8000-0000000016a1',
     'gas', 'QQ', DATE '2026-06-01'
   );
   RESET ROLE;
   ```

2. **New guard coverage is incomplete.** Removing only the jurisdiction shared-lock call at P:891 has no corresponding concurrent test or mutation. R6 checks isolation rejection, not pointer/close concurrency (R:116–118). Add both orderings of pointer/close and close-first membership/profile cases. Add reverse state-update/membership ordering and simultaneous conflicting memberships/profiles. GiST exclusions look correct, but the supplied race suite does not exercise those conflicts.

3. **Not every guard has an independently discriminating test.** Examples:
   - The profile NULL test supplies only a NULL date (T:512–516); removing any of the other three NULL branches survives.
   - Place-axis tests cover an unknown axis and NULL date, but not a NULL axis (T:573–590).
   - ETJ group mutation is covered, but changing only limited-purpose membership to another exclusivity group is absent from the mutation set (M:105–108).
   - Membership close boundary is tested, but equivalent equality boundaries for profile/fact/child close dependencies are not independently established (T:607–658).
   - N1’s disagreeing-axis case and N2’s cross-state outside case are absent.

4. **Mutation success still needs human interpretation.** M:276 counts an arbitrary `ERROR` before the named PASS as a catch. Printing the first failure helps review; it does not establish that the intended guard caught it. The R1/R2/R7 harness also uses sleeps rather than observed blocking, and accepts the expected rejection without proving concurrency occurred (R:50–74,120–139). A run where the first writer commits before the second starts can pass even with its lock removed. Require explicit synchronization/block observation and validate process exit statuses.

**Notes on integrity and operational limits**

- I found no additional application tenant-leak path through these invoker-rights lookups or `jurisdictions.place_id`. Shared place IDs intentionally carry no tenant. The two new tenant tables use FORCE RLS and composite premise/tenant binding (P:590–625,776–779).
- Required identity/date columns, coalesced kind tests, FKs and exclusion predicates close the obvious NULL-based membership/profile overlap bypasses. No new `pg_trigger_depth()` trust assumption is introduced.
- Concurrent fact/child creation versus place close remains unsafe without the declared single-writer platform discipline. It is explicitly R9 (P:1098–1102), not fixed by the application advisory protocol.
- `jurisdictions.place_id` is still current configuration: it can be repointed, and a currently valid, already finite place can later expire while pointed at (P:887–894). Future historical law resolution must not treat this pointer as dated evidence.
- Numeric fact validation enforces JSON type, not domain: negative population or an implausible sales-tax fraction is accepted (P:488). Distance likewise deserves finite-number validation before laws compare it to mileage thresholds (P:603–604).

The original stale-snapshot, state-edit, hidden-citation and nonuniform-state fallback failures appear addressed. Readiness still depends on resolving **N1 and N2**, with targeted tests that demonstrate refusal or correct representation.