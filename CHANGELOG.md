# Changelog

A permanent, cumulative ledger of work sessions on the TallyUtility (tally-utility) repo. Newest entries on top. Never overwrite existing entries.

This file keeps the newest 10 sessions. Older entries are in `changelog-archive/YYYY-MM.md` by the month of their date, unchanged; grep there for history. At wrap-up, add the new entry below this header and move the oldest entry here into its month's archive file (newest on top there too).

---

## 2026-10-28 (afternoon) — session-start context cut (repo docs, memory, global harness); roadmap concurrency what-ifs

**What was done:**
- **Measured the startup load** from transcripts: 72–84k tokens before any tool call; orientation adds 20–50k. The CHANGELOG was never read whole at the start. The real costs were global rules, connectors and skills, plus stale status written in several places.
- **Repo** (`867cd96`):
  - `CLAUDE.md`: the gate, session start, a table of the big files and how to grep them, standing rules, wrap-up.
  - `sql/PATCH-LESSONS.md`: 28 lessons moved out of session memory unchanged, plus the -22 lock-order rule and -25's build notes; 30 in all, with an index.
  - The CHANGELOG keeps the newest 10 entries; 75 older ones are in `changelog-archive/YYYY-MM.md`, checked by script to be present word for word.
  - `CONTEXT.md`'s stale status section replaced with one that has no counts or dates.
- **Memory** cut from 63 to 23 files:
  - 8 status snapshots deleted, after their durable lines moved to HANDOFF, CLAUDE.md and the lessons doc;
  - the 3 working-preference memories moved to a new personal `~/.claude/CLAUDE.md`;
  - new: `three-concurrent-sessions`.
- **Global harness**, with every original backed up in `~/.claude-backups/2026-10-28/`:
  - all of `~/.claude/rules/` (38 files) and `~/.claude/AGENTS.md` removed. They loaded into every repo because the home folder is a parent of each one, and the `common/` and `web/` sets had no `paths:` header;
  - `"disableClaudeAiConnectors": true` in `~/.ccs/shared/settings.json`. The connectors dropped out of this session immediately; Desktop keeps them;
  - 11 installer skills and the `/jira`, `/orchestrate`, `/claw` and `/devfleet` commands moved to the backup.
- **Roadmap concurrency what-ifs** on a scratch copy of `schedule.py`. Likely ready-to-onboard date: June 16 under today's plan; May 16 with P2 beside P1; May 9 with P4 started too; April 11 with P6 at P5's start and P7 at P5 +4 weeks. These dates are about 1.5 weeks too early (the `as_of` artefact). Details are in HANDOFF.

**Decisions made:**
- **Ryan: keep all 34 agents and the Laravel skills.** Agents get chosen when the core workflow is designed; never-used means nothing yet, because no code has been written.
- **Ryan: no mid-session reading rules.** The 1M context and frequent handoffs make long sessions fine.
- **Ryan: about three concurrent sessions that need his input.** The concurrency plan is built around that.
- **Global rules dropped rather than trimmed.** They restated practice a capable model follows anyway, and several contradicted this project: 80% coverage, files under 800 lines, agents spawned unasked, and "attribution disabled", which was false.
- **The connectors are off for Claude Code only.** The per-project `/mcp` disable list would have to be set in each of 17 projects.

**Failed approaches:**
- **Assuming path rules load on any file access.** The typescript rules loaded on a Read of a `.tsx` file, but the web rules did not: they were already loaded at startup and aren't loaded twice. Whether Bash `cat` triggers path rules is untested.
- **Running `schedule.py` in place for a what-if:** it overwrites the dashboard's generated files. Run it on a scratch copy.

**Accuracy / test results:** no schema changes. The CHANGELOG split was verified by script: 85 entries present verbatim, each archive holding only its own month.

**Next steps:**
- The concurrency plan: the gate decision for P2, then up to three workstreams; update `phases.json` and the dashboard.
- -23 r6 on Ryan's go; then the -25 and -26 reviews.

---

## 2026-10-28 — -23 cash round 5 built, frozen and reviewed; the r6 list written; Docker container leak fixed

**What was done:**
- **-23 r5, tests first** (`e73626c`): the W section of battery-23. The failing ones fail against r4 (`red-r5-against-r4.txt`).
- **-23 r5, built** (`4f62ae1`, `67b51e9`):
  - `cash_drawn_at` and `overpayment_split`: one split of a take-back between a payment and its overpayment credit, read by both positions, both caps and the escheat check;
  - a cap on the payment and its credit together (Kyle's K-10 refund cap), with a credit draw taking the payment's lock first;
  - nothing under a refund's posting row once it came back;
  - no give-back onto an escheated overpayment credit;
  - a reissue carries what is left (at most the refund), dated on or after the return, and the commit check requires nothing positive left;
  - no future or infinite status time for any role;
  - arrival rows and donations at READ COMMITTED;
  - the bounce's redundant credit lock removed (N145 retired).
- **Tests added with the build:** W2e/W2f, W10e, W11, W12, CR20/CR20b, CR21 and CR22. The mutations' anchors were updated for the rewritten code, and N171–N191 are new.
- **Frozen** (`83317c0`) and reviewed: Codex (`dd565e3`, with the author's probe run appended), Opus (`4dd597a`) and Fable (`0dbf502`). All three said "not yet".
- **The r6 list:** `application/wave2-build-2026-10-15/v5.4.2-23-r6-plan.md`.
- **Records:** DECISION-LOG 2026-10-28; the design doc's corrections for r4 and r5; the r5 plan's "As built"; the roadmap summary and the dashboard `phases` dataset (dates unchanged).
- **Docker:** Claude Desktop's postgres MCP had leaked 69 containers (about 6.4 GB). CI was OOM-killed twice (signal 9).
  - I killed 62 orphans, with Ryan's approval.
  - The new wrapper `~/.local/bin/postgres-mcp-docker` labels and reaps containers, and stops its own on a signal or end of input. The Desktop config points at it (backup `.bak-2026-10-28`).

**Decisions made:**
- **B2 as built (K-10 decides; reported to Ryan, not asked):** the credit absorbs a take-back from what it still held at that instant, then the payment's own part, then any shortfall (the credit up to its amount, then the payment). *Not the plan's "up to the credit's amount":* Opus's P2 would let 60 out of 50. *Not dynamic:* later draws would shift earlier take-backs.
- **The cap on the payment and its credit together, on every draw on either:** rows of one transaction share an instant, so the split alone cannot keep K-10.
- **A reissue carries `least(refund, what is left)`:** where the payment also bounced, nothing is carried and the customer owes the rest (K-10). This refines Ryan's option 1.
- **r6 settles by rule:** a deficit cancelled on an escheated credit is debt removed, not money given back.

**Failed approaches:**
- **The r5 plan's B2 and a dynamic split:** as above.
- **The shortfall placed at the take-back** (r5 as built): the positions read 40 / −10 when only 30 can be drawn (r6 B2).
- **`(created_at, id)` order within one instant:** a give-back can come before its parent (r6 B3).
- **W4 in one transaction:** no recorded order exists within one transaction; use chosen times.
- **`for i in $ids` in zsh:** the variable isn't split into words. Use `while read`.
- **`docker stop` on these containers:** "404 page not found". Use `docker kill`.

**Accuracy / test results:**

| Check | r4 | r5 |
|---|---|---|
| battery-23 | 252 | 293 |
| races/cash-23.sh | CR1–CR19, 29 | CR1–CR22, 33 |
| mutations-23.py | 170/170 | 190/190 (focused run 29/31, then the full run 189/190; owners moved to W3a and CR18, N145 retired) |
| tests/ci.sh | 49/49 | 49/49 (after the Docker fix) |

**Next steps:**
- Ask Ryan whether to start -23 r6 (the r6 plan). Then freeze and review it with the three reviewers.
- -25 and -26 review after -23 settles.
- Ryan to restart Claude Desktop, so the wrapper takes over and the last 7 untagged containers can be removed.

---

## 2026-10-21 — Kyle's K-10 answered; -23 cash rounds 3 and 4 built and reviewed; the r5 list written

**What was done:**
- **K-10:** Kyle answered (relayed by Ryan). His answer is recorded as GBM `kyle-decisions-2026-10-21-refund-then-bounce.md` plus manifest Section BS (`8003ec9`), and the brief is marked answered (`c55afe1`).
  - A refund is its own movement of money.
  - Two caps: a bounce ≤ payment − reversals; a refund ≤ payment − refunds − reversals.
  - A pending refund blocks the bounce.
  - A return-window hold is tenant policy.
- **-23 r3:** tests first (`530ffee`; every new check failed against r2), then the patch (`494f727`, `7728e96`):
  - a `refund` row names no entry and is > 0;
  - every draw is capped by the source less what was taken back under its arrival entry, at every date;
  - a pending refund blocks any row undoing the posting entry;
  - one arrival entry per source (unique indexes plus a check at the write);
  - positions read `received` / `issued`;
  - a donation undo frees the credit;
  - donations and remittances come from the credit's own account; remittances are frozen by the close (UTC day);
  - draws are not recorded before the source was posted;
  - Ryan's call: `refunded` and `donated` are no longer statuses.
  - -19's P-4 is cancelled before P-2 bounces.
  - Reviewed by Opus, Fable and Codex: "not yet". Codex's probes were run, and all reproduced (`5c3a7ab`).
- **-23 r4:** tests first (`d2b4ca3`), then the patch (`c91a00c`):
  - an overpayment credit's payment bounces per K-10 (one live credit per payment);
  - nothing comes back to an escheated credit, and a `refund_reissue` credit carries a refund that returned (Ryan, option 1), with a deferred commit check;
  - donation corrections are capped;
  - arrival rows are written only while the source is pending or active, under its lock, and count from their own date;
  - the cap runs from the new row's date on;
  - give-back rows are not held up, but never land on an ended source;
  - recorded order covers the arrival tree.
  - Reviewed: all three "not yet" (`3517d0b`); Codex hit its usage limit after writing its review; every probe reproduced.
- **The r5 fix list** is merged: `application/wave2-build-2026-10-15/v5.4.2-23-r5-plan.md`.
- **Records:** DECISION-LOG (four entries dated 2026-10-21), the design doc's "Corrections made in review", and the roadmap phases summary plus dashboard dataset (dates unchanged).

**Decisions made:**
- **Ryan:** no stored `refunded` or `donated` status. *Not "refuse the failure once labelled"* (the bank's return of a refund check would be unrecordable). *Not "refunded → posted"* (breaks forward-only).
- **Ryan:** a refund that returns after escheat goes into a new credit. *Not "remit it to the state", not "leave it flagged".*
- **The overpayment credit and the bounce:** what the credit paid out stands, and what it held goes with the payment. *Not Fable's "wait until the credit is empty"* (it needs refunding or spending bounced money).
- **A source's money counts from its arrival entry's date.** *Not "force the entry's date to the payment's"* (an ACH payment settles later).
- **r5 B4 refines Ryan's option 1:** a reissue carries only the escheated credit's positive remainder. Where the payment also bounced, nothing is carried. Reported to Ryan.

**Failed approaches:**
- **Fable's empty-the-credit bounce rule,** and **the date-equality rule:** as above.
- **The arrival counted as `amount + v_amount` at its date:** zero there, so earlier dates were unguarded.
- **plpgsql `IF` with an inner `CASE ... THEN`:** parse error. Compute into a variable first.
- **`NEW.<column>` in a trigger shared by tables without that column:** fails at runtime. Nest the check by `TG_TABLE_NAME`.
- **Two history rows with chosen times in one INSERT:** refused by recorded order. Use one INSERT per row.

**Accuracy / test results:**

| Check | r3 | r4 |
|---|---|---|
| battery-23 | 216 | 252 |
| races/cash-23.sh | CR1–CR17, 26/26 | CR1–CR19, 29/29 |
| mutations-23.py | 140/140 | 170/170 (first run 166/170; four renamed or wrapped) |
| tests/ci.sh | 49/49 | 49/49 |
| reviews | 3 × not yet | 3 × not yet |

**Open / next:**
- **Ask Ryan whether to start r5.** Six blockers: refund-tree guard, the overpayment split, give-back to an escheated overpayment credit, the reissue amount, no future status times, and the READ COMMITTED pin for arrival rows.
- **Then:** -25 and -26 go to review; the mirror order is -23, -25, -26.
- **Tell Kyle:** ui-concepts' `refunded` status, the `do_not_disconnect` checkbox, and the four law findings.

---

## 2026-10-19 — v5.4.2-26 (collections decisions, field verification) designed, tested first, drafted

**What was done:**
- **Orientation:** both repos were pulled. Kyle has not pushed K-10 (GBM is still at `bab1da5`), so -23 r3 still waits. Ryan chose "go ahead with -26" over freezing -25 early.
- **Design** (`9870aea`): `application/wave3-build-2026-10-18/v5.4.2-26-design.md`.
  - **C:** `collections_conditions` and `collections_decisions`, with the act, the subject at the CCK-7 grain, eligible / blocked / unevaluable, conditions, `valid_until`, inputs and fingerprint.
  - **C7:** acts cite their decision.
  - **E:** dunning keys, the stage moved by the database, the late-fee counters dropped, the `do_not_disconnect` fence.
  - **F:** field visits, supervisor approvals, the disconnect order guard.
- **Tests first** (`1f92514`): battery-26, races CR1–CR7, migration P0–P7. They failed first, at `collections_conditions`.
- **The patch** (`cb9abed`, `sql/v5.4.2-26-collections-decisions.sql`):
  - **New:**
    - the conditions vocabulary (20 codes);
    - the decision record and its guard, [C3a]–[C5];
    - `collections_act_check`, shared by dunning events, late-fee charges, disconnect orders and executed visits;
    - `service_order_field_visits`, where the database fills the expected values and the match;
    - `service_order_field_approvals`, where the database stamps the supervisor.
  - **Changed:**
    - a composite bill key on `dunning_events`;
    - the database moves `dunning_stage`;
    - `invoices.late_fee_assessed` and `late_fee_amount` are dropped;
    - `do_not_disconnect` is written only by `recompute_do_not_disconnect`.
- **CI:** -26 is pending in `tests/ci.sh`, with `ci_pre26` as the migration base, plus the battery, races and migration steps.
- **Mutations** (`tests/v5.4.2-26/mutations-26.py`): 127 of 127 caught. The first run caught 123; the four misses were renamed to the earlier check that rightly catches them (C3f6, A5g, CR6b, V4).
- **Roadmap:** the phases summary was updated and the dashboard dataset refreshed. Dates are unchanged.

**Decisions made (by standing rules):**
- **A notice names its bill and the service it threatens.** Kyle's CCK-7 puts a disconnect notice at meter/service grain, correcting the inventory's bill-only grain.
- **Idempotency is checked against the live decision, not by a unique key.** A unique key wedges A→B→A on one day (memory `append-only-vs-unique-deadlock`).
- **Unevaluable blocks**, and an eligible execute decision holds for its own day only (fail toward protection).
- **A disconnect is checked twice**, at order and at execution (CI-067, GBM rank 0).
- **Orders: only the disconnect act is guarded.** Dispatch moves stay free.
- **Rule citations wait for wave 7**, since no collections rule table exists yet. Adding them is additive.
- **One tenant check only**, on field visits: elsewhere row security answers first.
- **A visit takes its order's row `FOR SHARE`**, so an order cancelled while a crew executes it resolves one way or the other (CR8 and CR8b were added).

**Failed approaches:**
- **A unique idempotency key:** it wedges, as above.
- **Dunning log lines that must cite the live decision:** a log written after the next sweep would be refused. The act's own record is checked live; the log needs that record and its date in the window.
- **A vocabulary compared in the default collation:** `aged_suspense` sorts before `agency_pledge`. Use `COLLATE "C"`.
- **A bill with no location that is not consolidated:** refused by `invoices_check`.
- **Composite-key tests a guard beat first:** the fixtures were rebuilt so that only the key refuses (A5b, A5g).
- **Guard pieces always beaten by another check:** they were removed (tenant checks on decisions and approvals, a "no successor" filter, a blocked-but-empty test, an executed-visit filter).

**Accuracy / test results:**

| Check | Result |
|---|---|
| battery-26 | 202 checks (first run: one test bug, V1's sort order; 194 after the fix, 202 after the mutation pass added checks) |
| races/collections-26.sh | CR1–CR8, 11/11 |
| migration-26.py | P0–P7, 22/22 |
| mutations-26.py | 127/127 (first run 123/127, all renames) |
| tests/ci.sh | all pass, 49 steps (all earlier batteries pass with -26 applied) |

**Open / next:**
- **K-10 is unanswered.** -23 r3 waits; then -25 and -26 go to the three reviewers. Mirror order: -23, then -25, then -26.
- **At -26's mirror:** update APPLICATION-CONTRACTS (AC-10, AC-37, a new AC).
- **Tell Kyle:** the UI concept's `do_not_disconnect` checkbox must become a protective enrollment.

---

## 2026-10-18 (evening) — wave 3 begun: inventory, Q1, v5.4.2-25 (disputes) designed, tested first, drafted

**What was done:**
- **Wave-3 source inventory** (`9b9057e`): `application/wave3-build-2026-10-18/source-inventory-wave3.md`, with sources under `sources/`. Disputes and collections decision records (CI-074, 067, 069, 075, 071, 054's dispute side), split into -25 (disputes) and -26 (collections decisions, field verification). It also carries four items for Kyle, none blocking:
  - the day-26 elderly bar;
  - the extreme-weather forecast;
  - "closed days";
  - *Craft* due process for cities.
- **Q1 answered** (`e1ce387`): Ryan, "go with the rule entries". Dispute policies are rule-terms rows, with one law table and one tariff table (DECISION-LOG).
- **Design** (`e7a056f`): `application/wave3-build-2026-10-18/v5.4.2-25-design.md`, covering the law family L1–L7, the record D1–D6 and the meaning changes T1–T2.
- **Tests first** (`bfe4f21`): battery-25 (183 checks), terms-25 (the document format), races DR1–DR7, migration P0–P4, plus the dispute examples and state fixtures (PA, FL, CA municipal, TX electric, TX governmental). All failed first, as intended.
- **The patch** (`sql/v5.4.2-25-disputes.sql`; Ryan: "go ahead with the patch"):
  - **Vocabularies:** customer classes, subjects, blocks, duties.
  - **Kinds:** `dispute` and `dispute_tariff` v1, each with five facets.
  - **`dispute_rules`:** seeded from `law/dispute/dispute_rules.yaml` (TX gas, investor-owned and co-op protected/unprotected; city delegations).
  - **`dispute_tariffs`:** with the never-looser comparator.
  - **The record:** `disputes`, `dispute_amounts` (+ lines), `dispute_determinations`, `dispute_events`. The database writes the opened event and moves the status.
  - **Readers:** `dispute_shelter_as_of` and `dispute_line_shelter_as_of`.
  - **T1:** `pending_dispute` is no longer protective and takes no new enrollment.
  - **T2:** `meter_readings.dispute_*` are dropped; a reading's status `disputed` is tied to an open dispute.
- **CI:** -25 is in `tests/ci.sh`: the pending list, battery, races, the format test, and the migration test on a base snapshotted just before -25.
- **Mutations** (`tests/v5.4.2-25/mutations-25.py`): 110 of 110 caught.
  - The first run caught 106. Three misses were renamed to the earlier test that rightly catches them (DR7b, DR3, R3).
  - One was a real gap: nothing tested the order of shelter starts when the law starts wider than before delinquency. N8a and N8b were added against a test county law row.

**Decisions made (by standing rules; recorded in the design's "Built" section):**
- Duties are checked against their vocabulary by the insert checks; S3 fixes five facets.
- `within_days` compares only with its own kind, with the same anchor and at least the days. Anything else is refused (fail toward protection).
- The status move is a SECURITY DEFINER trigger function (residual R7): the application holds no UPDATE on disputes, and the update guard admits only the move that names its event.
- Another tenant's amount, line, determination or event is refused as row security before a guard reads anything; for a dispute, row security itself answers.

**Failed approaches:**
- **Tests that compared list values in document order** (K3, K5, U2): the -17 template stores owner types and text[] facets sorted.
- **`deferred()` run as one tenant's operator:** it fired the fixtures' deferred bill checks, which could not see another tenant's snapshot. The fixtures' checks now run as the owner.
- **H10's plain TRUNCATE:** PostgreSQL's own foreign-key check refuses it before the guard can, so the test now uses CASCADE.
- **Guard pieces that could never be what refuses** (a dispute's tenant check, two trigger-depth fences, an early return, the cited law row's attribute check): another check always answered first. They were removed.

**Accuracy / test results:**

| Check | Result |
|---|---|
| battery-25 | 201/201 (183 written first, 18 added from the mutation pass) |
| races/disputes-25.sh | DR1–DR9, 12/12 |
| terms-25.py | 0 failures (40 must-refuse cases; validators agree on every example and mutation) |
| migration-25.py | P0–P4, 13/13 |
| mutations-25.py | 110/110 (first run 106/110) |
| tests/ci.sh | all pass, 44 steps (first run: two failures — battery-19 RW6 updated for T2, and a -17 RC5 timing flake that passes on rerun with and without -25) |

**Open / next:**
- Kyle's K-10 is still unanswered (GBM unchanged); -23 r3 waits on it.
- -25 is not frozen and not reviewed. Freeze it and send it to all three reviewers after -23 r3 settles, or sooner if Ryan says so. It mirrors only after -23.
- -26 (collections decisions, field verification) follows.

---

## 2026-10-16 (evening) to 2026-10-18 — v5.4.2-23 (cash): triage, design, r1 and r2 drafted, two review rounds; r3 waits on Kyle

**What was done:**
- **Triage and design** (`0cb882a`, `23be62c`):
  - cash split into -23 (M, X, A, C) and -24 (U, L) (Ryan: "split it, go with the default");
  - design in `application/wave2-build-2026-10-15/v5.4.2-23-design.md`;
  - CI-058 corrected.
- **r1** (`d7d0d82`, `df41294`, `2c80188`, `3d329c2`):
  - the general reversal cap at every entry on the path, at every date, with one lock per tree root;
  - derived positions replace the counters;
  - payment application per bill line with source and line caps;
  - overpayment approvals; the within-bill order tariff; the line class at issue.

  Ryan kept the 1,000-deep reversal bound. Mutations 71/71. Frozen.
- **Round 1** (`3adeb8c`): Opus, Fable and Codex all "not yet". Codex's probes were run, and every predicted blocker was confirmed.
- **Kyle brief** (`3ff52bc`, `ff402b3`): `application/kyle-brief-2026-10-17-refund-then-bounce.md`. A $50 check refunded $30 then bounces: is a refund an undo of the payment or its own movement (K1)? What happens to a pending refund at the bounce (K2)? Is a refund allowed while a return is possible? Ryan sent it.
- **r2 plan** (`6b96f47`): every round-1 finding settled by a standing rule; refund-and-bounce held for Kyle.
- **r2 implemented** (`6452119`):
  - `check_cash_source` takes the source lock before reading the source;
  - births pending/active;
  - exact causes for nsf, reversed, refunded, voided, escheated and donated;
  - `cash_arrival_stands` and the bounce-row guard;
  - donations and escheats are draws;
  - `status_recorded_at`; positions gated on `first_issued_at`;
  - no future-dated reversal;
  - only the reversal types, `adjustment` and `write_off` name an entry;
  - the approver of the tenant's own;
  - column-grant invariants.
- **Older tests:**
  - -19: P1 became a move; P-2 and R4-PARENT posted by their entries; B1 20 not 40.
  - -21: credit 2161's `credit_issued` entry; 2181 posted.
  - -22 R12n kept: `write_off` may name an entry.
- **Tests** (`e72a311`):
  - battery-23 168 (R1–R18b, LC3; R4 rewritten to use Q2's own nsf row, the old case kept as R4a);
  - races CR1–CR13 (CR3 = the bounce row against an application in flight; CR9–CR12 reverse orders and REPEATABLE READ; CR13 a move to refunded against the refund's void);
  - mutations 110/110 (10 re-anchored, N72–N110 new).
- **r2 frozen** (`8570e95`): brief with six md5s; header (R2 closed, R9–R11, "Open with Kyle", lock order restated); DEPLOY-VERIFICATION `statement_timeout` (R11).
- **Round 2** (`852e68d`): all three "not yet". Codex's 14 probes were run, and all seven of its blockers reproduced.
- **Go-live dashboard refreshed:** P1 78/135, parity after -22, K-10 added. Likely ready-to-onboard is still 2027-06-16.

**Decisions made:**
- **Split cash into -23 and -24** (Ryan).
- **Keep the reversal depth at 1,000** (Ryan; memory `measure-the-real-shape-before-limiting`).
- **Send r2 for review before Kyle answers** (Ryan): most of r2 is independent of the refund question.
- **Wait for Kyle before r3** (Ryan, 2026-10-18): under K1 = A the refund exemption, and three blockers with it, are deleted rather than fixed.
- **`write_off` may name an entry:** -22's nested write-off.
- **A payment is born pending:** a born-posted payment had no posting entry behind it (guard the act).

**Failed approaches:**
- **The refund exemption keyed on `reference_id`:** a +100 adjustment citing a 0.01 refund undid an applied payment's money (all three reviewers).
- **No test posted a refund on the ledger:** the exemption and the refund's posting row were untested. Removing the exemption left 168/168.
- **K2 "refused" stated in the header, plan and brief, but not coded:** the patch admitted the bounce.
- **The old R4 named another payment's nsf row:** refused for the wrong reason, so N76 slipped past.
- **N31, N34 and N32 named at checks that no longer ran first or no longer exercised the lock:** renamed to M3f2 and M3h2, and CR13 added.

**Accuracy / test results:**

| Revision | Battery | Races | Mutations | CI |
|---|---|---|---|---|
| r1 (frozen) | 107 | CR1–CR8 (11) | 71/71 | all pass (38 steps) |
| r2 (frozen) | 168 | CR1–CR13 (18) | 110/110 (first run 106/110: N31, N32, N34, N76) | all pass |

**Round-2 findings:**
- **Codex probes:** B1–B7 all executed as ACCEPTED where a refusal was expected (B4: refused under its own `credit_issued` entry and accepted under an unrelated payment's).
- **Opus:** five blockers, all executed.
- **Fable:** three blockers, all executed.

**Open / next:**
- Kyle's K-10 answer, then the r3 plan (HANDOFF lists the merged findings, split into "either answer" and "depends on K1").
- While waiting: the wave-3 source inventory (disputes and collections). -24 waits until r3 settles.
- Carried items unchanged (see HANDOFF).

---

## 2026-10-16 (afternoon) — v5.4.2-22 review rounds 5–9; r5–r9 frozen; -22 mirrored into tu.sql (parity 78 of 135)

**What was done:**
- **r5 frozen (`6d3d709`); round 5:** Opus, Fable and Codex all ready.
  - Codex's 18 probes were executed. Its S1 (two transactions that each post then close deadlock) was reproduced with two sessions.
  - The should-fix items: the deadlock list was incomplete (all three); the "retry it" signal for a chosen-time history row could never succeed (Opus N1); test gaps.
  - **Ryan: fix them before the mirror** (default offered: mirror r5).
- **r6 (`e3393f2`):**
  - the lock order is rewritten;
  - a chosen-time row before a tree row gets 23514, a row stamped at its start keeps 40001;
  - new message text;
  - battery R11b/R11c, R12i–R12o (166); races CR16–CR18, using barriers; mutations M73–M79 (79/79).
- **Round 6:** Opus and Fable ready. Both showed the "complete" deadlock list still missing shapes: the period row, then a write; the tenant row, then the user's row; either, then a withdrawal. Codex hit its usage limit. **Ryan waived Codex for r6–r9.**
- **r7 (`7c887f2`):**
  - the lock order is a rule over the close's four rows, in order;
  - races CR19 and CR20;
  - battery R5b (167): no order of its same-date rows passes, so M71 and M54 are caught at one check every run.
- **r8 (`6176902`), comments only:** the rule counts indirect waits; no list is promised complete; every writer retries 40P01; one UPDATE that changes the edges and names slug can deadlock by itself.
- **Round 7:** both ready.
- **r9 (`f75f90e`), comments only:** lock-mode naming fixed; `tally_void`'s grant noted as unused; the users/tenant DELETE noted as owner-only and refused (checked in `pg_trigger`/grants). Ryan asked for this rather than a correction in -23.
- **Rounds 8 and 9:** both ready; nothing to fix in round 9.
- **Mirror (`eef5122`, Ryan: "yes, mirror it"):**
  - tu.sql went from 40,652 to 42,310 lines; the body is byte-identical to patch lines 347–1999;
  - `ci.sh --build`: 33/33, zero init errors;
  - pg_dump parity with the -21 build plus frozen r9;
  - catalog identity 11,580 lines;
  - PENDING emptied;
  - DEPLOY-VERIFICATION entry, with a deploy-time audit query.
- **Parity update 2026-10-16:** CI-048, CI-076 and CI-110 are REP+PROT, so 78 of 135 are done. GBM manifest Section BR (`bab1da5`).
- **Memory:**
  - `race-barriers-clear-stat-snapshot.md` (new);
  - `v5422-periods-landed.md` (new);
  - the Codex waiver added to `all-three-reviewers-before-mirror.md`.

**Decisions made:**
- Fix before the mirror, twice (Ryan): tu.sql's mirrored text is never edited, so a wrong sentence would stay there until -23 corrected it.
- Codex waived after r5 (Ryan): it had said ready on r5; what followed was one small code change and wording.
- The 23514 split, logged in DECISION-LOG: a chosen time never changes on a retry.
- The own-transaction 40001 case (owner only) is stated in R12, not coded: telling "its own" apart needs subtransaction-aware xmin checks.
- The lock order is a rule, not a list: four rounds each found a missing shape, and no deadlock ever admitted a row.

**Failed approaches:**
- Barriers that poll `pg_stat_activity` without `pg_stat_clear_snapshot()`: the view is cached per transaction, so CR15 and CR17 timed out.
- A "these are the cycles" list: incomplete in rounds 5, 6, 7 and 8.
- A named mutation catch that depended on same-date tie order: M71 moved between R10f and R12h from run to run.
- An edit to the battery during a mutation run. It was a broken quote, fixed in about 30 s. No mutation was affected: 79/79 named catches.
- R12i read as "the retry succeeds": the later row was the transaction's own.
- `email` listed as a unique users column: it isn't (checked `pg_index`).

**Accuracy / test results:**

| Revision | Battery | Races | Mutations | CI |
|---|---|---|---|---|
| r5 (frozen) | 157 | CR1–CR15 | 72/72 | 35/35 |
| r6 | 166 | CR1–CR18 (28, ×3) | 79/79 | 35/35 |
| r7 | 167 | CR1–CR20 (30, ×3) | 79/79 (78 + M54 renamed, re-run) | 35/35 |
| r8, r9 | unchanged | unchanged | 79/79, one full run each | 35/35 |
| build after the mirror | — | — | — | 33/33 (`--build`) |

- Codex probes (r5): 18 of 18 matched their predictions. The deploy-time audit returns 0 on the build.

**Open / next:**
- v5.4.2-23, cash: M, X, A, C, U, L in the source inventory. It is meaning-changing, and it restates the lock order in -22's form.
- Refresh the go-live roadmap dashboard.
- Carried items unchanged (see HANDOFF).

---

## 2026-10-16 — v5.4.2-22 review rounds 3 and 4; r3 and r4 frozen; r5 drafted (cap at every date and recorded instant, edges wait for the close, walks' plans pinned)

**What was done:**
- **Why last session's mutation run never finished:** one backend had sat in battery check R11 for 12 hours.
  - The cause was in the patch. The write-off cap's recursive walks scanned the customer's ledger at every step: the planner chose the tenant or customer index over the link.
  - Fixed with link-only joins. Also added R10f and R10g, M62 and M63, and a 300 s statement timeout in the runner.
  - **r3 frozen (`0b31d2b`):** battery 149, mutations 63/63, CI 35/35.
- **Round 3:**

  | Reviewer | Verdict | Blocker |
  |---|---|---|
  | Opus | not yet | B1: the cap held only for the final net; a later-dated reversal let February's snapshot freeze 200 recovered against 100 |
  | Codex | not yet | B1: the close's edges were read after its instant without a lock |
  | Fable | ready | none |

  - Codex's 12 probes were executed and appended.
- **r4 (frozen at `94d3b99`):**
  - the cap holds at every date of the tree;
  - tree rows are dated on or after the entry they name;
  - a row recorded before a tree row is refused with 40001 (retry);
  - the new trigger `enforce_aging_edges_close_order` makes an edges change take the close head FOR SHARE;
  - the upward walk carries type and customer;
  - the walk functions run with seqscan, hashjoin and mergejoin off;
  - the lock order states the cross-write-off deadlock.
  - Tests: battery 154 (R12–R12e), races CR13–CR15, mutations 68/68 (the runner now VACUUMs first), CI 35/35.
- **Round 4:**

  | Reviewer | Verdict | Blocker |
  |---|---|---|
  | Opus | ready | none |
  | Fable | ready | none |
  | Codex | not yet | B1: a superuser history row recorded at `infinity` makes 40001 permanent for its tree |

  - Codex's 15 probes were executed; B1 and S1 reproduced.
- **r5 drafted (`341590e`), not frozen:**
  - tree rows, the write-off included, are recorded at a finite time already reached; the trigger also fires for write-off rows;
  - the invariant pins the walks' `proconfig`;
  - the tenant-row deadlock is stated in the header;
  - new residual R12: history loads go one statement per recorded instant;
  - R12f–R12h, M69–M72; CR15 asserts 40001.
  - Tests: battery 157, CR1–CR15, mutations 72/72, CI 35/35.
- **Review files:** findings files for r3 and r4, the r5 brief, the Codex r5 prompt, and the DECISION-LOG entry for 2026-10-16.
- **Memory:** `recursive-walks-join-on-link-alone.md` (pin the plan; test after VACUUM).

**Decisions made:**
- The cap holds at every date, and the tree is in date order: aging and the close net the tree at a date.
- The cap also holds at every recorded instant: a row recorded before a row already in its tree is refused for retry (40001). `created_at` is the transaction's start, not its commit.
- Edges timing is enforced by a lock, not reworded. Codex called it blocking; Opus called it cosmetic; settled by "design permanent".
- The tenant-row deadlock is stated rather than rerouting the snapshot FK: rerouting changes keys, and `closed_by` still locks a row.
- Logged in DECISION-LOG.

**Failed approaches:**
- Tenant or customer predicates in a recursive step's join: a scan per step, and a 12-hour hang under M57.
- Link-only joins without pinned plans: on a vacuumed ledger, a hash join with a seqscan. With only seqscan off, a merge join over a full index scan. R10g flapped between 1.5 s and 30 s.
- Testing plans on a fresh clone: M68 was missed until the runner VACUUMed first.
- `WHEN OTHERS` to catch a statement timeout: `query_canceled` escapes it.
- R10f with only a foreign-customer row: it never fires C5's cap, so M62 was missed.
- psql `LAST_ERROR_SQLSTATE` after COPY: it stays `00000`.

**Accuracy / test results:**

| Revision | Battery | Races | Mutations | CI |
|---|---|---|---|---|
| r3 | 149 | CR1–CR12 | 63/63 | 35/35 |
| r4 | 154 | CR1–CR15 | 68/68 | 35/35 |
| r5 | 157 | CR1–CR15 | 72/72 | 35/35 |

- The bulk load of 200,000 rows followed by 5,000 reversals went from 51 s on r3 (Opus) to 0.8 s on r4.

**Open / next:**
- Freeze r5: copy the files, write the diff, fill the four md5s, write the brief's md5.
- Launch round 5 in a fresh session (Ryan's call: context was high).
- Mirror into tu.sql only on Ryan's approval, after three "ready" verdicts.
- Then -23 (cash).
- Carried items unchanged (see HANDOFF).

---

## 2026-10-15 (late) — v5.4.2-22 review round 2; r3 drafted (net write-off cap after insert, fail-closed lineage walk, close reads the tenant's setting)

**What was done:**
- **Resume:** no drift. CI passed with -22 pending. The r2 frozen hashes match the brief.
- **Round 2 of -22** (`788aef4`):
  - Opus: not yet.
  - Fable: ready.
  - Codex: not yet. Its 11 probes were run by me and appended to `codex-r2.md`.
- **Blocking findings, all reproduced:**
  - a row naming a write-off listed before it in one statement escapes the BEFORE-trigger rule (Codex B1 = Opus B1a);
  - a row naming the recovery is uncapped (Opus B1b);
  - a 10,001-row reversal ring is admitted (Codex B2).
- **`review-findings-22-r2.md`:** 13 findings with their dispositions.
- **r3 draft** (`sql/v5.4.2-22-periods-snapshot-gl-aging.sql`, 1,733 lines):
  - the write-off rule moved to AFTER INSERT, capping the net of the whole same-customer tree in [0, written off];
  - the lineage walk fails closed at 1,000 entries;
  - the close reads `tenants.receivables_aging_bucket_days`, and `tally_close`'s grants and seal list follow;
  - a withdrawal requires a user;
  - a "withdrawn" message at the close;
  - three more constraints pinned;
  - the seal refuses `closed_by` for `tally_app`;
  - header and residual R10.
- **Tests on r3:**
  - battery 147/147 (new: R9–R11, P9f, C13b, C16b; C12 uses the stored edges);
  - races CR1–CR12 (new: CR11, CR12);
  - mutations M53–M61 added, anchors updated, exact label match;
  - Codex's r2 blockers refused on r3.
- **r3 review brief** written, with hash placeholders.

**Decisions made:**
- The R-02 cap on a write-off is the net of its whole same-customer tree, not the gross recoveries. That closes both bypasses, and a bounced recovery frees the cap.
- The close reads the tenant's own setting, not the app-written history (memory "app-written logs are not guards").
- Withdrawal stays an operator's act with a named user. It is undone by re-creating the period, so it is not irreversible. Opus asked for a supervisor gate; Fable disagreed; settled by rule. Logged in DECISION-LOG.

**Failed approaches:**
- A BEFORE-trigger cap: it cannot see later rows of the statement.
- Gross recovery counting: indirect rows escape, and reversed recoveries block.
- A silent depth bound: a ring longer than the bound is admitted.
- M60 reading the history: `tally_close` has no grant, so it fails at C7 instead of C16b.
- P9f as `tally_app`: RLS hides the row, so the UPDATE touches 0 rows.

**Open / next:**
- The full mutation run on r3 had not finished at wrap-up. Re-run it, then `tests/ci.sh`, freeze r3, fill the brief, and launch round 3.
- Mirror only on Ryan's approval.
- Then -23 (cash).
- Carried items unchanged (see HANDOFF).

---

## 2026-10-15 — parity record consolidated; wave 2 started; v5.4.2-22 (periods, close snapshot, GL mapping, aging, write-off recovery) drafted, reviewed once, r2 frozen

**What was done:**
- **Resume:** Kyle's 3 pushes fast-forwarded. CI passed 30/30 on the -21 build.
- **The parity record (Ryan):** the tally-utility measurement is the single live record, and GBM register grades are frozen at v5.4.2-12 (GBM was eight patches behind, not two).
  - The 2026-10-15 update section: REP+PROT 51, REP 24, PARTIAL 46, GAP 13, BLOCKED 0, N/A 1 (`5680e6f`).
  - GBM `954c472`: preamble, frozen status line, manifest BP and BQ.
- **Wave 2 inventory** (`a7ce6d0`): -22 periods and reporting (additive), -23 cash (meaning-changing).
- **Q1 (Ryan, default):** under add-only money, a status column stays, moves forward only, and each move names its add-only row (`9b996b0`).
- **`sql/v5.4.2-22-periods-snapshot-gl-aging.sql`:**
  - **r1** (`afa7b67`):
    - accounting periods (contiguous, born open, closed only by the close);
    - a per-tenant closed-through head;
    - the freeze on ledger, payments and credits;
    - `close_accounting_period()` owned by the new role `tally_close` (supervisor, READ COMMITTED, ended at UTC-12, in order);
    - snapshots and lines computed at one recorded instant;
    - GL mappings (four-part wildcard key, dated and recorded, close-only edits, floor at the closed-through date);
    - `receivables_aging_as_of()` (balance-forward, netted by lineage, customer status per D-3);
    - aging bucket setting;
    - `write_off_recovery` with cap.
  - **r2** (wrap-up commit), from round 1 (all three "not yet"):
    - lineage loops refused;
    - aging edges validated everywhere and passed explicitly to reproduce a snapshot;
    - any row naming a write-off is a recovery;
    - the close refuses rows recorded after its instant;
    - two-tenant moves checked against both heads;
    - GL precedence stated and clock stamps;
    - mistyped open period withdrawn by status;
    - `write_off_threshold_days`;
    - the invariant pins constraints and the ledger's immutability.
- **Tests:**
  - `battery-22.sql`: 135 checks;
  - `races/close-22.sh`: CR1–CR10;
  - `mutations-22.py`: 52/52;
  - `tests/ci.sh`: all pass with -22 pending.
- **Codex** reviewed the source only. I ran its 8 probes; all reproduced.
- **Roadmap:** parity 75/135, W2-Q1 answered, wave 2 in progress. Dates unchanged. Dashboard datasets refreshed.

**Decisions made:**
- Q1 (Ryan), above.
- Drafting calls reported to Ryan (DECISION-LOG 2026-10-15):
  - the closed-through head;
  - the supervisor-only close;
  - UTC-12;
  - unbilled revenue supplied with its basis;
  - balance-forward aging;
  - status as recorded;
  - the GL floor.
- r2: withdrawal is a status, not a DELETE, because -21's retention invariant forbids app deletes.

**Open / next:**
- Launch -22 review round 2 (brief and frozen files ready). Mirror only on Ryan's approval.
- Then -23 (cash).
- Carried:
  - reply to Kyle on D-2's location;
  - the -05 defect;
  - -21 R9;
  - the R-03 scoping question;
  - `deferred_balance_after`.
