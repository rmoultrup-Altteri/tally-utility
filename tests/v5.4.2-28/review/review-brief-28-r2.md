# Review brief: v5.4.2-28 r2 — rates small fixes (the state-agency time zone, dated rider dependencies, four-decimal rates)

**Date:** 2026-11-04. **Kind:** patch review, round 2.
**Reviewers:** Opus, Fable and Codex, independently. You may read your own round-1 file and the round-2 plan; do not read the other reviewers' round-2 files.
**Stream:** rates (`~/code/tally-utility-rates`). Read the repo at that path. The other stream's clone (`~/code/tally-utility`) may be at a different commit.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-28/review/patch-28-frozen-r2.sql` | `a18f1b8f2ab5ef829c04da86ae1339a2` |
| `tests/v5.4.2-28/review/battery-28-frozen-r2.sql` | `ddded1e07268235d894294b8f17451fe` |
| `tests/v5.4.2-28/review/mutations-28-frozen-r2.sh` | `50dd0d51ab25c12d046e84767bc52ec5` |
| `tests/v5.4.2-28/review/past-cycle-28-frozen-r2.sh` | `32fab0fdb74cc41040472f2773142d48` |
| `tests/v5.4.2-28/review/older-tests-28-frozen-r2.diff` | `c82a09a7c0ba511a9721d74cb4140077` |

The live copies (`sql/v5.4.2-28-rates-small-fixes.sql`, `tests/v5.4.2-28/`) are identical to these today. `older-tests-28-frozen-r2.diff` is round 2's change to earlier tests: two renamed labels in battery -21 and the new race's line in `tests/ci.sh`. To see everything round 2 changed in the patch, diff `patch-28-frozen-r1.sql` against `patch-28-frozen-r2.sql`.

## What round 2 changes

The fix list is `application/rates-build-2026-11-02/v5.4.2-28-r2-plan.md`. It summarises the three round-1 reviews. Each item and what was done:

- **B1, a dump could not be restored (Opus B1).** The tier check is now `@ * 10000 % 1 != 0`, which reparses from its printed form. New battery case R6 feeds every CHECK on the four tables -28 touches back through `ALTER TABLE ... ADD CONSTRAINT` on a scratch copy. R6b checks the stored form. Mutation N23 puts the old form back and is caught at R6. Executed by the author: `pg_dump -Fc` of a patched clone, then `pg_restore` into a fresh database, gave 0 errors and identical counts (137 tables, 1365 constraints, 555 functions, 474 triggers). New lesson in PATCH-LESSONS: `jsonpath-check-must-reparse`.
- **B2, a close with no reason (Codex B1).** `closed_reason IS NOT NULL AND closed_reason ~ '[[:alnum:]]'`. Battery D7a2–D7a8 covers a left-out column, a NULL, a blank, a tab and punctuation, for both a supersession and a retraction. Mutation N18. New lesson: `check-passes-null`.
- **B3, a consolidated parent with its own premise (Codex B3, Fable N4, Opus N2).** `invoice_time_zone_as_of` now branches on `is_consolidated`. A consolidated parent always reads its live children. If it names a premise of its own, that premise's zone must agree with theirs too. A child that is itself consolidated is refused, whatever its premise. Battery Z5h2, Z5m–Z5p and Z6j. Mutations N14, N16, N17.
- **B4, a summary bill changed after issue.** Ryan settled it on 2026-11-02 (option 1): the rule belongs to the money stream. It is listed as known limit L6, with no code change.
- **S1, a long transaction could record a cycle in the past (Opus S1).** The walk counts a row that is open, or that was closed after the new row's `recorded_at`: `(d.recorded_until IS NULL OR d.recorded_until > NEW.recorded_at)`. New race `tests/v5.4.2-28/races/past-cycle-28.sh` (two committed sessions; it checks that session 1 started before session 2's close). Executed by the author: it passes on round 2, and on round 1 it fails P1 and P2 (ten instants hold the cycle). The mutation runner cannot reach this rule, because it needs two sessions. Mutation N7 (every closed row counted) is caught at D7d.
- **S2, NaN (Fable S2).** `<> 'NaN'` on the rate and the override. Battery R1e, R3c, R5c. Mutations N19, N20.
- **S3, tier shapes.** Comment only: the check covers `$.tiers[*].rate`, and tier shape is the tier-shape check's job.
- **S4, the tests.** D7c now looks at the header right after the close, before the successor's insert bumps it (back-dated just before the close). Mutation N21 removes the close's header bump and is caught at D7c. The runner now fails on a catch at the wrong check unless that mutation declares an accepted alternate with a reason (none do). New mutations: N12 (override check), N13 (`changed_by` stamp), N14 (nested-parent refusal), N15 (trigger renamed to sort before the row guard; the patch-tail invariant call is removed in the mutant, so battery D11 must catch it). In battery -21, K3b and K-del are relabelled to say what they prove. Battery -28's D3c says it proves the grant only.
- **Percentage rates (Ryan 2026-11-02; AC-45).** A rate in the fraction unit (`rate_unit = 'decimal'`) is checked under its own name, `rate_item_versions_fraction_rate_store_as_percent_check`, so the refusal says to store percentages in percent. The general check skips that unit, so the two never both apply to a row. Battery R5a–R5d. Mutation N22.
- **Ryan 2026-11-04 (DECISION-LOG): the zone read stays as built (option 1).** All 254 Texas counties will be loaded once with their zones as shared place data, in a separate patch (-29). L1 is restated; no code change.

Not changed: Opus N7 also asked for a mutation on the parent branch's tenant filter. The battery has no cross-tenant child fixture, so the filter is not mutated. Say whether you think it should be.

## The rulings behind it

- `application/DECISION-LOG.md`: the 2026-11-02 (-28) entries and the 2026-11-04 entry (the zone read).
- Kyle K-06: `/Users/ryanscomputer/code/gas-billing-memory/application/kyle-decisions-2026-10-15-waves-1-to-7-and-texas-first.md`. Kyle's 2026-11-03 batch (`kyle-decisions-2026-11-03-scenario-batch-1.md`, Q2) confirms the state-agency exemption and the fee only when a city passes it on. That changes nothing here.
- APPLICATION-CONTRACTS AC-45 (percentage rates).
- Read the index of `sql/PATCH-LESSONS.md` and the sections it points to for what you check.

## Known limits (in the patch header)

- **L1.** Until -29 loads the counties, a non-zero fee outside El Paso and Hudspeth is refused.
- **L2.** The cycle check is conservative across dates.
- **L3.** The battery reads transaction time only at `now()`. The long-transaction case is the race's.
- **L4.** Not covered by the four-decimal check: bill-line rates, deposit interest, `rate_item_history`.
- **L5.** -07's earliest-value fallback in `customer_is_state_agency_as_of` is kept.
- **L6.** A summary bill's members can change after it is issued. This is the money stream's rule (Ryan, option 1).

## Drafting calls to check in particular

- **The zone union.** Is `array_agg(DISTINCT ...)` over children UNION ALL the parent's own premise right? Does a parent whose own premise has no answerable zone refuse even when its children agree? (It should: `premise_time_zone_as_of` raises.)
- **The walk's new predicate.** Does `recorded_until > NEW.recorded_at` ever keep out a row it should count, or count one it shouldn't? Consider a close-then-successor in one transaction, a row closed by a transaction that started after NEW's and committed before NEW's insert, and REPEATABLE READ.
- **The two rate checks.** Is the split by `rate_unit` airtight: a NULL unit, a unit changed in place (are versions frozen?), the override (whose unit can come from `rate_unit_override`, which is not split)?
- **The reparse test.** Does R6 really reparse what `pg_dump` writes? Does it cover the exclusion constraint and the indexes, or only CHECKs, and does that matter?

## Results so far (reproduce them)

- **Strict apply, twice:** clean.
- **`battery-28.sql`:** 99 PASS on `tally` + -28.
- **`mutations-28.sh`:** 23 of 23 caught, each at its named check.
- **`past-cycle-28.sh`:** passes on round 2 and fails on round 1 (executed by the author).
- **Dump and restore:** 0 errors, identical counts.
- **`tests/ci.sh`:** every step passes (52) except battery -15 case V23, the money stream's fixed date that has passed, unchanged from round 1 (a board note). The new race runs in CI as `races v5.4.2-28`.

## What to answer

1. **Does each round-2 fix close its finding,** with nothing the ruling didn't ask for?
2. **Is there a path around any rule?** Consider every role (`tally_app`, `tally_core`, the owner), every isolation level and every statement shape.
3. **Did round 2 break anything** that round 1 had right?
4. **The tests.** Is any claim narrower than its check, or any mutation caught for the wrong reason?
5. **Known limits L1–L6.** Does any of them block?

## How to probe

**Opus and Fable** may query the running `tally-pg` read-only. For experiments, clone into your own scratch database (Opus `rv28opus`, Fable `rv28fable`):
1. `CREATE DATABASE <name> TEMPLATE tally`.
2. Right after creating it, revoke TEMP on the clone from PUBLIC, `tally_app` and `tally_core`.
3. `docker cp` the frozen patch into the container and apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim must be a probe file in `tests/v5.4.2-28/review/codex-r2-probes/`. Each probe runs as the owner on a fresh clone of `tally` with frozen r2 applied, ends in ROLLBACK, and prints the SQLSTATE and message of each caught error with RAISE NOTICE. Keep each probe to what runs in minutes.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role.
- Do not run `mutations-28.sh`; it uses the fixed name `m28`.
- Run the race scripts only against your own clone; they commit rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.
- Other sessions share this container: do not run `tests/ci.sh`, and keep to your own clone.

## Output

Write your full review to `tests/v5.4.2-28/review/<reviewer>-r2.md` (`opus`, `fable` or `codex`). It should contain:
- a verdict: "ready" or "not yet";
- blocking items (B1…), each with the concrete path or repro;
- should-fix items (S1…);
- notes (N1…).

Mark each claim as **executed** or **predicted**. Your final message gives the verdict, the blocking items in one line each, and the file path, in several messages, each under 3 KB.
