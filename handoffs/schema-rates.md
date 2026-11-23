Folder: `~/code/tally-utility-rates`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: schema stream "rates" — tax, gas cost, zones, reads, dated history

**Generated**: 2026-11-22, end of this stream's fifth session
**Branch**: `main`. Run `git pull --ff-only` first.
**Status**: Ready for the next patch. **v5.4.2-30** (tax levies and taxability) was **mirrored 2026-11-22**. **-31 (franchise fees)** is next: not claimed, not started, unblocked (Kyle answered K-15 on 2026-11-06).

## Goal

Close the rates half of the open invariants, beside the money stream (`~/code/tally-utility`). Parity stands at 85 of 135.

## How this stream differs from working alone

- **The board** (`HANDOFF.md`): read it at session start and before every mirror. Edit only this stream's lines.
- **Next free patch number:** -31. Claim it on the board, commit and push before creating its file.
- **`tests/ci.sh`:** one run at a time across clones (a lock). `PENDING` holds money's -25, -26 and -24; nothing of ours.
- **Law runners:** this clone has no `tools/law/.venv`. `ci.sh` finds the main checkout's venv by itself.

## Completed this session

- [x] **-30 r3:** Codex reviewed it (not yet). Its blocking item was confirmed with its probe: a past read answered one place twice, or both within and outside.
- [x] **-30 r4** (`application/rates-build-2026-11-05/v5.4.2-30-r4-plan.md`): alike repeats answer once, disagreeing ones refuse (21000). All three reviewers ready.
- [x] **-30 r5** (`v5.4.2-30-r5-plan.md`): the three-argument `premise_places_as_of` reads what is committed (at `infinity`), as -16's did. Read at `now()` (r1–r4) it answered a voided district beside its replacement. The memberships that count are picked once. Race verdicts name their proof, with a selftest. All three ready.
- [x] **-30 r6:** words only (L7, one function comment). Schema dumps of r5 and r6 differ in that comment alone; Opus confirmed.
- [x] **Mirrored** (Ryan: "mirror it once money's reviewers are done"), ahead of -25, -26 and -24. tu.sql 49,958 lines, md5 `373668c99fe6b18496845ed59c5e1c65`; schema parity 0 lines; `ci.sh --build` 61/61. DEPLOY-VERIFICATION, parity update (no class change), AC-47, DECISION-LOG, board note to money, GBM Section CA.

## Not Yet Done

1. [ ] **-31 franchise fees** (Kyle 2026-11-06, GBM `application/kyle-decisions-2026-11-06-franchise-fee-base.md`; design: `application/rates-build-2026-11-05/tax-design.md` section 3):
   - The base is one of two values, no default: "gas sales" or "all billed lines" (never taxes or the fee itself).
   - A rider's exclusion leaves it out of the rule's base.
   - No per-charge flag: a city may have several franchise rules, each covering a required list of customer classes. No two rules may cover one class over overlapping dates; this replaces `UNIQUE (tenant_id, city_name, effective_date)`.
   - Keyed to the city as a place; rate in percent.
   - No 2% cap check that assumes §182.025 governs city-owned systems (§182.026(a)).
   - CI-044 also needs a line-to-rule link and a remittance record: the link is on the money stream's bill lines, so leave a board note.
2. [ ] -32 (Texas cities and districts, with the Comptroller's rates as reference facts).
3. [ ] Carried over: the gas-cost billing side; zones and factor tables; read ownership and replacement reads (Kyle batch 2, answer 15); dated history and the meter test fee; the backbilling tariff table (Kyle batch 2, answers 10–14); retiring the `decimal` rate unit; retiring the old customer exempt columns (-30 L4).
4. [ ] Small items left from -30's reviews, none blocking, all for the next patch that touches the file:
   - two filters of the state's own place row in `premise_places_as_of` have no test (`p.created_at`, its `end_as_known`);
   - the race selftest does not check the run's exit status; a failed `LAST` query in R3 prints FAIL, not BROKEN;
   - L7 (b) says every later read "refuses or answers both"; "can refuse or answer both" is exact (alike repeats answer once);
   - with four places a premise, the read costs about twice r4's (replanning), half of -16's.
5. [ ] Unexplained: `ci.sh` once failed battery -22's R11d on 2026-11-22 (1.34 s against 1 s). Timed at about 0.3 s with and without -30; every later run passed. The load average was about 12 soon after. If it recurs on a quiet machine, look into it.

## Failed Approaches (Don't Repeat These)

- **An as-of read at `now()` standing in for a plain read:** the caller's transaction start is compared with other writers' starts, so a long transaction misses a committed void. Use `infinity` for "what is committed".
- **Waiting for a run instant's writers, then reading:** the answer can settle on a row and its replacement. The instant itself must be one with no earlier transaction open (AC-47).
- **The same filters written twice** (once for the refusal, once for the answer): four were untested in one copy. Pick the rows once.
- **`count(*)` for "two places of one group":** it counts records. Count distinct places.
- **A race leg's `FAIL` label as a mutation's catch:** an unrelated error prints the same label. Name the damage, the SQLSTATE or the answer.
- **Two new battery checks sharing a premise:** the first one's check catches the second's mutation (N66 at M12h). One premise per claim.
- **`psql -c` exits 1 on a SQL error, a script 3:** read both.
- **`P="docker exec …"; $P …` in zsh:** no word splitting. Use a function.
- **`git pull --rebase --autostash` with the DECISION-LOG edited:** it conflicts with other streams' entries and leaves the tree half-merged. Pull before editing shared files.
- Carried over: a place-close check at the close itself refuses every succession (check at commit); `clock_timestamp()` in the state history; `ALTER TABLE places` after a close in one battery transaction ("pending trigger events"); reading after `COMMIT` in a session that did `SET ROLE tally_app` (22P02); a uuid as a rule-template key; non-canonical JSON numbers (`1.0`).

## Key Decisions (DECISION-LOG 2026-11-22)

| Decision | Rationale |
|---|---|
| Disagreeing records of one place refuse; alike ones answer once | A read that can be ambiguous refuses; refusing a certain answer would make that bill's instant unreadable for good |
| The plain read reads at `infinity` | A patch does not break what an earlier one had right; a refusal would stop long billing runs on every ordinary correction |
| The run's instant is a contract on the core (AC-47) | A patch header is not carried into tu.sql; R-22 is unchanged |
| -30 mirrored ahead of -25, -26, -24 (Ryan) | Ready, no shared function or trigger; waiting meant retesting after each |

## Current State

**Working:** `tally` holds -23, -27, -28, -29 and -30. `ci.sh --build` 61/61 with money's -25, -26 and -24 pending.
**Broken:** none known.
**Uncommitted changes:** none after the wrap-up commit.

## Code Context (for -31)

```sql
tax_levies (tenant_id, state_code, service_type, system_kind, place_kind, place_code, tax_kind, effective_from, effective_to,
            terms_kind 'tax_levy', terms {rate_percent, stacking_position, computed_on, source_kind, citation, reaches_residential})
  -- rule_table_register('public.tax_levies','tariff','tax_levy', ARRAY['place_kind','place_code','tax_kind'], …,
  --   'public.tax_levy_insert_check(jsonb)'): the pattern to copy for a rule keyed to a city as a place
tax_levy_as_of(…, p_on date, p_recorded_at timestamptz)          -- 2 rows raise 21000
premise_places_as_of(loc uuid, on date, axis text, recorded_at)  -- as known at an instant
premise_places_as_of(loc uuid, on date, axis text)               -- as committed (infinity)
check_place_levy_coverage()   -- deferred; a place is never closed from under a levy
franchise_fee_rules           -- still keyed on city_name text; UNIQUE (tenant_id, city_name, effective_date)
```

## Resume Instructions

1. `git pull --ff-only`; fetch GBM; read the board and this file.
   - Expected: no commits touching this stream's files. Money's -24/-25 may have moved.
2. Claim -31 on the board, push.
3. Read Kyle's 2026-11-06 file and `tax-design.md` section 3; inventory every reader and writer of `franchise_fee_rules` in tu.sql (`grep -n franchise_fee sql/tu.sql`) and in the tests before drafting.
   - Expected: conflicts settled by rule; ask Ryan only where money ends up differently.
4. Tests first (`tests/v5.4.2-31/battery-31.sql`), then the patch; strict apply twice; then `ci.sh` PENDING once its battery passes alone.

## Warnings

- `preconditions-30.sh` and `mutations-30.sh` clone `tally` and expect it without -30: they no longer run as written. `levy-30.sh` still runs, through `ci.sh`.
- Revoke TEMP after every TEMPLATE clone. At most two mutation runs at once.
- Never edit the frozen review copies or `tu.sql`'s mirrored bodies.
- Run `/verify` (the verification-loop skill) right before a commit that holds code; not for docs or tests.
- A test fixture's county must use an even code 48990–48998, never a real one.
- Kyle's batch 2 answer 3b (late-charge tax depends on the tariff's form) and the penalty engine are the money stream's.
- Before writing or reviewing patch code, read the index at the top of `sql/PATCH-LESSONS.md`.
- Ryan wants plain language with no shorthand codes in what he reads, and one decision per message.
