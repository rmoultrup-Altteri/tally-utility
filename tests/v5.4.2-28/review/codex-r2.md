# Codex — v5.4.2-28, review round 2

Verdict: **ready** (source review; database predictions await the author's probes).

**Executed — provenance and scope.** Read the brief, then checked all five hashes before reviewing patch content. All matched:

| Frozen file | MD5 |
| --- | --- |
| patch-28-frozen-r2.sql | a18f1b8f2ab5ef829c04da86ae1339a2 |
| battery-28-frozen-r2.sql | ddded1e07268235d894294b8f17451fe |
| mutations-28-frozen-r2.sh | 50dd0d51ab25c12d046e84767bc52ec5 |
| past-cycle-28-frozen-r2.sh | 32fab0fdb74cc41040472f2773142d48 |
| older-tests-28-frozen-r2.diff | c82a09a7c0ba511a9721d74cb4140077 |

Reviewed those sources, the r1/r2 patch diff, my own r1 review, the r2 plan, the relevant DECISION-LOG entries, AC-45, parity rows CI-010/101/109, Kyle K-06 and November 3 Q2, PATCH-LESSONS index/relevant sections, and targeted schema definitions. Did not read Opus's or Fable's r2 reviews. Did not run Docker, psql, CI, races, mutation runner, or any database probe. The author's reported 99 passes, 23 mutation catches, strict applications and dump/restore results are not my measurements.

## Blocking items

**Executed — source assessment:** none identified within the settled scope. My prior B1/B3 are addressed in code; prior B2 is explicitly allocated to the money stream by Ryan's ruling, not silently treated as repaired here.

## Should-fix items

### S1 — Executed: the new race does not establish its decisive ordering

`past-cycle-28-frozen-r2.sh`, P1: session 1 sleeps 2.5 seconds, while the shell sleeps 0.8 seconds before starting session 2. The final assertion establishes `START < CLOSED`. It never establishes **session 2's COMMIT completed before session 1 attempted the reverse insert**.

An unintended schedule is: session 1 begins, session 2 is delayed, session 1 wakes and attempts its insert, then session 2 closes the original edge. The timestamp condition can still pass. In that order P1 exercises an ordinary cycle against an open edge, not the newly fixed historical-edge predicate. P2 checks the resulting absence of a cycle and does not distinguish these orders either. This is a source-level test-design finding, not an executed PostgreSQL race result.

Add a handshake releasing session 1 only after session 2's successful commit; bound its wait and verify both sessions reached the intended stages. If using `pg_stat_activity`, follow PATCH-LESSONS and clear its cached snapshot in polling loops. Preserve the old-predicate negative control. Also describe P2 as checking **41 sampled instants at 100 ms spacing**, not every instant from session 1's start onward.

This is nonblocking here: the predicate itself has a sound interval rationale, and the brief reports an author-executed negative control on r1. It weakens future repeatable regression evidence. [Probe 02](codex-r2-probes/02-temporal-predicate.sql) checks the interval boundaries and prints the guard definition; it deliberately does not pretend to reproduce scheduling or repair the race.

### S2 — Executed: add owner-visible cross-tenant child fixtures and mutate both filters

The brief explicitly asks whether to add the omitted parent-branch tenant-filter mutation: **yes**. Both the count/nesting scan and the zone scan contain `c.tenant_id = v_inv.tenant_id`. A tally_app-only fixture can conceal removal through RLS, and a single same-tenant family cannot distinguish either mutation.

Add a real foreign-tenant child pointing at a same-tenant parent, with its own valid customer/premise. As owner, check that a foreign child in the other zone does not contaminate the zone aggregate; separately make it consolidated and check that it does not contaminate the nested-child scan. Mutate each filter independently. [Probe 01](codex-r2-probes/01-regression-and-boundaries.sql), C2/C3, supplies those fixtures and predictions without disabling guards. If an existing guard rejects fixture creation, that is a setup result to investigate, not proof that the filter mutation was caught.

This is missing defense-in-depth coverage, not a discovered missing filter: both filters remain in r2.

## Notes and required answers

### N1 — Predicted: each round-2 fix closes the intended finding

Database support: [Probe 01](codex-r2-probes/01-regression-and-boundaries.sql), a copy of the frozen battery with caught-error NOTICE diagnostics, a timeout, and additional boundary cases; [Probe 02](codex-r2-probes/02-temporal-predicate.sql) for the temporal predicate.

| Plan item | Source assessment and pending probe |
| --- | --- |
| B1 dump/reparse | The tier expression now uses remainder instead of a method on a parenthesized expression. R6 feeds catalog CHECK definitions back into ALTER TABLE; R6b checks the expected rendering. Predicted to close the specific r1 parser failure. See N4 for the scope of this evidence. |
| B2 NULL close reason | The closing branch explicitly requires `closed_reason IS NOT NULL`. D7a–D7a8 require the close-consistency constraint and cover omitted/explicit NULL and non-alphanumeric text for both close types. Predicted fixed. |
| B3 parent premise/nesting | Branch selection now uses the NOT NULL `is_consolidated` flag, not premise presence. Nesting tests the child's flag independently of its premise. Z5h2, Z5m–p and Z6j exercise the changed paths. Predicted fixed. |
| B4 post-issue family changes | No enforcement change; L6 and the money-stream allocation match the November 2 decision. This closes the rates-side disposition, not the underlying invoice invariant. |
| S1 historical cycles | The walk includes closed edges with an upper transaction-time endpoint after NEW's start. Probe 02 covers the strict boundary; D7d/D8c cover same-transaction closes. Actual concurrency remains unexecuted by me; S1 above addresses the harness. |
| S2 NaN | Both scalar checks and the override explicitly reject NaN. R1e/R5c/R3c target the named constraints. |
| S3 tier shapes | Comment narrows the precision claim to rates at the documented path. This is the agreed documentation-only resolution, not stronger shape enforcement. |
| S4 tests | D7c now observes the backdated header immediately after the close and before inserting its successor. Runner mismatches now set `fail`; N21 targets the close UPDATE. Additional N12–N15 cover the named omissions. |
| Percentage rates | The split changes the refusal name for `decimal`, without granting it additional precision. R5a–d and C7–C9 cover the intended boundaries. AC-45's conversion/display policy remains application work. |
| Zone data ruling | L1 reflects the separate shared county-data patch, -29. No unnecessary two-midnight shortcut was introduced. |

**Executed — source comparison:** the operative r1/r2 changes stay within that list. No additional policy expansion or new regression was identified. This is not a claim that all database regressions were executed.

### N2 — Predicted: zone union and branch behavior are correct for a stable family

`UNION ALL` retains every relevant premise lookup; the outer `array_agg(DISTINCT z.zone)` deduplicates answers, not premises before evaluation. The existing helper either returns a non-NULL zone or raises. Therefore a parent with an unanswerable own premise must raise even when every live child agrees: C1 adds this missing case. Zero live children are rejected before considering the parent's own premise. Z5o covers agreement; Z5n covers own-premise disagreement; Z5h2 covers nesting with a premise. NOT NULL invoice numbers make the nesting `string_agg` a usable presence indicator.

The same helper remains invoker-rights, and the explicit child tenant filters cover the owner-visible case (C2/C3). C5 calls it as tally_core; Z6 exercises application fee writes. This does not solve changes to family membership after checking: L6 remains the explicit boundary. No new all-isolation parent-family stability guarantee is claimed.

Minor **executed** test-label issue: Z6j says the parent is at Austin, but `inv(70, ...28d1, ..., true)` places it in El Paso. Its mixed children still exercise the intended refusal; correct the label or use the Austin premise to match the prose.

### N3 — Predicted: temporal predicate and write paths

Probe support: 02's interval cases and guard/trigger catalog output; 01's D cases and C10–C12.

A new edge remains open with interval `[NEW.recorded_at, infinity)`. Any existing edge that could coexist with it must have no upper endpoint or an upper endpoint strictly greater than NEW's lower endpoint. That is the new predicate. Equality must exclude an edge closed in the same transaction; otherwise close-then-successor would traverse the predecessor unnecessarily. A close from a later-started transaction committed before NEW's insert must remain included if its endpoint exceeds NEW's start.

Do **not** add `d.recorded_at <= NEW.recorded_at`: an edge first recorded after NEW's start can still overlap the new open edge later. Accordingly the comment saying all counted rows were “known at this row's recorded_at” is slightly too narrow. The implementation tests potential transaction-time overlap with the new open interval. As with the valid-date walk, retained edges need not all share one common instant; the walk is conservative across transaction time too.

The row-version UPDATE of the schedule header remains before traversal, on both insertion and close. Source reasoning predicts a Read Committed writer sees the committed predecessor after waiting; a Repeatable Read/Serializable writer with an older snapshot encounters a changed header version and must retry. Read Uncommitted supplies no weaker PostgreSQL snapshot semantics. These are unexecuted isolation predictions, not certification of an all-isolation race suite. Probe 02 expressly distinguishes interval logic from that missing execution evidence.

The shared row guard runs first, stamps the start, prevents in-place content/key changes, and refuses DELETE, including the owner path (D9e). Immediate CHECKs cannot be deferred by SET CONSTRAINTS. D7g flushes successor enforcement. C10 supplies a multi-row cycle and C11 a chained writable-CTE cycle; both are predicted refusals, and their execution is particularly useful before promoting this review into runtime evidence. A close/insert statement with an order that checks the insert first can refuse conservatively; no statement-order independence is promised.

Roles: Z6/D/R exercise tally_app; C4/C5 call the readers as tally_core and C6 tests its denied write; D9e covers owner DML retention; C12 adds a genuine foreign-tenant item reference. A superuser deliberately disabling/dropping constraints is not an enforcement guarantee any ordinary schema guard can provide. The probe's replica-mode header backdate is an explicit existing battery fixture technique, not an application bypass.

### N4 — Executed: R6 tests CHECK reparsing, not a complete restore

R6 obtains `pg_get_constraintdef` and adds that definition to an empty LIKE copy. That is a useful reproduction of the specific deparsed JSONPath problem that broke r1. Its filter is explicitly `contype = 'c'`: it does **not** cover exclusion constraints, indexes, foreign keys, function bodies, ACLs, restore ordering or data loading. It also runs in the battery's search path rather than reconstructing the whole dump session.

The new exclusion and indexes use ordinary range/column expressions; source inspection found no analogous risky JSONPath method there. Nevertheless “a dump can be restored” in the battery header exceeds what R6 alone proves. Keep R6's printed CHECK-only claim and retain the separately reported real dump/restore as the independent wider verification. I have not reproduced that result. Probe 01 reproduces R6, not pg_dump or pg_restore.

### N5 — Predicted: the rate-check split has no NULL-unit precision gap

`IS [NOT] DISTINCT FROM 'decimal'` is two-valued, including for a NULL unit. A NULL unit reaches the general precision rule; `decimal` reaches the fraction rule; other units reach the general rule. Both precision expressions are the same, including NaN rejection. R1b already uses an omitted/NULL unit; C7 makes it explicit. R5 checks percent and fraction forms.

Versions have non-NULL recorded timestamps and the shared immutable assertion guard: C8 tests an in-place unit change. Changing units through a successor still writes a row subject to the same checks. Overrides have a unit-independent precision CHECK, so a local unit override or an inherited unit cannot choose a more permissive branch; C9 tests `rate_unit_override = 'decimal'` with five decimals. It returns the override constraint name, not the fraction-specific version name; this is consistent with retaining a single storage-precision rule and leaving percentage conversion to AC-45.

Do not claim the schema mandates `percent` for all percentage calculations: R5d intentionally admits a four-decimal fraction, and AC-45 says retiring `decimal` is later work. Likewise the tier-shape comment assigns responsibility without repairing the existing permissive shape check. Neither is a new precision exemption in r2.

### N6 — Executed: mutation/source-test assessment

The runner now fails a wrong named check, with an explicit optional alternate/reason mechanism and no current alternates. Each new mutation targets its stated code fragment. N15 removes the patch-tail invariant call as well as renaming the trigger so the battery, rather than failed patch application, must detect the altered trigger set. N21 now has a discriminating close-only D7c observation. N23 targets the exact old JSONPath form and R6 reparses it. No wrong-reason catch was identified from source; no mutation was executed by me.

N7 removes the close-time filter entirely and tests over-counting; it does not prove the historical-edge fix. The runner acknowledges this and assigns that proof to the race. N2 mutates only the child-count scan's void filter; Z5g covers that mutation, but it is not mutation coverage of the zone scan's separate void filter. The older-tests diff changes two labels and adds the race CI line; it introduces no additional schema change.

### N7 — Executed: known limits L1–L6 do not independently block this scoped patch

- L1: expressly retained by November 4's decision; -29 supplies shared county data. Probe 01's Z5i/Z6d/Z6e cover refusal and the zero-line exception, not all 254 counties.
- L2: conservative cycle detection is approved. D6 exercises valid-date over-refusal; N3 explains the transaction-time conservatism too.
- L3: the single-transaction battery cannot establish separate commit histories. The author owns concurrency execution; S1 should strengthen its ordering evidence.
- L4: bill-line rates, gas commodity rates, deposit interest and retired history remain outside these entry checks. No complete-platform precision claim is made.
- L5: earliest recorded state-agency history is intentionally retained, not a new live-row fallback. The scope decision stands.
- L6: money-stream ownership is explicit. The existing family-stability gap is not represented as fixed or retested here.

## Probe handoff

**Executed — files authored and inspected only. Predicted — every database outcome.**

1. `codex-r2-probes/01-regression-and-boundaries.sql`: frozen battery with caught-error SQLSTATE/message NOTICEs, plus unknown parent zone, owner-visible foreign children, core calls/write denial, explicit NULL rate unit, frozen unit, decimal override, multi-row/CTE cycles and foreign dependency endpoint.
2. `codex-r2-probes/02-temporal-predicate.sql`: synthetic interval-boundary assertions and catalog evidence. Not a concurrency simulation.

Each runs as owner on its own fresh tally clone with frozen r2 applied, uses only transaction-local fixtures, and ends in ROLLBACK. Revoke TEMP on the clone from PUBLIC/tally_app/tally_core beforehand as the brief requires. No role creation/alteration is needed. Probe 01 uses ordinary SET ROLE for app/core paths. All caught errors print SQLSTATE and message with RAISE NOTICE; unexpected setup failures invalidate dependent results. Do not report these files as executed until the author supplies their output.

## Author's run of the probes (2026-11-04)

Each probe ran as the owner on its own fresh clone of `tally` with frozen r2 strict-applied, TEMP revoked; output in `codex-r2-probes/OUTPUT-r2.txt`.

- **01:** the first run stopped at the C2 fixture: the foreign tenant's premise membership was stamped with tenant 1's `app.user_id` (`created_by must name a user of tenant ...28a2`). A setup error, not a finding. Rerun from a copy with `app.user_id` set to tenant 2's user for that insert and back to tenant 1's before C2 (the probe file is unchanged). Result: the frozen battery's checks all pass ("battery-28: all checks passed"), and C1–C13 all PASS as predicted: the parent's own unknown zone refuses (C1); the owner ignores a foreign-tenant child, both live (C2) and consolidated (C3); the core reads and cannot write (C4–C6); NULL unit, frozen unit and fraction-unit override all meet the precision check (C7–C9); multi-row and writable-CTE cycles are refused (C10, C11); a foreign item is refused (C12); the earliest-history fallback holds (C13).
- **02:** every interval case as predicted (open before, closed after start: retained; closed at the same instant or before: not; asserted after start: retained).
