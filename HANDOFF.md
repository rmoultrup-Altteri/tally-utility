# Handoff: v5.4.2-23 (cash) — r2 reviewed "not yet"; r3 waits on Kyle (K-10)

**Generated**: 2026-10-18, about 6:40 PM CDT
**Branch**: `main` in both repos. tally-utility is at `852e68d` plus this wrap-up, pushed. GBM had no new commits at the start of the session.
**Status**: Blocked on Kyle. Ryan, 2026-10-18: "let's wait on Kyle" (r3 is not to start before his answer).

## Goal

Reach the C# core build. Ryan's gate, in order:
1. schema parity with CI-001…CI-135 (**we are here**: 78 of 135);
2. scenarios and a test strategy;
3. a phase plan;
4. build.

Wave 2 is -22 (landed) and -23, cash (M, X, A, C; meaning-changing). -24 (U unmatched cash, L agency pledges) follows -23.

## Completed (sessions of 2026-10-16 evening through 2026-10-18)

- [x] **-23 triage** (`0cb882a`). Cash was split into -23 and -24 (Ryan: "split it, go with the default"). **Design:** `application/wave2-build-2026-10-15/v5.4.2-23-design.md`.
- [x] **-23 r1** (`d7d0d82`…`3d329c2`): draft; Ryan kept the 1,000-deep reversal bound; 71/71 mutations; frozen.
- [x] **Round 1:** Opus, Fable and Codex all "not yet" (`3adeb8c`). Codex's probes were run, and every predicted blocker was confirmed.
- [x] **Kyle brief** on a refunded payment that then bounces: `application/kyle-brief-2026-10-17-refund-then-bounce.md` (`ff402b3`). Ryan sent the Slack message. It holds three questions; the open ones are K1 and K2 below.
- [x] **r2 plan** (`6b96f47`): `application/wave2-build-2026-10-15/v5.4.2-23-r2-plan.md`. Every round-1 finding is settled by a standing rule.
- [x] **r2 implemented** (`6452119`, `e72a311`):
  - `check_cash_source(kind, id, row_created_at, purpose, on_date)`: lock first, then read and judge the source;
  - births: a payment is born pending, a credit active;
  - exact causes for every status move;
  - `cash_arrival_stands`, and the bounce-row guard in `enforce_ledger_reversal`;
  - donations and escheats are draws;
  - `status_recorded_at`; positions gated on `first_issued_at`;
  - only the reversal types, `adjustment` and `write_off` name an entry (-22 R12n's nested write-off).
- [x] **Tests:**
  - battery-23: 168 checks (R1–R18b, LC3, R4 rewritten, R4a);
  - races: CR1–CR13, 18 results (CR3 reworked; CR9–CR13 new);
  - mutations: 110/110 (10 re-anchored, N72–N110 new);
  - -19 and -21 fixtures post their money on the ledger;
  - `tests/ci.sh`: all pass.
- [x] **r2 frozen** (`8570e95`):
  - `tests/v5.4.2-23/review/review-brief-23-r2.md`, with six md5s;
  - the patch header updated (R2 closed, R9–R11, "Open with Kyle", lock order restated);
  - DEPLOY-VERIFICATION: tally_app's `statement_timeout` (R11).
- [x] **Round 2** (`852e68d`): all three "not yet".
  - Reviews: `tests/v5.4.2-23/review/{opus,fable,codex}-r2.md`.
  - Codex's 14 probes were run; outputs are in `codex-r2-probes/out/`. **All seven Codex blockers reproduced.**
- [x] **Go-live dashboard refreshed:**
  - P1 is at 78/135;
  - parity is after -22;
  - K-10 (this Kyle question) added to the decision queue;
  - likely ready-to-onboard is still 2027-06-16.

## Not Yet Done

- [ ] **Wait for Kyle's K-10 answer**, then write the r3 plan from the round-2 findings (merged below).
  - Fetch GBM first: Kyle may push his answer there.
- [ ] **r3, under either answer:**
  1. **Refund posting tests first.** No battery, race or mutation anywhere posts a refund on the ledger (Fable). Opus S2: removing the refund exemption left the battery at 168/168.
  2. **K2 as stated:** a bounce (nsf or reversed, the row or the move) is refused while a refund of the payment is pending. All three reviewers caught that no code does this. -19's P5c fixture relies on the admission and must change.
  3. **One arrival entry per source:**
     - a credit gets exactly one `credit_issued` row, at minus its amount;
     - a payment gets one posting row;
     - the void must cancel *the* arrival entry.

     Opus S1, Codex B3, Fable S.
  4. **Donations:** a donation that is undone still counts against the credit (Codex B5). Cross-customer donations and escheats are counted as draws (Fable S).
  5. **Escheat remittance and the freeze:** a remittance dated in a closed period is admitted (Codex B6). It needs `enforce_accounting_freeze` or an equivalent.
  6. **Voiding an overpayment credit returns money to an ended payment** (Codex B7).
  7. **A refunded payment's refund undone on the ledger** while both statuses stand (Opus B4).
  8. **A payment posted by a `refund`-typed row** escapes the bounce guard (Opus B1).
  9. **A draw recorded before its source's posting entry** (Fable S, a two-session race).
  10. **A refund that fails after its source is `refunded` has no exit** (Fable S).
  11. **The payment position ignores the payment's own status:** an nsf payment reads remaining 20 (Fable S).
  12. **Unpinned facts:**
      - the refund sign CHECK;
      - `original_amount > 0`;
      - the escheat stamp trigger;
      - tally_app's EXECUTE on the cash functions;
      - an extra permissive approvals policy.

      Fable S; Codex probe 08.
- [ ] **r3, depending on K1:**
  - **Answer A** (a refund is its own movement): delete the refund exemption from `enforce_ledger_reversal` and `cash_arrival_stands`, and drop `refund` from X1. Per Fable, only the two X1 CHECK strings in the invariants and mutation N77 change.
  - **Answer B** (a refund undoes the payment): rewrite the exemption on the act, not on `reference_id`:
    - a `refund` row at the refund's amount, naming that refund's payment;
    - one row per refund.

    This fixes Opus B2, Codex B2 and Fable B1, and also Opus B5/Codex B4/Fable B2: a credit's refund (including an overpayment credit's) must be postable under its own arrival entry.
- [ ] **After -23 mirrors:**
  - re-grade the parity measurement;
  - add a GBM manifest section;
  - add a DEPLOY-VERIFICATION mirror entry;
  - update the memory record.
- [ ] **While waiting, next work (Ryan agreed to the order, 2026-10-18):** the wave-3 source inventory (disputes and collections decision records: CI-074, 067, 069, 075, 071, 054's dispute side). It is reading only and independent of K-10. -24 waits until r3 settles.
- [ ] **Carried over:**
  - the reply to Kyle on D-2's location;
  - the -05 defect (`meters_last_validated_actual_reading_id_fkey`);
  - -21 R9;
  - the R-03 scoping;
  - `pga_monthly_reconciliations.deferred_balance_after`;
  - the backbilling tariff table;
  - the GitHub Actions bump;
  - the Florida 25-7.083 text;
  - the waiver-determination rewrite;
  - low-confidence measurement rows;
  - the -15 r8 follow-ups;
  - gate steps 2–4.

## Failed Approaches (Don't Repeat These)

- **An exemption keyed on a caller-written reference.** The bounce guard exempted any row whose `reference_id` pointed at one of the payment's refunds. A +100 adjustment citing a 0.01 refund undid the payment's money while it was still applied. Key the exemption on the act: the row's type, amount, and the refund's own lineage. Or remove it (K1 = A).
- **A guard whose exempt path no test exercises.** Nothing in five batteries posts a refund on the ledger, so the exemption and the refund's posting row ran in no test. Every guard branch, the exempt one included, needs a fixture that takes it (memory `checks-narrower-than-their-claim`).
- **Stating a default in the header and brief without code behind it.** K2 ("refused until the refund is voided") was written in three documents, and the patch admitted the bounce. When a header states a behaviour, add the battery check in the same change.
- **A test that names the wrong row.** The old R4 named Q1's nsf row for Q2's move, so it was refused for the wrong reason, and mutation N76 slipped past it. Name the row the label describes, and use a rolled-back DO block when the setup needs a row the later fixtures can't coexist with.
- **Mutations named at a check that no longer runs first.** After r2 moved the guards, N31 and N34 were caught first by M3f2 and M3h2, and N32's race (CR3) no longer exercised the move's lock. Rename to the sub-check that catches it, or add the race (CR13). Never loosen the runner.
- **Earlier failures still hold:**
  - barrier polls need `pg_stat_clear_snapshot()`;
  - the lock order is a rule, not a list;
  - never edit the battery during a mutation run;
  - `codex exec` with the prompt as an argument needs `< /dev/null`.

## Key Decisions

| Decision | Rationale |
|---|---|
| Wait for Kyle before r3 (Ryan, 2026-10-18) | Under K1 = A the refund exemption, and the three blockers hanging on it, are deleted rather than fixed |
| r2 went to review before Kyle answered (Ryan) | Most of r2 is independent of the refund question; the reviews found holes that need fixing under either answer |
| write_off may name an entry | -22's nested write-off (R12n): part of a recovery that came back is written off under it |
| A payment is born pending; posted is a move naming its entry | Q1 (a) and guard the act: a born-posted payment had no posting entry behind it |
| The test helper `post()` fills `effective_date` from `payment_date` | It keeps fixtures short; the -19 rule that posting needs an effective date is tested in -19 P1 |
| `statement_timeout` for tally_app at deployment (R11) | A 1,000-deep chain posted in one statement holds the tree and the head for minutes; the value is the deployment's choice |

## Current State

**Working:**
- tu.sql through -22;
- `tests/ci.sh` all pass with -23 r2 pending;
- -23: battery 168, races 18/18, mutations 110/110.

**Broken (known, in r2):** the round-2 findings above. Repros:
- `tests/v5.4.2-23/review/codex-r2-probes/*.sql`, with outputs in `codex-r2-probes/out/`;
- Opus's and Fable's repros are in their review files.

**Uncommitted changes:** this wrap-up only (HANDOFF.md, CHANGELOG.md, application/roadmap/*.json, memory).
**Scratch DBs:** `qk` and `qr` in tally-pg (throwaway; drop them freely).

## Code Context

```sql
-- every draw: purposes application | undo | overpayment_credit | refund | donation | escheat
public.check_cash_source(p_kind text, p_id uuid, p_row_created_at timestamptz, p_purpose text, p_on date) RETURNS void
--   RC only (25000) -> source lock -> read source (NOT FOUND: 23503) -> purpose table -> date -> cash_arrival_stands
--   -> recorded order vs source (40001 / 23514 chosen time) -> vs later draws -> cap at every date (23514 "more than its N")
public.cash_source_draws(p_kind text, p_id uuid) RETURNS TABLE(id uuid, on_date date, amount numeric, created_at timestamptz)
public.cash_arrival_stands(p_kind text, p_id uuid) RETURNS boolean   -- K1 exemption lives here and in enforce_ledger_reversal
-- lock order: head -> (reversal) tree root -> source | (application) tariff row shared -> source -> line
--   status move: own row -> source; refund's move that could end its source -> that source's lock
```

```bash
# quick loop used this session (scratchpad; recreate if gone): clone tally -> qk, strict-apply -23 twice, run batteries
#   q qk -f tests/v5.4.2-NN/battery-NN.sql
# race script against a throwaway clone (commits rows):
bash tests/v5.4.2-23/races/cash-23.sh <db>
python3 tests/v5.4.2-23/mutations-23.py [N01 ...]      # ~20 min for all 110; uses fixed db m23
```

## Resume Instructions

1. `git pull --ff-only` in tally-utility, and `git fetch` in `../gas-billing-memory`. Look for Kyle's K-10 answer there and in Slack (ask Ryan).
   - Expected: tally-utility at the wrap-up commit after `852e68d`.
2. `bash tests/ci.sh`.
   - Expected: `ci: all pass`.
   - If `tally-pg` is missing: `bash tests/ci.sh --build`.
3. **If Kyle has answered:**
   - write `application/wave2-build-2026-10-15/v5.4.2-23-r3-plan.md` from "Not Yet Done";
   - implement it, writing the refund-posting tests first;
   - re-run CI and the mutations;
   - freeze r3 and send it to all three reviewers (memory `all-three-reviewers-before-mirror`).
4. **If not:** start the wave-3 source inventory (memory `source-inventory-first-triage-by-rule`). Do not start r3 (Ryan's call).

## Warnings

- **Never edit the frozen review copies** (`tests/v5.4.2-23/review/*-frozen-r*.{sql,sh,py,diff}`) or tu.sql's mirrored bodies.
- **Revoke TEMP from PUBLIC, `tally_app` and `tally_core` after every `CREATE DATABASE … TEMPLATE`.**
- **Don't edit tests while `mutations-23.py` runs.** It re-reads the battery for every mutation.
- **The -23 header says K2 is "refused (now)", but the code admits it.** That is a known r2 blocker, not a decision.
- **Codex:**
  - only under nvm v24.15.0 (`export PATH="$HOME/.nvm/versions/node/v24.15.0/bin:$PATH"`);
  - run it as `codex exec -s workspace-write -C <repo> -o <final.txt> "$(cat prompt)" < /dev/null`;
  - a "Reading additional input from stdin..." line followed by the prompt echo is normal.
