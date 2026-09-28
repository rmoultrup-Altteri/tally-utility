# Handoff: Audit the whole system for Texas-only architecture (A-2 / v5.4.2-13 paused)

**Generated**: 2026-09-28 16:40
**Branch**: tally-utility `main` (pushing `570d437` with this wrap-up) · gas-billing-memory `main` (`091c990`, unchanged this session)
**Status**: The A-2 patch is paused and not merged, pending a new task: a full audit for Texas-only architecture.

## THE ONE THING TO CARRY FORWARD

**Ryan's ruling, 2026-09-28:** "A Texas only launch does not mean a Texas only architecture." Launching in Texas first limits which utilities we sign first. It must never lock the design into Texas law.

**Kyle's rulings are correct and do not change.** What changes is where they live. A statutory or tariff rule has to be data, held per jurisdiction and service type and dated by when it takes effect. The code implements general mechanisms that read that data. Texas is then just the first set of rows seeded and tested.

This session's patch broke that. I defended the hardcoding with "Texas-only scope", and Ryan called it dangerous for expanding beyond Texas. See the memory `launch-scope-is-not-architecture-scope`.

**Next session's task:** a full and thorough audit of the whole system for Texas-only architecture. It comes before any further work on A-2.

## Goal of the next session

Produce an audit that lists every place the system encodes one state's law in structure instead of per-jurisdiction data. For each place, give:
- **where it is:** file, patch, and object (table, column, CHECK, function, trigger, view);
- **the rule** it encodes, and its source (a Kyle ruling code or a statute clause);
- **how it is held today:**
  - (a) per-jurisdiction data already, correctly;
  - (b) data, but only in a shape Texas uses;
  - (c) hardcoded in a CHECK list, trigger or function logic, or an enum;
- **what another state could need** that the current shape can't express;
- **the fix it needs, and its size**, before any redesign starts.

Write it for Ryan in plain language, per the memory `explain-jargon-in-the-question`. He said "you might as well be speaking jibberish" about reviewer labels and round shorthand.

## Scope of the audit

- `sql/tu.sql` (23,452 lines, through -12) and each patch under `sql/` (`v5.4.0-00` … `v5.4.2-13`; 23 files).
- The docs that state rules as architecture: `CONTEXT.md`, `INVESTIGATION-BRIEF.md`, `TECH-STACK-DISCUSSION.md`, `application/`, and GBM's `application/` briefs and decision records (Kyle's rulings, CCK, the parity plan, the invariant register).
- `ui-concepts/` fixtures and schemas (`schemas/enums.ts`, `models.ts`). Kyle's newest commits added a Payments tab, AR aging and a rate editor there. Check them for Texas-only enums or assumptions.

## Known Texas-hardcoded items so far (from v5.4.2-13 alone; a starting list, not the audit)

| Where (v5.4.2-13) | What is locked in |
|---|---|
| `backbilling_cap_rules_cause_check` and `meter_correction_cases` cause CHECK | Texas §7.45's eight error causes, as a closed list |
| `correction_run_targets_backbill_cause_check` plus `enforce_backbilling_gate_issue()` | Void-and-reissue is allowed for `rate_misapplication` only (R-33: Texas sends meter errors to an adjustment) |
| `backbilling_cap_rules_billable_scope_check` | The window formulas are the Texas clause shapes (`months_from_anchor`, `shorter_of_months_or_last_test`) |
| Fast-meter refund duty (case direction logic, the `meter_fast_findings_without_case` view, the refund reach of R-37(a)) | A mandatory refund on a fast meter, written in code |
| R-36 supervisor gate (`meter_governing_test().supervisor_gate`, `meter_correction_approvals`) | Kyle's transitional sign-off, as a fixed condition |
| `regulatory_class_mode`, protected / unprotected | Texas's "residential and small commercial" protection, and the CCK-14 default |

**Already correct, and a model for the rest:** -12's meter accuracy threshold. It is per state and service type, dated by when it takes effect, platform-held, and Texas's 2.0% is just a seeded row. The cap table's month *numbers* are also data, keyed by jurisdiction, with a NULL row as the state default.

**To check in the landed patches:** these are suspects, not findings.
- Tax and franchise fees (-09).
- Regulatory surcharges and riders (-07, -08).
- WNA, the weather adjustment (-03).
- The PGA gas cost factor (-06).
- Account lifecycle, deposits and disconnection (-06).
- Cutover and legacy handling.
- The `state_code` and `jurisdictions` model itself: GBM `application/jurisdictions-shared-place-modelling-2026-09-22.md`.

## Completed (this session)

- [x] Pulled Kyle's 4 `ui-concepts/` commits (payments, lists, AR aging, rate editor). They are UI only, and none touches `sql/`.
- [x] Restarted `tally-pg`. It had exited with code 255, which is a Docker restart, not a crash.
- [x] **Review round 5** (the r5 hash was `d0873150`, sent to fresh Fable and Opus). Both reviewers said "not yet, narrowly".
- [x] **r6** (`03c5ffa6`, committed as `36d2115`), which folded both reviewers' findings:
  - Meter scope now reads deployments, bounded by the voided bill's `first_issued_at`.
  - Units against a voided bill the correction does not replace: usage may not rise.
  - Battery group Q (Q1–Q6); M73–M83; fence-and-race F1/F2.
- [x] **Review round 6**, a targeted look at the gate only:
  - **Fable:** "sound enough to mirror", with U4/U5 stated.
  - **Opus:** "not yet, narrowly", on S4.
- [x] **r7 working fixes** (NOT frozen, NOT sent; committed as `570d437`):
  - **S4:** the premises of a voided bill with no premise honour a removal only if it was on record before `first_issued_at` (Q7, M84).
  - **U:** both units tests count lines of unknown usage (Q8, M85, M86).
- [x] **Verified on the r7 working copy:**
  - strict apply ×2 clean;
  - **battery-13 146 PASS**;
  - **all 84 mutations caught** at their named checks;
  - **fence-and-race A–F PASS**;
  - regressions **28 / 58 / 41 / 116**.
- [x] Memory: `launch-scope-is-not-architecture-scope` (new); `explain-jargon-in-the-question` (expanded to cover every status update).

## Not Yet Done

- [ ] **The audit** (above). Do it first.
- [ ] **A-2 / v5.4.2-13:** do not merge it. After the audit, redesign it: keep the mechanism (case, evaluation, evidence fingerprint, freeze, holds, approvals, and the rule that "charging more for billed days needs a legal basis on record") and move the law into a per-jurisdiction rule set. Texas's behaviour must stay identical, with the battery as proof.
- [ ] Fable's **U4**, which awaits Ryan's call. The gate's customer leg reads `service_locations.customer_id` as it is now, and tally_app may rewrite it. Reassigning a premise to the customer lets a meter with real history there carry an extra charge. The options:
  - state it in R21;
  - fence it with a DB-stamped `customer_recorded_at`.

  I recommended stating it, after Ryan asked who could realistically exploit it: only the utility's own app or staff, through a deliberate and visible act.
- [ ] Fable's **U5**, which goes in R21. Migrated bills carry historical `first_issued_at` but load-time deployment `created_at`, so legacy consolidated rebills refuse until the migration backdates deployments.
- [ ] A **stopping rule for hardening**, proposed but not confirmed by Ryan. The database blocks easy, single-step mistakes. Deliberate multi-step manipulation becomes a written known limitation. There are no open-ended review rounds.
- [ ] Unchanged from before:
  - Kyle's OQ-1 brief is still unsent;
  - -14 (delivery) waits on OQ-1;
  - Workstreams A and B: the UI direction, the 229 tenant-blind FKs, A-8, A-10, Wave 4, re-grades, scenarios, wiki ingestion A–BM.

## Failed Approaches (Don't Repeat These)

- **Treating "Texas-only launch" as licence to hardcode Texas law.** It went into CHECK lists and trigger logic, and it makes a second state a redesign. Ryan: "conflated two things… dangerous for us to now expand beyond Texas." Use per-jurisdiction, date-effective, platform-held rule rows; -12's accuracy threshold is the model.
- **Open-ended adversarial review against tally_app.** Six rounds on one function. Each round found a narrower, more contrived path. Set the stopping rule above before any further review.
- **Fable's `voided_at` bound (round 5).** The caller picks the moment of the void: insert a deployment, then void. Fence-and-race F1 fails under it. Use `first_issued_at`, which is DB-stamped and write-once.
- **Fable's lineage skip (round 5).** It re-admits a units rise laundered through a downward reissue: 50u $100 → 100u $80 → 100u $200 (Q5, M81). Use "usage may not rise" against every voided bill the correction does not replace.
- **Opus's `meters.location_id` legs (round 5).** They were redundant with the deployment legs, so a mutation removing them went uncaught. Read deployments only.
- **Fable's `service_locations.updated_at` bound for U4.** Any address edit would refuse legitimate rebills.
- **Harness traps met this session:**
  - Battery fixtures created in one transaction tie `created_at` with `first_issued_at`. So N2 (e2), P (e1) and Q (M-L3-B, M-L2) backdate their deployments as owner, as O3 already did.
  - Without the backdate, the new customer leg masked M72.
  - Opus had to move its probe chains to 2025-10 and 2025-11, because June and July collide with Q4/Q5's own L3 chains.

## Key Decisions

| Decision | Rationale |
|---|---|
| Launch scope ≠ architecture scope (Ryan) | Statutory rules become per-jurisdiction data; the rules themselves don't change |
| A-2 paused, not merged | It is not in `tu.sql` yet, so restructuring now is cheap. `tu.sql` is append-only |
| Both meter-scope legs are bounded by the voided bill's `first_issued_at` | DB-stamped and write-once; `voided_at` is caller-timed |
| Against non-replaced voided bills, usage may not rise | Admits misread-down-then-reprice (Q4); refuses laundering (Q5) |
| The units tests count unknown-usage lines | `sum()` skips NULL, so a $300 line of unknown usage matched |

## Current State

**Working:**
- The r7 working copy of `sql/v5.4.2-13-backbilling-caps.sql`: 3,755 lines, md5 `db9ba40ee953b8db8b93da9b76dc9e1d`. The md5 changed only by a header comment after the 146 PASS run.
- `battery-13.sql`: 1,779 lines, md5 `9e7126c6ee91e38dec0bad41663ecd1a`.
- `mutations-13.py`: 84 mutations, md5 `3626ede2…`.
- `fence-and-race-13.sh`: md5 `87c0c898…`.

**Deployed:** `tally-pg` is running. Only the database `tally` exists (the -12 build); the scratch clones were dropped.

**The patch header is honest:** it says U4/U5 are NOT yet in R21.

**Uncommitted changes:** none after this wrap-up commit.

## Resume Instructions

1. Fetch both repos, and check GBM for Kyle's commits (memory `fetch-gbm-before-orienting`).
   ```sh
   cd ~/code/tally-utility && git pull --ff-only
   cd ~/code/gas-billing-memory && git fetch && git log --oneline HEAD..origin/main
   ```
2. Start `tally-pg` if it has stopped: `docker start tally-pg`, then `docker exec tally-pg pg_isready -U tally -d tally`. The audit is mostly reading; the database is only needed to confirm catalog facts.
3. Run the audit.
   - Consider parallel Explore agents: one per patch group, one for the docs, one for `ui-concepts`.
   - Each one reports object-level findings in the (a)/(b)/(c) classes above.
   - Merge the findings into one document.
   - Useful catalog queries:
     - every CHECK with an `ANY (ARRAY[...])` list;
     - every function whose body names a statute, `Texas`, `TX` or `§`;
     - every column or table keyed by `state_code` or `jurisdiction_id`, versus the ones that should be.
4. Present it to Ryan in plain language, with a recommendation on the shape of the per-jurisdiction rule model. Then plan the A-2 restructure on that model.

## Warnings

- **`tu.sql` is APPEND-ONLY.** Mirror a patch BODY only, then `diff` it.
- **Do not send r7 for review, and do not merge -13,** before the audit and the redesign.
- **Only database `tally` exists.** Clone it with `TEMPLATE tally`. There is no host port, so use `docker exec … -U tally`.
- `fence-and-race-13.sh` uses a fixed DB name (`fr13x`), so only one run at a time.
- Never `git add -A` in GBM. Log GBM canonical changes in `application/wiki-ingestion-pending.md`.
- Reviewer agents from this session (`fable-r5`, `opus-r5`) do not carry over. Spawn fresh ones: `general-purpose`, `model: fable` or `opus`, with "send the report to main as several messages under ~3 KB".
