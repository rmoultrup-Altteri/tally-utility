# Review brief — v5.4.2-13, round 3 (frozen)

| Artefact | Lines | md5 |
|---|---|---|
| `sql/v5.4.2-13-backbilling-caps.sql` (= `review/patch-13-frozen-r3.sql`) | 3516 | `d991df9218585788363604f0679add62` |
| `tests/v5.4.2-13/battery-13.sql` (= `review/battery-13-frozen-r3.sql`) | 1395 | `74ea8e45a3fd5f5657925ff07e6e51f4` |
| `tests/v5.4.2-13/fence-and-race-13.sh` | — | `069f8bbc7f7e1acccdca4bd6658c96bb` |

Same rules as before: review the frozen copies, edit nothing in either repo, and put every repro under your scratch directory. Name clones `fab13_*` / `op13_*` and drop them when you're done. Send your report to "main" as several messages, each under about 3 KB.

## Verification (re-run it)

- Strict apply ×2 is clean and AC-32 passes.
- **battery-13: 132 PASS.** That's round 2's 128 plus group **N**, which covers the round-2 guards that fit in one transaction.
- Regressions: 28 / 58 / 41 / 116.
- **67 planted mutations**, all caught at the check written for them. M64–M68 are new; M09 was re-pointed at the scoped comparison.
- `fence-and-race-13.sh`: **A, B, C1, C2, D, E all PASS**.
  - **D**: the fast meter is pulled after its test, with a backdated removal set through `meters.status`, and the freeze still refuses 31 days.
  - **E**: a transaction locks a case and then records a test on its meter, racing a correction on that meter, and both commit.
  - D fails without the removal stamp, and E deadlocks with the round-2 trigger name.

## Round-2 findings and dispositions

| Finding | Reviewer(s) | Disposition |
|---|---|---|
| Backdated removal after the finding, on the case's own meter (directly or via `meters.status` / `sync_meter_deployments`), or on another meter's live deployment | Opus N1, Fable F1 (both HIGH) | `meter_deployments.removal_recorded_at` is stamped by the guard on NULL → date for tally_app, and immutable. `uncovered_days` treats a removal recorded after the fence as not having ended the deployment, in both legs. Corroboration requires `coalesce(removal_recorded_at, created_at) <= fence`. (N1; fence-and-race D) |
| Reissue gate compared whole bills of different scope: a consolidated bill's over-refusal and a lineless consolidated bill's bypass | Opus N2, Fable F2 | Each matched voided bill is compared at the scope it was found by. A shared meter compares the two bills' lines on those meters, plus the new bill's money that no line carries. Anything else compares the whole charge. A new customer leg handles bills with no premise. **Fable's per-day proration was declined**: a cheap new month would dilute an overcharge below the old daily rate. The remaining refusals are stated in R21. (N2, N3) |
| FOR SHARE handshake deadlock | Opus N3, Fable F3 | The trigger was renamed `a0_…` so it fires before -12's meter lock. (fence-and-race E) |
| NULL usage admitted a zero correction | Opus (LOW) | Unknown usage counts as usage. (N4) |
| R6, R15, R16 and R21 overclaimed | both | Reworded. R6 names the meters-only route to a pre-finding fabrication. |

On r3, your round-2 repros behave as follows:
- Opus `s_gap_removal`: refused, 31 days.
- Opus `s_r16_other`: window stays 2025-12-15, uncorroborated.
- Opus `s_consol` (a): refused. **(b), a parent re-summing a live correction, is still refused. That is stated in R21 until consolidation is defined.**
- Fable q7b: refused, 31 days.
- Fable race-q4: both commit.

## What I want from round 3

1. Confirm the three fixes against your own repros, and look for siblings:
   - Can a removal still end a deployment for a finding by any route other than the NULL → date write? For example, an owner-looking write, `meters` updates that close and reopen, or a new deployment row closing the gap.
   - Does the scoped comparison leak? For example, splitting the voided meter's charge across two meters, an excess carried by a line with no meter, or a mix of shared and unshared meters.
2. Is anything in the revision newly wrong?
3. Verdict: **"sound enough to mirror"** or **"not yet"**. Both of you said round 3 should be mirrorable once these are in. If you still find something, say whether it blocks mirroring or can ride as a stated residual.
