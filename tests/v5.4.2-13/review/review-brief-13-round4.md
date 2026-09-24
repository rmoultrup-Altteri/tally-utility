# Review brief — v5.4.2-13, round 4 (frozen) — confirmation round

| Artefact | Lines | md5 |
|---|---|---|
| `sql/v5.4.2-13-backbilling-caps.sql` (= `review/patch-13-frozen-r4.sql`) | 3562 | `ea35e6bb1d84502fa04405ce0e2934de` |
| `tests/v5.4.2-13/battery-13.sql` (= `review/battery-13-frozen-r4.sql`) | 1465 | `bce968a21d4f9045a13d343907a7d3c6` |
| `tests/v5.4.2-13/fence-and-race-13.sh` (unchanged) | — | `069f8bbc7f7e1acccdca4bd6658c96bb` |

The rules are the same as in earlier rounds. Both of you said round 3 was sound enough to mirror once the reissue gate's two holes were closed. This round confirms that fix, and asks whether anything in it is newly wrong.

## Verification (re-run it)

- Strict apply ×2 is clean, and AC-32 passes.
- **battery-13: 135 PASS.** That is round 3's 132 plus group **O**:
  - **O1:** at the same premise, $60 on the voided meter plus $90 on another meter, or plus a $300 meterless line, is refused.
  - **O2:** a $500 duplicate issued beside the live $100 bill, then both voided, does not excuse a $400 rebill.
  - **O3:** a backdated removal written in the fast test's own transaction does not excuse its 31 days.
- Regressions: 28 / 58 / 41 / 116.
- **70 planted mutations**, all caught at the check written for them:
  - M69 through M71 are new.
  - M09 and M66 were re-pointed.
  - M71 mutates both legs of the uncovered-days test, because either leg alone refuses O3.
- `fence-and-race-13.sh`: A through E all PASS, unchanged.

## Round-3 findings and dispositions (both reviewers found both gate holes)

| Finding | Disposition |
|---|---|
| At the same premise, meter scope let the extra ride on another meter's line (Fable S2a) or a meterless line (Fable S2b, Opus `s_meterless`) | A bill matched by the same premise, or by the bill it names in `replaces_invoice_id`, compares the **whole charge**. Meter scope applies only to a shared-meter match at another premise or with no premise. In meter scope, the new bill's **meterless lines** count as unattributed money, alongside amount_due above all lines. (O1, M69) |
| "More than EVERY matched voided bill" let a higher voided bill excuse a rebill: a decoy (Opus `s_decoy`), a one-day overlapping mis-key (Opus `s_decoy2`), or a duplicate issued beside the live bill (Fable S3) | **More than ANY** matched voided bill is an increase, which is Fable's rule. Opus proposed a per-scope maximum plus a covering-bill rule; I didn't take it, because a same-premise duplicate covers the period and would still excuse the rebill (S3). The cost, stated in R21: re-issuing a lawful correction after it is itself voided needs its cause again. (O2, M70) |
| Fable F3a: a removal written in the test's own transaction ties with it | A removal the application recorded must be **strictly before** the fence. An owner-loaded row, which has no stamp, keeps `<=`. This applies in corroboration and in both uncovered-days legs. (O3, M71) |
| Fable F3b: the lock order rests on trigger-name sort | Stated in R15 as an invariant a later patch must keep. |
| Fable F3c–e, Opus cosmetic | Notes, and the refusal message now always carries the prior figure. |

All of your round-3 repros are refused on r4:
- Opus: `s_decoy`, `s_decoy2` and `s_meterless`.
- Fable: `probe-s` (S2a, S2b, S3) and `probe-q7` as a single transaction.
- Every earlier repro still behaves as disposed.

## What I want

1. Confirm the gate changes against your repros, and look for siblings in the whole-versus-meter split. For example: a same-premise match reached only through the customer leg, a `replaces_invoice_id` naming a bill at another premise, or amount_due below the lines.
2. Tell me anything the revision made newly wrong.
3. Give your verdict, **"sound enough to mirror"** or **"not yet"**, and say whether anything remaining blocks mirroring.
