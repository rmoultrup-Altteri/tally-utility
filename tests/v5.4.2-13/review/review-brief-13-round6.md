# Review brief — v5.4.2-13, round 6 (frozen) — targeted confirmation of the reissue gate

| Artefact | Lines | md5 |
|---|---|---|
| `sql/v5.4.2-13-backbilling-caps.sql` (= `review/patch-13-frozen-r6.sql`) | 3727 | `03c5ffa63dc23d369cf93d815628b6ae` |
| `tests/v5.4.2-13/battery-13.sql` (= `review/battery-13-frozen-r6.sql`) | 1715 | `b330c42742e7c9e707cc5c2f33f20b00` |
| `tests/v5.4.2-13/fence-and-race-13.sh` | — | `87c0c8985446ed58733b9107a3d6d833` |
| `tests/v5.4.2-13/mutations-13.py` | — | `249e2788905079182319580212cfe900` |

The rules are the same as in rounds 1–5 (round-1 brief, "Rules of engagement"). In round 5 both reviewers said "not yet, narrowly". Both said a targeted confirmation of the gate function would do, so this round is scoped to the reissue gate: `enforce_backbilling_gate_issue()`, the new `backbilling_units_not_above()`, and R21. Nothing in the case, evaluation, freeze or hold machinery changed.

## Verification (re-run it)

- Strict apply ×2 is clean and AC-32 passes.
- **battery-13 passes 144 checks**: round 5's 137 plus group **Q** (Q1, Q1b, Q2–Q6).
  - Two fixtures were backdated, as O3 already does, so each check exercises one guard alone:
    - **N2** (e2): with a same-transaction created_at, the new customer leg would refuse N2's legitimate bill.
    - **P** (e1): the new customer leg would otherwise mask M72.
  - The frozen r5 patch fails the new battery at Q1.
- Regressions: 28 / 58 / 41 / 116.
- **81 planted mutations**, all caught at the check written for them:
  - M73–M75 are re-pointed at the r6 code.
  - M76–M83 are new. M81 is Fable's proposed lineage skip; M83 is r5's equality rule.
- **fence-and-race-13.sh A–F PASS.**
  - **F1** (new): a deployment written after the voided bill went out, but before its void, does not excuse a rebill. It fails when the bound is `voided_at` (Fable's proposal).
  - **F2** (new): a real move to the customer's other premise, in natural order, issues. It fails when no removal is honoured (M78). This is the case Opus could not measure.
  - Its DB name is still fixed (`fr13x`), so only one reviewer should run it at a time.

## Round-5 findings and dispositions

| Finding | Disposition |
|---|---|
| Opus HIGH: "a meter at the voided premise" read only a deployment overlapping the new period, so it was beaten by a backdated removal, a meter onboarded today, or an inactive meter | Leg (i): a meter counts if it was EVER deployed at one of the voided bill's premises. The one exception is a removal before the new period that was on record (`coalesce(removal_recorded_at, created_at)`) before the voided bill's `first_issued_at`. (Q1, Q1b, F2; M73, M77, M78) |
| Opus MEDIUM: a voided bill with no premise left leg (i) empty | The voided bill's premises are its header plus the premises of its own line meters' deployments during its period. (Q2; M76) |
| Fable U1 HIGH: "a meter of this customer" read `meters.location_id`, so a relabel or an inactive meter escaped. A deployment inserted later (R16) beat Fable's own v1 | Leg (ii): a meter is the customer's only through a deployment at one of the customer's premises that overlaps the new period and has `created_at` < the voided bill's `first_issued_at`. Fable proposed `voided_at`, but the caller picks that moment: insert a deployment, then void. This was measured at F1 and declined. (Q3, F1; M79, M80) |
| Opus's fix also counted `meters.location_id` labels | Dropped. It was redundant with the deployment legs, so a mutation removing it went uncaught. The label is no longer read on either leg. |
| Fable U2 / Opus E: equality against a non-replaced voided bill refused misread-down-then-reprice | Against a voided bill it does not replace, a correction may not RAISE usage per meter. A meter the other bill lacks counts as a rise, and so does a quantity known on one side only. The replaced bill still needs equality. (Q4, Q6; M82, M83) |
| Fable's alternative for U2: skip the replaced bill's lineage | Declined. It re-admits Opus's laundering chain F (50u $100 → 100u $80 → 100u $200). (Q5; M81) |
| Opus F LOW: chain F was unpinned | Q5. |
| Fable U3, Opus G, and Opus's no-shared-meter note | Stated in R21. |

## What to confirm

1. Each of your round-5 repros is refused on r6. Legitimate shapes still issue: T-a2, Opus G0 (which needs deployments on record before the voided bill went out, as any real history has), Q1b and F2.
2. Look for anything newly wrong in the gate:
   - a leg that still reads a caller-written label or a caller-timed stamp;
   - a new false refusal of a lawful rebill that R21 does not state;
   - a hole in `backbilling_units_not_above()` (NULLs, meterless lines, a meter present on one side only).
3. Verdict: **"sound enough to mirror"** or **"not yet"**.
