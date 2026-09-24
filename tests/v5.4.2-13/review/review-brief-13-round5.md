# Review brief — v5.4.2-13, round 5 (frozen) — confirmation round, NOT YET SENT

| Artefact | Lines | md5 |
|---|---|---|
| `sql/v5.4.2-13-backbilling-caps.sql` (= `review/patch-13-frozen-r5.sql`) | 3619 | `d0873150fb758cb2a490ed083c691d96` |
| `tests/v5.4.2-13/battery-13.sql` (= `review/battery-13-frozen-r5.sql`) | 1536 | `535815cde79183647ff06c0e50648c67` |
| `tests/v5.4.2-13/fence-and-race-13.sh` (unchanged) | — | `069f8bbc7f7e1acccdca4bd6658c96bb` |

The rules are the same as in rounds 1–4. In round 4 both reviewers said "not yet, narrowly": each would call the patch sound enough to mirror once the reissue gate's siblings were folded in. This round folds all four.

## Verification (re-run it)

- Strict apply ×2 is clean and AC-32 passes.
- **battery-13 passes 137 checks.** That's round 4's 135 plus group **P**:
  - **P1:** three bills are refused.
    - one with the customer's other premise on the header, $150 against $100;
    - one with no premise and a second meter at the voided premise;
    - one with no premise and another tenant's meter.
  - **P4:** a correction that exceeds a voided bill it doesn't replace must match that bill's units.
- Regressions: 28 / 58 / 41 / 116.
- **73 planted mutations**, all caught at the check written for them.
  - M72–M75 are new.
  - M66 was re-pointed.
  - M69 was retired into M72: restoring the round-3 condition is M72's own test.
- fence-and-race-13.sh: A through E all PASS.

## Round-4 findings and dispositions

| Finding | Disposition |
|---|---|
| Fable T-d: meter scope keyed on "another premise" read the caller-chosen header | Meter scope now needs a new bill with **no premise**. A bill naming any premise compares whole charges. Cost stated in R21. (P1, M72) |
| Opus Q1: a no-premise bill carried the extra on a second meter AT the voided premise | In meter scope the new side also counts lines on any meter deployed at the voided bill's premise during the new period. (P1, M73) |
| Fable T-a: under a no-premise header a line may name any meter, another tenant's included | In meter scope the new side also counts lines on a meter not at one of the customer's premises; an invisible meter counts too. The tenant-blind line FK is stated in R20. (P1, M74) |
| Opus Q2: the units test read only the replaced bill | Every other voided bill the new bill exceeds must also match its units. (P4, M75) |

All four round-4 repros are refused on r5: Fable probe-t T-d and T-a, Opus s_sib and s_sib_b. T-a2 (N2's own shape) still issues, by design.

## What to confirm

Confirm the four folds, look for anything newly wrong, and give a verdict: **"sound enough to mirror"** or **"not yet"**.
