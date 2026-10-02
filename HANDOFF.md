# Handoff: v5.4.2-15 deposits at parity — round 2 reviewed; decide D1–D5, then build round 3

**Generated**: 2026-10-02 (end of session)
**Branch**: tally-utility `main` (`1a7097b` plus this wrap-up) · gas-billing-memory `main` (`091c990`, no new Kyle commits at the start of the session)
**Status**: Blocked on Ryan's decisions D1–D5 and the proposed stopping rule. -15 is a DRAFT: not mirrored into tu.sql, not landed.

## Goal

Move the Texas deposit law that -06 built into guards out of the database:
- the law becomes per-state, dated, cited platform rows;
- the records keep integrity only;
- the C# core evaluates.

This is the same pattern as -13. The ground rules (memories `schema-represents-core-evaluates`, `launch-scope-is-not-architecture-scope`, `design-permanent-record-on-change`, `utility-owns-regulated-values`) still hold.

## Completed (this session)

- [x] **R-D2 decided** after a council (me, Opus, Codex). The core writes a return-due row when the return falls due, with evidence. A wrong row is corrected by a separate withdrawal table.
- [x] **R-D3 decided:** "the delivery patch" carries no number; deposits is v5.4.2-15.
- [x] **`application/deposits-rules-for-the-core.md`:** every -06 deposit rule, with its source and line range.
  - 20 boundary cases with computed amounts.
  - DG1–DG9: places where -06 disagrees with Kyle's tables #53–#55.
  - Kyle questions K7 and K8 added (K1–K8 in design §5).
- [x] **-15 drafted** (`sql/v5.4.2-15-deposits-law-to-core.sql`).
- [x] **Review round 1** (frozen `4f9468eb`; Opus, Fable, Codex all said "not yet"). Record: `tests/v5.4.2-15/review/review-findings-15-r1.md`.
  - Ryan decided:
    - **B1, option 3:** a later accrual, return or due row cites the deposit's own rule, or a rule of its key in force over its dates (`deposit_rule_citable()`).
    - **B2:** the cap records its source (`statute` or `tariff` plus `cap_tariff_reference`).
    - **B3:** `deposit_rule_waiver_reach` (rule, class, trigger, effect excuse/reduce/defer) replaces `waivable`. The utility's tariff waivers are its own rows (`deposit_tariff_waiver_grounds`). The proposal itself was reviewed by the same three reviewers first (`review/proposal-b3-waiver-reach.md`).
  - A1–A15 folded:
    - a row-version due mutex;
    - a rate advisory lock with a READ COMMITTED pin;
    - no CHECK naming a basis;
    - closure evidence by status and date;
    - stamps;
    - chronology checks;
    - class-specific rates;
    - `cap_other_held` for combined caps;
    - `principal_returned`;
    - a refund lookback and disqualifier rows;
    - time-held evidence;
    - reasons tied to rules;
    - TEMP revoked on test clones.
- [x] **Round-2 revision** `32444e5`: patch `026e25d2`, 2,196 lines.
  - Battery-15 **104/104**; X1; races R1–R6; mutations **91/91**.
  - Regressions 28/58/41/116/3/99/6, plus -13's X1.
  - All of it on clones with TEMP revoked.
- [x] **Review round 2** (frozen `026e25d2`): all three said "not yet". Every finding was reproduced.
  - Record: `tests/v5.4.2-15/review/review-findings-15-r2.md`.
  - Integrity fixes I1–I8 and shape decisions D1–D5 are listed there.

## Not Yet Done (in order)

1. [ ] **Ryan decides D1–D5 and the stopping rule** ("model a shape when it has a real source, such as a statute, Kyle's tables or our own design; record hypothetical shapes as residuals"). My recommendations:
   - **D1, additional-deposit thresholds (#55 rules 5–7):** build it, as a rule part plus a utility table (the R-D1 pattern).
   - **D2, two-part caps** (lesser-of; a ceiling or floor): build it, as cap parts plus a combinator.
   - **D3, deposits paid in instalments:** build it if the citation checks out. Pennsylvania Chapter 14 is unverified.
   - **D4, a mandatory partial return tied to a due row:** build it, as a due row with an amount, settled by `principal_returned`.
   - **D5, reduce-to-amount, instrument substitution, per-disqualifier windows:** residual.
   - Explain each in plain language (memories `prefers-discussion-over-canned-options`, `explain-jargon-in-the-question`).
2. [ ] **Fold I1–I8** (no decision needed):
   - **I1:** the close floor reads `coalesce(period_end, effective_on)`.
   - **I2:** `deposit_return_reasons.requires_measure`, and the delinquency limit becomes optional under a count.
   - **I3:** an accrual must end before any return's date and must not run past exhaustion; principal_basis ≤ the principal held at the period's end; a credit ≤ interest accrued for periods ending before it; period_end < today.
   - **I4:** evidence on or before `due_on`; an event citing a due row is on or after its `due_on`.
   - **I5:** the determination locks its tariff ground; the ground's close is pinned to READ COMMITTED; add a race leg.
   - **I6:** coverage in the rate report per class actually held.
   - **I7:** refuse mixing any-trigger and trigger-specific reach rows for one class on one rule.
   - **I8:** compare the closure date in UTC; the premise's time zone becomes a residual.
3. [ ] Build D-decisions plus I1–I8.
   - Battery and mutations for each new guard: every mutation must be caught at its NAMED check.
   - Strict apply ×2, races, regressions (all on TEMP-revoked clones).
   - Freeze for round 3 if Ryan wants one.
4. [ ] Then mirror -15 into tu.sql (procedure below) and add an entry to sql/DEPLOY-VERIFICATION.md.
5. [ ] Still open:
   - Ryan's R12 follow-ups (a record of a waived deposit; an explicit "no waiver reaches" flag; fail open or closed on missing input; which waiver to record when two are in force; a waiver granted while a deposit is held);
   - the DIVERGENCE (accrued interest must be credited by the deposit's last event), which Ryan has not confirmed;
   - Kyle K1–K8;
   - the rest of the landed-law strip in audit §4 order.

## Failed Approaches (Don't Repeat These)

- **A battery case that a different guard refuses first.** It passes whether or not its own guard exists, so the mutation goes MISSED.
  - Happened about 12 times this session. Typical causes:
    - a deferred evidence check firing under `SET CONSTRAINTS ALL IMMEDIATE`;
    - a "live row" or "refund started" guard refusing before the guard under test;
    - foreign keys from reach rows blocking a delete;
    - the date check masking the status and customer checks.
  - Defer constraints in the negative due-row cases (`EXECUTE 'SET CONSTRAINTS ALL DEFERRED'`). Pick fixtures where ONLY the named guard can refuse, and read the "[first FAIL/ERROR]" column the mutation script prints.
- **`x > 0` in a CHECK on a nullable column.** NULL passes a CHECK.
  - Found three times: `cap_divisor`, the `cap_source` NULL leg, the return-due mandatory leg.
  - Always add `IS NOT NULL`. Use `IS NOT TRUE` or `coalesce(..., false)` in trigger IFs (memory `blank-checks-whitelist-alnum`).
- **A bare `FOR UPDATE` as a count mutex.** It fails under REPEATABLE READ: the waiter gets the lock with no serialisation error and counts from a stale snapshot.
  - Also write a row version: `UPDATE deposits SET status = status`.
  - Keep the early `FOR UPDATE` too. Without it, the status read before the wait is stale (mutation M47, R2).
- **`FOR UPDATE` / `KEY SHARE` on `deposit_interest_rates` as `tally_app`.** Every row-lock clause needs UPDATE privilege, which tally_app lacks there. Use advisory xact locks (`deposit_rate_lock_key()`).
- **`IF x IS DISTINCT FROM CASE … END THEN` in plpgsql.** It fails with "syntax error at end of input", because plpgsql scans the IF condition up to the first THEN. Wrap the CASE in parentheses.
- **`CREATE DATABASE … TEMPLATE tally`.** It drops the database ACL, so tally_app has TEMP and the depth fences are open. Revoke TEMP after every clone (memory `template-clone-drops-acl`). Every battery run before 2026-10-02 had this gap.
- **Codex `read-only` sandbox.** It cannot reach the docker socket, so Codex reviews statically and writes repro scripts, which the main session runs. Codex 0.160 runs `gpt-6-astra`; `--add-dir` lets it read the scratchpad.
- **Reviewer REPORT.md writes** were refused every time. Reviewers send findings by SendMessage instead (memory `reviewer-reports-truncate`).

## Key Decisions

| Decision | Rationale |
|---|---|
| R-D2: a return-due row plus a separate withdrawal table | Evidence of a standing obligation, recorded when it changes. A withdrawal means "the answer was wrong", which is distinct from "the obligation lapsed" (K6, law) |
| B1 option 3: cite the own rule OR the in-force rule of the key | Amendments both spare and reach deposits already held; the citation records which |
| B2: `cap_source` statute/tariff | A tariff can cap tighter, or where the law sets none (R-D1: the utility's value stays the utility's) |
| B3: reach table plus tenant tariff grounds | One boolean couldn't hold K2 or per-trigger/partial waivers. The law holds the permission, the utility holds its grounds |
| Kept "accrued must be credited by the last event" (DIVERGENCE) | Ledger arithmetic, not law; awaiting Ryan |
| The "rule_id IS NULL" refusal has no mutation | The rule-key comparison also refuses (basis is never NULL), so it only changes the message |
| UTC for date comparisons (I8, pending) | A session must not change the outcome; the premise's time zone waits for the places table |

## Current State

**Working:** `tally-pg` runs the fresh build of tu.sql, 26,049 lines (`9139367a…`), with -15 NOT applied. Only `postgres` and `tally` exist (every review database was dropped).
**Broken:** nothing. -15's open items are in the r2 findings.
**Uncommitted changes:** none after this wrap-up.

## Code Context

```sql
-- B1: which rule a later record may cite
public.deposit_rule_citable(p_deposit_id uuid, p_rule_id uuid, p_from date, p_to date) RETURNS boolean
-- A2: rate lock key (rate insert: exclusive; accrual: shared)
public.deposit_rate_lock_key(p_tenant_id uuid, p_state_code text, p_service_type text) RETURNS bigint
-- rule parts must be written in the rule's own transaction (deposit_rules.recorded_txid)
public.enforce_deposit_rule_part_record()   -- on deposit_rule_waiver_reach, deposit_rule_refund_disqualifiers
```

- **The rule close floor** (`enforce_deposit_rule_history`) reads `deposits.posted_on`, `deposit_events.period_end` and `deposit_return_due.due_on`. I1 adds `effective_on` for return events.
- **The run script** for a fresh clone, strict apply and the battery: `scratchpad/run15.sh` (session-local). Its steps: `CREATE DATABASE s15 TEMPLATE tally`; `REVOKE TEMP ON DATABASE s15 FROM PUBLIC, tally_app`; apply the patch with `SET search_path=''; SET check_function_bodies=on` under `psql -1`; then the battery.
- **The mutations** need `tally` to be the -14 build (it is). Run `python3 tests/v5.4.2-15/mutations-15.py [Mnn …]`.
- **The mirror procedure:**
  1. Append the patch body from the first `-- ---` divider before `-- 1.`.
  2. Add a 4-line banner, as at tu.sql 25,931 and 26,050.
  3. `cmp` the prefix and the body.
  4. Rebuild: `docker build -q -t tally-postgres -f postgres/Dockerfile . && docker rm -f -v tally-pg && docker run -d --name tally-pg -e POSTGRES_PASSWORD=tally tally-postgres`, then wait for "PostgreSQL init process complete".
  5. Run catalog identity (`tests/v5.4.2-14/parity/catalog-identity.sql`) on the clone and on the build, and diff.

## Resume Instructions

1. Fetch both repos: `cd ~/code/tally-utility && git pull --ff-only; cd ~/code/gas-billing-memory && git fetch && git log --oneline HEAD..origin/main`.
   - Expected: nothing new, or Kyle's rulings (read those first).
2. Run `docker ps --filter name=tally-pg`. If the container has stopped, `docker start tally-pg` and wait for the init line (memory `tally-pg-readiness-wait`).
3. Open `tests/v5.4.2-15/review/review-findings-15-r2.md` and take D1–D5 and the stopping rule to Ryan.
4. After his calls, fold I1–I8 plus the chosen D items into the patch.
   - Re-run strict apply ×2, the battery, X1, `races/due-mutex-15.sh`, the mutations and the regressions, all on clones with TEMP revoked.
   - Expected: every check green, and every new guard has a mutation caught at its named check.

## Warnings

- **`tu.sql` is append-only.** Mirror only after Ryan approves.
- **Freeze the hash before any review round** (memory `freeze-hash-before-reviews`). One revision per round.
- **Don't trust reviewers' "from memory" citations** (16 TAC §25.24, Pennsylvania Chapter 14). Verify them before modelling.
- **Never `git add -A` in GBM.**
