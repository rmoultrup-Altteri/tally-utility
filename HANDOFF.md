# Handoff: -23 cash r5 reviewed "not yet" by all three; the r6 fix list is written, r6 not started

**Generated**: 2026-10-28, 12:35 CDT
**Branch**: `main` in both repos, pushed. tally-utility is at the wrap-up commit; GBM is unchanged at `8003ec9` (it has an untracked `Clippings/` folder that isn't ours; leave it).
**Status**: In progress. Ryan has been asked "shall I start round 6?" and has not answered yet. Ask him first.

## Goal

Reach the C# core build. Ryan's gate, in order:
1. schema parity with CI-001…CI-135 (**we are here**: 78 of 135, re-graded only after a mirror);
2. scenarios and a test strategy;
3. a phase plan;
4. build.

-23 (cash) is the blocker in wave 2. -25 (disputes) and -26 (collections) are drafted and wait for it. Mirror order: -23, then -25, then -26.

## Completed (this session, 2026-10-28)

- [x] **-23 r5, tests first** (`e73626c`): the W section of `tests/v5.4.2-23/battery-23.sql`. The failing ones fail against r4: `tests/v5.4.2-23/red-r5-against-r4.txt`.
- [x] **-23 r5, built** (`4f62ae1`, `67b51e9`), all in `sql/v5.4.2-23-cash-reversals-positions-application.sql`:
  - `cash_drawn_at` and `overpayment_split` (the take-back split);
  - the cap on the payment and its credit together, in `check_cash_source`; a credit draw takes the payment's lock first;
  - the refund-tree guard, the escheated give-back guard, the arrival READ COMMITTED pin and the future status-time checks;
  - the reissue's remainder rule and its date rule;
  - the bounce's redundant credit lock removed, and N145 retired.
- [x] **Frozen** (`83317c0`): brief `tests/v5.4.2-23/review/review-brief-23-r5.md`. Battery 293, races 33 (CR1–CR22), mutations 190/190, CI 49/49.
- [x] **Reviewed:** Codex (`dd565e3`; probes run by me, all reproduce), Opus (`4dd597a`), Fable (`0dbf502`). All three "not yet". All agree K-10's money is safe and the B2 refinement is right.
- [x] **The r6 list is merged:** `application/wave2-build-2026-10-15/v5.4.2-23-r6-plan.md`.
- [x] **Records:** the DECISION-LOG 2026-10-28 entry, the design doc's corrections (r4, r5), the r5 plan's "As built", and the roadmap summary plus the dashboard `phases` dataset (dates unchanged: likely ready 2027-06-16).
- [x] **Docker memory leak fixed** (Ryan approved). Claude Desktop's postgres MCP left one container per launch: 69 of them, about 6.4 GB, and tally-pg was OOM-killed in CI.
  - I killed 62 orphans.
  - The wrapper `~/.local/bin/postgres-mcp-docker` labels its containers, removes ones whose launcher is gone, and stops its own on SIGTERM or end of input.
  - The Desktop config points at it; the backup is `claude_desktop_config.json.bak-2026-10-28`.
  - It takes effect when Ryan restarts Desktop. 7 untagged containers remain until then, removable with `docker ps -q --filter ancestor=crystaldba/postgres-mcp | xargs docker rm -f`.

## Not Yet Done

- [ ] **Ask Ryan whether to start -23 r6.** If yes, follow `v5.4.2-23-r6-plan.md`:
  - **B1:** check_cash_source's three recorded-order legs, applied to rows under a payment's posting entry (40001 or 23514). Add a race.
  - **B2:** decide the shortfall's side when a position is read: if one side is negative and the other positive, the positive side covers it. The caps already admit exactly this. The escheat check, the reissue's remainder and the commit check read the covered credit. Write a "remaining = what the cap admits" helper over every W pair.
  - **B3:** in one instant, order a row before the rows under it (depth, then id).
  - **B4:** `status_recorded_at` changes only with its status, for every role; a chosen one is not before rows already on the source.
  - **B5:** a reissue descended from an overpayment credit stays in its payment's lineage: payment lock, the cap on the two together, it holds up the bounce, and its unspent money goes with the payment.
  - **S1:** a leaving refund of an overpayment credit takes the payment's lock first (the deadlock).
  - **S2:** an escheated give-back is refused only as far as the credit would read positive.
  - **S3:** no future `created_at` for a superuser on payments, credits, applications and escheat events.
  - **S4:** tests and mutations. **S5:** comments (R17's last sentence).
  - Time `overpayment_split` on a realistic tree.
- [ ] **Then:** freeze r6 and launch the three reviewers as in r5 (commands below), then merge.
- [ ] **Review -25 and -26** after -23 settles.
- [ ] **Tell Kyle (not blocking):** ui-concepts still lists `refunded`; `do_not_disconnect` must become a protective enrollment; the four wave-3 law findings.
- [ ] **Carried over:**
  - the reply to Kyle on D-2's location;
  - the -05 FK defect;
  - -21 R9;
  - the R-03 scoping;
  - `deferred_balance_after`;
  - the backbilling tariff table;
  - the GitHub Actions bump;
  - the Florida 25-7.083 text;
  - the waiver rewrite;
  - low-confidence measurement rows;
  - the -15 r8 follow-ups.

## Failed Approaches (Don't Repeat These)

- **The r5 plan's B2, "the credit absorbs a take-back up to its amount".** In Opus's P2 the credit had already refunded its 20, so a later 10 take-back became a credit deficit while the payment could still pay out 40: 60 out of 50. K-10's cap is 30. Use "what the credit still held", plus the cap on the two together.
- **A dynamic split, "what the credit holds now".** Later draws shift earlier take-backs, and the positions stop matching the caps.
- **Placing the shortfall at the take-back** (r5 as built). When the payment's refund later returns, the positions read 40 / −10 while only 30 can be drawn (r6 B2). Decide the shortfall's side at read time instead.
- **Splitting take-backs only by `created_at` within one transaction.** Ties fall to uuid order, so a give-back can be processed before its parent (r6 B3).
- **W4 in one transaction.** Everything shares `now()`, so "take-back before the credit" cannot be expressed. Use a history load with chosen times.
- **`for i in $ids` in this shell.** zsh does not split unquoted variables into words, so the loop ran once with all the ids. Use `... | while read i`.
- **`docker stop` on these postgres-mcp containers.** It returned `Error response from daemon: 404 page not found`. `docker kill` works.
- **The bounce's credit lock** (N145). Once credit draws take the payment's lock, nothing could catch its removal, so it was removed.

## Key Decisions

| Decision | Rationale |
|---|---|
| B2 as built differs from the plan (K-10 decides; reported to Ryan, not asked) | Kyle's refund cap, payment − refunds − reversals, binds the payment and its credit together |
| The cap on the payment and its credit together, on every draw on either | Rows of one transaction share an instant; this keeps K-10 for any reading of the split |
| A reissue carries `least(refund, what is left)`; the commit check requires nothing positive | K-10: where the payment also bounced, what came back offsets money that never arrived |
| r6: a deficit cancelled on an escheated credit is not "money back" | Ryan's rule protects against money returning to the customer, not against a debt being removed |
| The tests added with the build are labelled as such | W2e/W2f, W10e, W11, W12, CR21, CR22; tests-first honesty |

## Current State

**Working:**
- -23 r5 on a fresh clone: battery 293/293, races 33/33, mutations 190/190.
- `tests/ci.sh` 49/49, which needs memory (see Warnings).

**Broken (known):** r5's findings (the r6 list). All reproduce: Codex's probe outputs are appended to `codex-r5.md`, and Opus and Fable executed theirs.

**Uncommitted changes:** none after the wrap-up commit.

**Scratch DBs** (throwaway): `s23`, `r23`, `r23b`, `ci_*`. The scratchpad is session-specific. Recreate the helper as before: clone `tally`, revoke TEMP from PUBLIC, tally_app and tally_core, then strict-apply the patch twice with `PGOPTIONS="-c search_path= -c check_function_bodies=on"`.

## Code Context

```sql
public.cash_drawn_at(kind text, id uuid, at timestamptz) -> numeric
    -- what a payment or credit had given at an instant (statuses as of then); a payment's credits are excluded
public.overpayment_split(credit_id uuid)
    -> TABLE(id, on_date, amount, absorbed, created_at)
    -- every row under the credit's payment's posting entry, in (created_at, id) order, with what the credit absorbs
-- readers:  payment credited = k - sum(absorbed);  credit issued = k - sum(absorbed)  (filtered by on_date <= d, created_at <= R)
-- caps:     payment: tree rows count amount - absorbed;  credit: tree rows count absorbed;
--           plus the cap on the two together (v_pool_pay): payment draws (credits excluded) + credit draws + tree <= payment amount, from p_on
-- locks:    a credit draw: payment, then credit;  a row under a refund's posting row: tree, then refund
```

## Resume Instructions

1. `git pull --ff-only`; `git -C ../gas-billing-memory fetch`. Check `docker ps -q --filter ancestor=crystaldba/postgres-mcp | wc -l`; it is small once Desktop has restarted.
2. Ask Ryan whether to start r6. If yes:
   - **tests first:** an X section in battery-23, recording failures against r5 as `red-r6-against-r5.txt`. Run the battery with `\set ON_ERROR_ROLLBACK on` and `RAISE EXCEPTION 'FAIL` turned into `NOTICE`, so every check reports;
   - **then:** the patch, the battery, races, mutations (~45 min; run with `python3 -u`), and `tests/ci.sh`;
   - **then freeze and review:** copy the six files to `review/*-frozen-r6`, write the brief and its md5;
     - Codex: `PATH=~/.nvm/versions/node/v24.15.0/bin:$PATH codex exec -s workspace-write -o $R/codex-r6-final.txt "$(cat $R/codex-prompt-r6.md)" < /dev/null`;
     - Opus and Fable as background agents (`model: opus`, `model: fable`).
3. Expected: every X check fails on r5 and passes after the fix.

## Warnings

- **Don't edit the patch or tests while `mutations-23.py` runs.**
- **Revoke TEMP after every TEMPLATE clone.**
- **CI dies with "terminated by signal 9" when Docker runs out of memory.** Check the postgres-mcp container count first.
- **A mutation's first catch can move** when a guard changes, as N181 (to W3a) and N191 (to CR18) did. Name the owner by its first failure; don't loosen the rule.
- **Never edit** the frozen review copies or tu.sql's mirrored bodies.
