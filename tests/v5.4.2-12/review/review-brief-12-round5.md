# Review brief — v5.4.2-12, the meter test history (round 5, confirmation)

| Artefact | Lines | md5 |
|---|---|---|
| `sql/v5.4.2-12-meter-test-history.sql` (= `review/patch-12-frozen-r5.sql`) | 1789 | `3f74a76c32710e733c0f003818c3bccf` |
| `tests/v5.4.2-12/battery-12.sql` (= `review/battery-12-frozen-r5.sql`) | 1094 | `c83e5d6b7e07c3a9d381dc03a185ce78` |

Frozen. **Do not edit any file in the repo.** Earlier briefs still govern.

Both round-4 reviewers said **"sound enough to mirror"**. This round exists
only because the fold changed code; it is a CONFIRMATION round, scoped to the
r4 → r5 delta (`diff review/patch-12-frozen-r4.sql review/patch-12-frozen-r5.sql`,
73 changed lines, mostly comments).

## The delta — four changes, all proposed and measured by the round-4 reviewers

1. **`meter_test_refresh_pointer()` writes the meter row unconditionally**
   (both). Row-version mutex: a concurrent insert under RR/SERIALIZABLE now
   fails with a serialisation error at its meter lock. Re-measured here with
   Fable's seed/A/B scenario: B `could not serialize access due to concurrent
   update`; pointer = governing = `migrated_full accurate`.
2. **Ranking key `(outcome IS NOT NULL) DESC`** after the asserted-failure key,
   before record_basis, in both readers (Fable F2). Pinned by K8d; mutation M20.
3. **The round-3 insert guard narrowed** (both: it refused legitimate rows) to
   refuse only a no-readings, non-superseding row on a date whose live
   evidence includes an ASSERTED failure without readings. K5 and K5b now
   assert "accepted, and the failure still governs both readers"; K6b pins the
   remaining refusal; mutation M15.
4. **R19 documented** (both): same-day readings rows rank by entry order; the
   comments no longer claim the as-left test governs.

Verification: strict apply ×2 clean; battery **116 PASS**; isolation 3;
regressions 28 / 58 / 41; mutations M1–M20 (less M18, folded into M14) each
caught by its named check.

## What I want

Confirm each of the four, against your round-4 repros (F1/F2/F3 and B-series
for Fable; finding 1/2 and p4 B-series for Opus). Look only for a defect the
delta itself introduced. If none: "sound enough to mirror".
