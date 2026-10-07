**Verdict: ready for the stated foundation scope. No blocking SQL integrity finding.** Round 4’s successor race appears fixed. Test attribution and coverage still have nonblocking defects described below.

Both frozen hashes match:

- Patch: `24757cfc95fb3be08e416f8504c0dbc1`
- Battery: `3add58b717852d9d5d4804cc934c3150`

The working patch and battery also match their frozen copies. Review was read-only; no Docker or database tests ran. I executed only the mutation harness’s pure Python helpers: it contains 146 mutations and recognizes 90 battery checks; all mutation anchors resolve.

References: **P** = [frozen patch](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-16/review/patch-16-frozen-r5.sql), **B** = [frozen battery](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-16/review/battery-16-frozen-r5.sql), **R** = [race script](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-16/races/place-close-16.sh), **M** = [mutation harness](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-16/mutations-16.py). Numbers below are file lines.

**Round 4 dispositions**

| Item | Assessment |
|---|---|
| **B1** | **Fixed on static inspection.** P:977–984 selects the covering state row, takes its shared transaction advisory lock, then rechecks containment against exactly that UUID. It cannot substitute an unlocked successor. R19 targets the original failure; R20 targets locking the wrong historical row. |
| **S-own** | **Fixed for the reported modelling defect.** Five ownership categories at P:285–289; three separate system kinds at P:321–326; required profile column/FK at P:911,928; service compatibility at P:995–999. A municipality can own piped propane or a master-meter system without losing its ownership classification. U6 exercises separation and service mismatch. See the ownership terminology note below. |
| **S-tax** | **Fixed in production SQL.** Both area kinds take both axes at P:195–198, retaining `municipal_status` exclusivity. Generic membership and state guards apply unchanged. U7 incompletely tests its advertised result: its limited-purpose insert uses **regulatory**, not tax. |
| **S-key** | **Fixed to the chosen scope.** P:554–556 requires citation syntax, an alphanumeric character, and no space after `§`. Canonical case/spelling and ASCII range hyphens are explicitly R20, P:1387–1391. U8 tests both added restrictions. |
| **T** | **The enumerated fixes are present.** U1 tests negative distance; U2 actually queries duplicate and distinct agreeing places; U3 dates state resolution; U4 isolates the finite-ended governed-profile floor; U5 isolates `no_repeat`; U9 checks the unknown-place message; U10 uses an uncited place. U4/U5 inspect the refusing message. Coverage qualifications remain below. |
| **T-attr** | **Partially fixed.** Earlier incomplete battery checks no longer automatically count as target catches; race output must name the target; clone setup return codes are checked. But “all previous checks passed” still does not establish that execution entered the target. I reproduced false-positive classifications without a database. |

**Integrity assessment**

The state handshake now withstands the round-4 interleavings:

- **Close/successor first:** the inserter initially sees the old covering row, waits, then rechecks that row. If shortened below the profile’s range, it refuses even when a successor now covers the profile.
- **Profile first:** the close waits on the selected state’s shared lock, then its fresh query sees the committed profile and refuses a close before the profile ends (P:489–501).
- **Gap:** no single covering row exists, so P:989 refuses.
- **Reopening the original row:** P:475–479 forbids editing an already closed place. A newly inserted row with the same state code has a different UUID and cannot satisfy the locked-row recheck.
- **Two rows, either UUID order:** selection filters by containment before locking; UUID ordering is irrelevant.
- **Profile spanning adjacent state rows:** refused because neither row contains the whole range. This is explicitly R19, not accidental missing union coverage.
- **Close still covers the profile:** recheck succeeds correctly; an end exactly on the close boundary is allowed by the close floor’s strict `>` comparison.

I found no replacement race introduced by selecting only the covering row. Places cannot change state/kind/identity through ordinary updates, and the state code/place code rule plus exclusion prevents simultaneous covering state rows (P:381–383,442,475–479).

For memberships, the premise row share lock and place advisory lock remain complementary: one protects normalized premise state, the other protects place lifetime (P:812–840). The state-change guard includes **all unvoided memberships**, including tax and closed historical rows (P:880–882). The new tax-axis area memberships therefore do not escape it.

Concurrent membership cardinality and profile overlap remain enforced by GiST exclusions, not vulnerable count-before-insert checks (P:725–735,940–943). R16/R17 exercise the competing writers. Close/void updates cannot extend a citation, change its identity, or resurrect it (P:769–787); omitting insertion-style locks on these shrinking/removing operations does not create an orphaning path.

NULL defenses remain adequate along the changed paths: profile system kind/service/state/start and membership identity/axis/start are NOT NULL; an unknown or NULL system kind fails the service lookup; unknown owner types cannot escape their FK. Optional outside distance remains intentional. The numeric typmod and distance check jointly reject infinities, NaN, zero and negatives (P:685,718–721).

The time-zone lookup does **not** inherit the parent municipality’s zone merely because a premise has an ETJ or limited-purpose membership. Only kinds declared zone-capable participate, and neither area kind is declared zone-capable (P:243,1178–1185). Thus:

- A tax-axis area does not manufacture a city-zone answer.
- An actual county membership can answer.
- Without a finer answer, Texas’s non-uniform state cannot supply a fallback.
- A municipality independently recorded on the other axis can answer by the documented precedence.

Agreeing distinct places collapse to one zone; conflicting or partially loaded peers at the answering level refuse (P:1187–1223). A zoned city outranking a conflicting county level remains the explicit design.

RLS remains canonical and forced on both new tenant tables (P:740–743,946–949). The three lookups have invoker rights. Shared place IDs intentionally reveal shared geography, not another tenant’s memberships, profiles or jurisdiction settings. `jurisdictions.place_id` adds no definer-rights traversal; its trigger validates an open shared place under the same advisory protocol (P:1083–1095).

The patch introduces no SECURITY DEFINER or trigger-depth bypass. Its close-role check follows -13’s pattern (`sql/v5.4.2-13-backbilling-caps.sql:875`); advisory locking follows the draft -15’s approach (`sql/v5.4.2-15-deposits-law-to-core.sql:1090–1117`). P:417–422 consistently refuses non-READ-COMMITTED insertion/close handshake operations with 25000. Historical reads can safely use a consistent older snapshot.

The remaining concurrency assumptions are explicit: platform child/fact writes are serialized operationally, not locked against each other (R9); advisory-lock denial of service is R13; deadlock retry is R18. I found no way around the stated close floors within those assumptions.

**Should-fix findings**

1. **Mutation attribution still accepts infrastructure/setup failures as target catches.**

   M:392–397 discards the subprocess return code. M:420 returns true solely because every earlier check passed—even if there is no error, no target-entry evidence, or only a fixture error between checks.

   Executed reproduction, using only the harness’s definitions:

   ```python
   import runpy
   m = runpy.run_path("tests/v5.4.2-16/mutations-16.py")
   order = m["battery_order"]()

   assert m["caught"]("A1", "") is True
   assert m["caught"]("A1", "psql: error: connection refused") is True

   prior = "\n".join(
       f"NOTICE: PASS {c}: passed"
       for c in order[:order.index("U1")]
   )
   assert m["caught"](
       "U1", prior + "\nERROR: duplicate key during U fixture setup"
   ) is True
   ```

   This matters concretely because U fixtures execute between T12’s PASS and U1 (B:1159–1175). Their failure is currently attributed to U1. Clone-creation checks at M:432–440 do not cover this.

   Require explicit target-entry/location evidence plus an expected failure, or a target FAIL marker; classify connection/setup failures separately. Preserve return codes.

   Similarly, R:74–97 does not check fixture setup success, and `two()` at R:108–124 does not validate A’s exit status. A named `FAIL Rn` can therefore represent failed setup rather than mutation detection. This does not prove the reported 146 catches were false; it limits what that count establishes automatically.

2. **U7 does not test limited-purpose tax membership despite claiming it does.**

   B:1241 inserts ETJ on tax, but B:1242 inserts limited-purpose on **regulatory**. No limited-purpose tax membership is exercised elsewhere in B. M143 changes only ETJ.

   A mutation changing P:195 from:

   ```sql
   ARRAY['regulatory', 'tax']
   ```

   to:

   ```sql
   ARRAY['regulatory']
   ```

   is therefore predicted to survive this battery and the supplied races. Production SQL is correct.

   Add a positive limited-purpose tax case and a city-versus-limited-purpose tax exclusion case. This exact positive probe can run immediately before B’s final ROLLBACK, using its existing fixtures; L19 has only a district membership:

   ```sql
   SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000016b1';
   SET LOCAL ROLE tally_app;

   SELECT pg_temp.mem(
     '00000000-0000-4000-8000-0000000016e8',
     pg_temp.id('austin_lpa'),
     'tax', DATE '2020-01-01'
   );
   ```

   Expected: succeeds on the frozen patch; fails on the mutation above. Also explicitly test tax-area membership against the state-change guard and county/no-county time-zone cases.

3. **The new vocabulary’s protections lack direct regression coverage.**

   P:313 and P:656–665 correctly protect `utility_system_kinds`, but B’s permission, immutability and truncation tests exercise other vocabularies. U6 tests profile behavior, not vocabulary access control.

   Removing only its REVOKE at P:313 would restore application INSERT through the base default grants (`sql/tu.sql:11388–11391`), allowing the application to extend this supposedly platform-held vocabulary. The existing battery does not attempt that insert. Add a valid application INSERT refusal and direct owner UPDATE/DELETE refusals for this table.

   Also add successful historical/current profile inserts against a two-row state and an explicit profile spanning their shared boundary. R20 proves a close race against the current row; it does not establish those successful/read-boundary cases.

Consequently, **I cannot affirm “every guard has a case only it can refuse.”** The listed round-4 integrity fixes have targeted tests, but complete guard coverage is a stronger claim than the suite supports.

**Inventory traceability**

“Holds” means the foundation represents and constrains the fact, not that all source data and downstream rule evaluation are implemented.

| Requirement | Result and evidence |
|---|---|
| **P1 State** | **Holds**, with address-write validation residual R10. State code shape/identity P:378,442; normalized dated lookup P:1128–1134. |
| **P2 County** | **Holds.** County kind P:191; dated zone/weather facts P:243,257; memberships P:678 onward. Loading R2. |
| **P3 Full-purpose city/unit facts** | **Holds foundation.** P:193,247–254. Franchise text migration remains R4. |
| **P4 Limited-purpose area** | **Holds representation**, now on both axes, P:195–196. Gas-rate interpretation explicitly R6. |
| **P5 ETJ** | **Holds.** P:197–198; municipal-status exclusion P:732–735. |
| **P6 Utility rate area** | **Residual R3**, P:1315–1318: tenant jurisdictions retained, optional shared-place pointer; dating deferred. |
| **P7 Tax jurisdictions/rates** | **Holds foundation.** P:191–204,251–255,534–561. Publisher/quarter loading is R2; universal quarter-start enforcement is not imposed. |
| **P8 Time zone** | **Holds lookup**, P:1155–1229. Replacement of existing day-boundary constant remains R5. |
| **P9 Weather reference/WNA** | **Holds reference shape.** County weather fact P:257; tenant WNA retained P:1063–1074. Loading R2. |
| **P10 Relative boundary/distance** | **Holds same-state facts**, P:714–721. Cross-state distance R16; jurisdiction predicates R15. |
| **A1 Owner type** | **Holds surveyed categories**, separating five owners from three system kinds, P:285–326,905–943. Law keys remain R1. Terminology qualification below. |
| **A2 Commission status** | **Holds dated independent fact**, P:912,940–943. Law-key integration R1. |
| **A3 Size/counts** | **Residual R7**, P:1330–1332: thresholds in terms, reproducible counts derived by the core. |
| **A4 Local adoption** | **Holds.** Keyed, dated, cited fact P:259,554–561,586–590. Canonical spelling R20. |
| **A5 Enforcing body** | **Residual R11**, P:1347–1350. |
| **A6 Customer/meter attributes** | **Residual R12**, P:1351–1354. Utility system kind does not replace premise/meter attributes. |
| **A7 Retail role** | **Explicitly out**, R8, P:1333–1335. |
| **D1 Separate effective dates** | **Holds.** Axis participates in each membership exclusion, P:725–735; lookup filters requested axis, P:1141. |
| **D2 Evidence** | **Holds.** Kind/reference/date P:690–692,706–707,722; recording-date guard P:845–848. |
| **D3 Many simultaneous units/cardinality** | **Holds foundation**, P:191–204,725–735; derived zone refuses ambiguity. Rate-area dating/cardinality work remains R3. |

No inventory item is silently omitted. Rule-terms §9’s applicability discriminators are supported as facts; putting them on law/tariff keys is explicitly deferred by P:96–100 and R1. Existing state-only law lookups do not become municipal-safe merely because this patch is installed.

**Notes for the next modelling step**

- Five owner categories plus separate system kinds cover the inventory’s enumerated categories more faithfully than seven “owners.” District distinctions can reside in the owning place’s dated `special_district_type` fact (P:255). Unverified source questions should remain unverified, rather than being inferred from these labels.
- **Ownership versus operation still needs precise terminology before law keys are populated.** P:285 defines municipal as “owned or operated,” while `owning_place_id` and the header describe ownership. The saved research distinguishes ownership-only Louisiana 45:850 (`application/places-sources/utility-type-10-states.md:160`) from Ohio’s owned-or-operated exclusion (:573). A city operator must not automatically be treated as the title owner for every rule. This is a forward modelling qualification, not a demonstrated new round-4 integrity bypass.
- Separate profiles per governing state support a two-state utility, and the owning place may be across the border. Ownership does not require premise membership inside the owning city, so outside-city service works (P:940–952,1013–1025). Cross-state boundary distance remains explicitly deferred.
- `jurisdictions.place_id` remains a utility setting, not a second authoritative premise-membership lookup. Annexation and tax dates belong to memberships; reconciliation/dating of rate areas remains R3.
- The reported live results are useful evidence from the author, but this review independently establishes only the static conclusions and Python attribution failures above.