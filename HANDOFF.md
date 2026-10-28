# Handoff: plan which roadmap phases run concurrently; -23 r6 still waits on Ryan's go

**Generated**: 2026-10-28, 15:20 CDT
**Branch**: `main` in both repos, pushed. GBM is unchanged at `8003ec9` (its untracked `Clippings/` folder isn't ours; leave it).
**Status**: Next session = concurrency planning, which Ryan asked for. Ryan has not answered "shall I start -23 round 6?"; raise it inside the plan, not before it.

## Goal

Reach the C# core build sooner by running roadmap phases side by side. Ryan can attend to **about three sessions at once** when they need his input, so the plan is a set of up to three concurrent workstreams, not maximum parallelism.

The gate (Ryan, 2026-10-13), in order: (1) schema parity, CI-001…CI-135, now 78 of 135; (2) scenarios and test strategy; (3) the core build plan; (4) the build. The gate's order is the open question below.

## Completed (this session, 2026-10-28 afternoon): context and harness, no schema work

- [x] **Repo docs** (`867cd96`):
  - `CLAUDE.md`: session start, how to read the big files, standing rules, wrap-up.
  - `sql/PATCH-LESSONS.md`: 30 lessons moved out of session memory.
  - `CHANGELOG.md` keeps 10 entries; older ones are in `changelog-archive/YYYY-MM.md`.
  - `CONTEXT.md` no longer carries status.
- [x] **Memory** cut from 63 to 23 entries: status snapshots deleted, lessons moved to the repo.
- [x] **Global harness** (backups of everything in `~/.claude-backups/2026-10-28/`):
  - `~/.claude/rules/` and `~/.claude/AGENTS.md` removed;
  - a personal `~/.claude/CLAUDE.md` holds Ryan's working preferences;
  - `"disableClaudeAiConnectors": true` in `~/.ccs/shared/settings.json`, so the claude.ai connectors are off in Claude Code only (Desktop keeps Higgsfield);
  - 11 installer skills and 4 commands (`/jira`, `/orchestrate`, `/claw`, `/devfleet`) moved to the backup;
  - all 34 agents kept (Ryan: decide when the core workflow is designed).
- [x] **Concurrency what-ifs**, run on a scratch copy of the scheduler. The dashboard is unchanged.

## The concurrency analysis so far

Likely "ready to onboard" date under each variant (each row includes the changes above it):

| Variant | Likely | Low | High | Critical path |
|---|---|---|---|---|
| A. today's plan | 2027-06-16 | 04-28 | 09-15 | P1>P2>P3>P4>P5>P6>P8 |
| B. P2 (scenarios) starts now, beside P1 | 05-16 | 04-11 | 07-25 | P2>P3>P4>P5>P6>P8 |
| C. + P4 (platform) starts now | 05-09 | 04-04 | 07-25 | P2>P3>P5>P6>P8 |
| D. + P6 at P5's start (was +6 wk), P7 at P5 +4 wk (was +12) | 04-11 | 02-21 | 07-11 | P2>P3>P5>P8 |

**Caution on B–D:** those dates are about 1½ weeks too early. A phase with no dependency starts at `phases.json`'s `as_of` (2026-10-18), not today.

Why each move is safe:
- **P2 beside P1:** scenario prose, state machines and Kyle-checked worked bills depend on the rules and Kyle's rulings, not on the tables. Only the coverage audit needs P1 finished. Start with families already at parity; hold cash, disputes and collections until -23, -25 and -26 mirror (cash is still changing: "refunded" became derived on 10-21).
- **P4:** login (R1 "trust Cognito", ruled 10-14), AWS environments, CI/CD, the .NET solution and tenant-scoped data access are all independent of the schema's remaining work.
- **P6:** the "harden or rebuild the prototype" decision, roles, permissions, audit views and accessibility don't need the API.
- **P7:** bank and payment files, the meter-read import, the GL export and the conversion templates are generic adapters.

## Not Yet Done

- [ ] **The concurrency plan.** Propose up to three workstreams Ryan can supervise at once, in plain language, one decision at a time. Candidates:
  1. P1 (the -23 r6, -25 and -26 reviews, then waves 4–7, tax and franchise, the PGA billing side);
  2. P2 scenarios for the families already at parity, with Kyle checking dollar figures;
  3. P4 platform foundation, plus the P6 "harden or rebuild" decision.
  - The limits are Ryan's attention (about three sessions) and Kyle's: Kyle both validates P2 and co-owns P6.
  - Prefer pairings where one stream fills another's waiting time (reviewers running, a ruling from Kyle pending).
- [ ] **Ryan's decision:** relax the gate so P2 runs beside P1? Steps 3 and 4 stay in order. P4, P6 and P7 sit outside the gate, so moving them needs no change to it.
- [ ] **After the plan is agreed:** edit `application/roadmap/phases.json` (`depends`, possibly `as_of`), run `python3 tools/roadmap/schedule.py`, and refresh the dashboard as `application/roadmap/README.md` says.
- [ ] **-23 r6** (on Ryan's go): follow `application/wave2-build-2026-10-15/v5.4.2-23-r6-plan.md`.
  - **B1:** recorded-order legs under a payment's posting entry. **B2:** the shortfall's side decided at read time. **B3:** lineage order within one instant.
  - **B4:** `status_recorded_at` write-once. **B5:** a reissue stays in its payment's lineage.
  - **S1:** the refund deadlock. **S2:** the escheated give-back refused only as far as the credit would read positive. **S3:** no future `created_at` for superusers.
  - **S4:** tests and mutations. **S5:** comments.
  - Then freeze, run the three reviewers and merge.
- [ ] **Review -25 and -26** after -23 settles. Both are drafted and tested, not frozen; they mirror after -23, -25 first. At -26's mirror, update APPLICATION-CONTRACTS: AC-10 still lists `dunning_stage` and `late_fee_*` as writable.
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

- **Running `tools/roadmap/schedule.py` in place for a what-if.** It writes `schedule.json`, `golive.json`, `phases-table.json` and `parts.json` next to its own location, which are the dashboard's sources. Copy it and `phases.json` into a scratch tree, `<scratch>/tools/roadmap/` and `<scratch>/application/roadmap/`, and run it there.
- **Treating the scheduler's dates as capacity-aware.** It gives every phase full effort however many run at once. Check any overlap against Ryan's three-session limit and Kyle's time.
- **-23 (still valid):**
  - the r5 plan's B2, "the credit absorbs a take-back up to its amount": 60 out of 50;
  - a dynamic split: positions drift from the caps;
  - the shortfall placed at the take-back: 40 / −10 readable while only 30 can be drawn;
  - `(created_at, id)` order within one transaction: uuid ties;
  - W4 in one transaction: a shared `now()`;
  - `for i in $ids` in zsh: use `while read`;
  - `docker stop` on postgres-mcp containers ("404 page not found"): use `docker kill`.

## Key Decisions

| Decision | Rationale |
|---|---|
| Plan for about three concurrent workstreams | Ryan: "I can only focus on about three running sessions at a time when my input is needed. But that is still better than one." |
| Long sessions are fine; no mid-session reading rules | Ryan: 1M context, and frequent handoffs start fresh sessions |
| Keep all 34 agents and the Laravel skills | Ryan: agents get chosen when the core workflow is designed; the usage history only reflects the schema phase |
| Claude Code drops the claude.ai connectors but Desktop keeps them | Higgsfield is used daily in Desktop; `disableClaudeAiConnectors` is Claude Code-only |
| -23: K-10 decides B2 as built; a cap on the payment and its credit together; reissue = `least(refund, what is left)` | See DECISION-LOG 2026-10-28 |

## Current State

**Working:**
- -23 r5 on a fresh clone: battery 293/293, races 33/33, mutations 190/190.
- `tests/ci.sh` 49/49.

**Broken (known):** r5's findings, listed in the r6 plan.

**Uncommitted changes:** none after this wrap-up's commit.

## Code Context

```
application/roadmap/phases.json       # hand-edited; per phase: depends [{phase, type: finish|start, lag_weeks}], weeks [low, likely, high], parts
tools/roadmap/schedule.py             # writes schedule/golive/phases-table/parts.json beside phases.json; prints ready date per estimate
# dependency rule: 'finish' = start at that phase's end; 'start' = start lag_weeks after it begins
# no dependency -> starts at phases.json as_of (or remaining_from for an in-progress phase)
# work spanning 2026-12-21..2027-01-04 is pushed out 2 weeks
```

Current dependencies: P2←P1 finish; P3←P2 finish; P4←P3 start+0; P5←P3 finish and P4 start+2; P6←P5 start+6; P7←P5 start+12; P8←P5, P6 and P7 finish; P9←P5 start+6; P10←P8 and P9 finish.

## Resume Instructions

1. `git pull --ff-only`; `git -C ../gas-billing-memory fetch` and check `HEAD..origin/main` for Kyle's rulings.
2. Confirm the harness changes held: no `claude.ai …` servers in `/mcp`, and no `rules/` files among the loaded instructions. If ccs rewrote `settings.json` and dropped the key, set `ENABLE_CLAUDEAI_MCP_SERVERS=false` in its `env` block instead.
3. Re-run the what-ifs with `as_of` set to today, to get honest dates (Failed Approaches says how).
4. Walk Ryan through the plan: the gate decision first, alone, in plain language; then the three workstreams.
5. Once agreed: update `phases.json`, run the scheduler, refresh the dashboard, record the decision in DECISION-LOG.

## Warnings

- **Don't edit the patch or tests while `mutations-23.py` runs.**
- **Revoke TEMP after every TEMPLATE clone.**
- **Check the postgres-mcp container count before CI.** CI dies with "terminated by signal 9" when Docker runs out of memory.
- **Never edit the frozen review copies or tu.sql's mirrored bodies.**
- **Things a fresh session may notice that are intentional:**
  - `docs-lookup` needs Context7, which isn't configured; Ryan chose to keep it;
  - global rules no longer exist;
  - personal preferences are in `~/.claude/CLAUDE.md`.
