**Verdict: not yet.** One blocking integrity hole remains in the new governing-state lock protocol. The other round-3 fixes hold on static inspection.

Both frozen hashes match exactly:

- Patch: `a0b43c01bda36c127707100c9726643f`
- Battery: `15eea127cf8d34da55d917325d947659`

The working patch and battery also match these hashes. I made no changes and ran no database tests. Reproduction results below are predictions from the SQL, not claimed executions.

References below use **P** = `tests/v5.4.2-16/review/patch-16-frozen-r4.sql`, **B** = the adjacent `battery-16-frozen-r4.sql`, **R** = `tests/v5.4.2-16/races/place-close-16.sh`, and **M** = `tests/v5.4.2-16/mutations-16.py`.

**Blocking — B1: a profile can validate against a state row it never locked**

P:920–927 selects state IDs for the lock loop, waits on those IDs, then independently searches again for a covering state row. Under READ COMMITTED, that second search can see a newly committed successor absent from the loop’s snapshot.

Interleaving:

1. Platform transaction A closes state row S1 and inserts successor S2, without committing.
2. Application transaction B starts a profile insert. Its loop sees S1, not S2, and waits on S1.
3. A commits. B finishes locking S1; its fresh containment query sees S2 and accepts the profile.
4. Before B commits, a subsequent platform transaction closes S2. B holds no lock on S2, and its uncommitted profile is invisible to the close floor.
5. B commits. The profile now extends beyond every state row. The profile lookup still returns it at P:1174–1182.

This violates P:124–129. It is not covered by R9’s sequential-platform-migration discipline: the two platform transactions run sequentially. Nor does R19 exclude it: S1 had no profiles when succeeded, and B initially fits wholly within S2.

Exact repro, on a fresh throwaway clone with the frozen patch applied; use two psql sessions connected as `tally`.

```sql
-- SESSION A: setup, autocommit
INSERT INTO public.tenants(id, name, slug)
VALUES ('00000000-0000-4000-8000-000000004401',
        'R4 race utility', 'r4-state-successor');

INSERT INTO public.users(id, tenant_id, display_name, email, role)
VALUES ('00000000-0000-4000-8000-000000004402',
        '00000000-0000-4000-8000-000000004401',
        'R4 operator', 'r4-state-successor@example.test', 'operator');

INSERT INTO public.places
  (id, kind_code, state_code, place_code, name,
   effective_from, source_note)
VALUES
  ('00000000-0000-4000-8000-000000004403',
   'state', 'QV', 'QV', 'Fictional QV',
   DATE '1900-01-01', 'R4 race fixture');

-- SESSION A: first platform transaction; leave open
BEGIN;
UPDATE public.places
SET effective_to = DATE '2020-01-01'
WHERE id = '00000000-0000-4000-8000-000000004403';

INSERT INTO public.places
  (id, kind_code, state_code, place_code, name,
   effective_from, source_note)
VALUES
  ('00000000-0000-4000-8000-000000004404',
   'state', 'QV', 'QV', 'Fictional QV successor',
   DATE '2020-01-01', 'R4 successor fixture');
```

```sql
-- SESSION B: run while A remains open; INSERT should block
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL ROLE tally_app;
SET LOCAL app.user_id = '00000000-0000-4000-8000-000000004402';

INSERT INTO public.utility_service_profiles
  (tenant_id, service_type, state_code, owner_type,
   commission_jurisdiction, effective_from,
   evidence_reference, evidence_date)
VALUES
  ('00000000-0000-4000-8000-000000004401',
   'gas', 'QV', 'investor_owned', true, DATE '2021-01-01',
   'R4 profile evidence', DATE '2021-01-01');
```

```sql
-- SESSION A: release B
COMMIT;
```

Wait for B’s INSERT to complete, but **do not commit B**.

```sql
-- SESSION A: second platform transaction, after the first has committed
BEGIN;
SET LOCAL lock_timeout = '2s';
UPDATE public.places
SET effective_to = DATE '2025-01-01'
WHERE id = '00000000-0000-4000-8000-000000004404';
COMMIT;
-- Predicted: succeeds without waiting for B.
```

```sql
-- SESSION B
COMMIT;

BEGIN;
SET LOCAL ROLE tally_app;
SET LOCAL app.user_id = '00000000-0000-4000-8000-000000004402';

SELECT effective_from, effective_to
FROM public.utility_service_profile_as_of(
  '00000000-0000-4000-8000-000000004401',
  'gas', 'QV', DATE '2026-01-01');
-- Predicted: returns the open profile, although QV ended in 2025.
ROLLBACK;
```

Fix by ensuring the row used for containment is actually locked: select a covering ID, lock it, and recheck containment against **that same ID**, refusing or retrying selection if necessary. Alternatively, introduce a stable state-code lock shared by profile writes and state-row lifecycle operations. Add this interleaving to the race harness.

**Round-3 dispositions**

| Item | Assessment |
|---|---|
| **B: finite distance** | **Fixed.** P:635 and 667–671 work together: `numeric(8,3)` refuses either infinity; the CHECK refuses NaN, zero and negative stored values. Negative zero and tiny values rounded to zero fail too. NULL remains intentionally valid for unknown outside distance; within requires NULL. Positive overflow fails the typmod. |
| **S-d′: state floor and lock** | **Partially fixed; B1 blocks.** For an unchanged set of state rows, the exclusive close/shared insert protocol works in both orders. P:453–454 ignores voided profiles and accepts an end exactly on the close boundary. P:920–924 locks all visible state rows in UUID order, including historical rows; P:925–927 requires containment in one. The new-row interleaving above escapes that protocol. |
| **S-tz: answering level** | **Fixed.** P:1107–1127 includes unzoned candidates and refuses an unzoned peer at the answering level. An entirely unzoned level falls through. P:1129 refuses disagreement; DISTINCT aggregation accepts agreement. Outside memberships are removed at P:1114, voids at P:1072, and facts are date-filtered at P:1113. A city deliberately outranks its county. |
| **S-key: citation-form key** | **Whitespace fix holds**, with a format limitation below. P:506’s whitelist rejects tabs, newlines, NBSP, doubled spaces and leading/trailing spaces. The lookahead does not admit a forbidden following character: that character must still match a consuming alternative. |
| **S-err** | **Fixed.** P:370–375 emits `invalid_transaction_state`/25000 for every isolation other than READ COMMITTED. This matches `sql/tu.sql:22113`; the draft -15’s 40001 remains a separate issue. |
| **S-uninc** | **Fixed.** P:339–341 excludes overlapping unincorporated rows by state regardless of code. Separate states and nonoverlapping successive rows remain possible. PostgreSQL’s exclusion constraint also covers concurrent inserts. |
| **T: test gaps** | The listed T6–T12 cases and mutations address the reported gaps, and R16–R18 add the requested exclusion/profile/owning-place races. R:87–88 now identifies B itself. Coverage is materially improved, but is not exhaustive; see below. |

**Should-fix — test coverage and mutation attribution**

1. **Negative distances remain untested.** B:996–1008 covers NaN, zero and `0.001`, but no negative distance. Changing P:671 from `distance_miles > 0` to `distance_miles <> 0` would admit negatives while preserving those outcomes; I predict it survives the present battery. Add `-1`, negative values rounding to zero, both infinities and positive underflow. The production guard currently appears correct.

2. **The “agreeing candidates” test does not assert its advertised result.** B:743–744 adds the duplicate Travis membership to L2, but the subsequent lookups at B:748 and 753 query L12 and L8. Explicitly query L2 afterward. Also test two *different* counties/cities with equal zones on opposite axes, which exercises agreement beyond deduplication of one place.

3. **Mutation counts do not prove the named check caught the change.** M:391 counts any output containing `ERROR` and lacking `PASS <target>` as caught—even if an unrelated earlier error prevented the target from running. Printing the first error at M:387–392 helps manual diagnosis but does not enforce attribution. Require the intended failure marker, or explicitly validate the expected error and location. Database setup return codes at M:369–373 should also be checked.

4. **Add changing-state-row-set coverage.** R13/R14 exercise a fixed state ID; neither tests B1. Also add an ordinary multi-row state fixture to demonstrate successful historical/current profile containment and refusal across a gap or boundary spanning two rows.

I therefore cannot affirm “every guard has a case only it can refuse.” T2a and T3a notably improve attribution by checking the error message (B:1016, 1046); several other cases rely only on a broad SQLSTATE.

**Notes — citation keys and modelling**

- **Citation keys are a restricted syntax, not arbitrary source citations.** P:506 refuses an en dash, for example `§§845–849`, which appears in `application/places-sources/utility-type-10-states.md:25`; the ASCII-hyphen spelling passes. It also accepts `§`, `§§` and `§ ()`, because no alphanumeric is required after the initial section sign. No whitespace-only key appears to pass. This is not a blocking integrity issue for reviewed platform data, but document a canonical key spelling and test it; “real citations pass” at B:1084 overstates two examples. If the intended rule remains “whitelist alnum,” add an explicit alphanumeric requirement.
- Ownership and commission status are correctly separate and dated. The owner’s place need not be in the governing state (P:937–955), supporting a border utility. The profile is independent of premise membership, so a city can own service outside its limits. Same-state outside distance is represented; cross-state distance is explicitly R16.
- The regulatory/tax split correctly permits an annexation window with different memberships and dates. Time-zone disagreement during that window deliberately refuses, rather than silently choosing the regulatory axis.
- Foundation readiness is distinct from applicability integration. Existing state-only law lookups must not be treated as municipal-safe merely because these profiles exist; P:1231–1236 correctly records that remaining work.

**Inventory traceability**

“Holds” below means the foundation can represent and constrain the requirement, not that publisher data or downstream law evaluation is complete.

| Requirement | Result and evidence |
|---|---|
| **P1 State** | **Holds; input-validation residual.** State place shape P:177, 395; normalized known-state resolution P:1059–1065. Raw premise input remains R10, P:1271–1276. |
| **P2 County** | **Holds.** Kind P:179; weather/time-zone facts P:231, 245; memberships P:628 onward. Loading is R2. |
| **P3 City/full-purpose/unit facts** | **Holds foundation.** P:181, 235–242. Franchise text migration remains R4, P:1249–1252. |
| **P4 Limited-purpose area** | **Holds representation; legal treatment residual.** Regulatory-only kind P:183; R6 P:1257–1259. |
| **P5 ETJ** | **Holds.** P:185 and municipal-status exclusion P:682–685. |
| **P6 Utility rate area** | **Residual.** R3 P:1245–1248: existing undated tenant jurisdictions, with optional place pointer. |
| **P7 Tax jurisdictions/rate history** | **Holds foundation; loading residual.** Kinds P:179–192, dated rate/type/taxability facts P:239–244. Quarter-start publisher dates are loaded under R2, not enforced by a universal calendar CHECK. |
| **P8 Time zone** | **Holds lookup; integration residual.** P:1086–1159; replacing the existing day-boundary constant is R5. |
| **P9 Weather reference/WNA** | **Holds reference shape.** County fact P:245–246; tenant WNA settings retained P:994–1005. Source data is R2. |
| **P10 Relative boundary/distance** | **Holds same-state representation.** P:634–671. No membership means unknown. Cross-state measure is R16; rule predicates R15. |
| **A1 Owner type** | **Holds dated fact; law-key residual.** Seven types P:270–279; profiles P:852–897. R1 defers law-table keys. |
| **A2 Commission status** | **Holds dated independent fact; law-key residual.** P:858, 885–897; R1. State lifetime enforcement has B1. |
| **A3 Size thresholds/counts** | **Residual.** R7 P:1260–1262: terms thresholds and reproducible core-derived counts. |
| **A4 Local adoption** | **Holds.** Keyed dated fact P:247–248, 509–511; key-format note above. |
| **A5 Enforcing body** | **Residual.** R11 P:1277–1280 assigns it to each rule set. |
| **A6 Customer/meter attributes** | **Residual.** R12 P:1281–1284. |
| **A7 Retail role** | **Explicitly out.** R8 P:1263–1265. |
| **D1 Independent dates per axis** | **Holds.** P:633, 638–639, 675–685; B:323–346, 558–574. |
| **D2 Membership evidence** | **Holds required shape/date.** P:640–642, 672, 792–795. Content truth remains a loader/operator responsibility. |
| **D3 Many simultaneous units/cardinality** | **Holds implemented kinds.** P:675–685; time zone resolved separately. Rate-area dating/cardinality remains P6/R3. |

No inventory requirement is silently omitted: remaining implementation is explicitly residual, though the patch is not the completed §9 applicability selector.

**Other integrity checks**

- The changed paths add no SECURITY DEFINER function or trigger-depth bypass. Lookups remain invoker-rights functions. Membership/profile RLS is forced with the canonical policy (P:690–694, 891–895); base premise and jurisdiction policies are at `sql/tu.sql:11272` and `11595`.
- Shared places and facts intentionally expose platform reference data, not tenant memberships. `jurisdictions.place_id` points to shared identity; it does not grant access to another tenant’s jurisdiction. Its lock/re-read path uses a fixed ID (P:1017–1023), so it does not share B1.
- Required-column NULLs are backed by NOT NULL/FKs. Copied membership kind/group cannot be supplied to evade exclusivity. Insert stamping removes forged void/close flags. Close/void updates only shrink or remove citations, so they do not need the insert-side handshake to prevent an orphan.
- Membership races on a fixed place ID and profile races on a fixed owning-place ID retain the correct shared-lock/re-read ordering. GiST exclusions enforce competing memberships/profiles independently of snapshot visibility. The new governing-state search is the exception.
- Facts and children are counted by the close floor (P:456–460), but their insert-side concurrency still depends on explicitly stated R9. The superuser/BYPASSRLS close requirement at P:436–440 matches the -13 house pattern (`sql/v5.4.2-13-backbilling-caps.sql:875`).
- Advisory-lock denial of service and deadlock retries remain declared operational residuals R13/R18. Neither explains away B1.

**Blocking item to resolve: B1, with the successor-state race added to the tests.**