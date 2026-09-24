# Review brief — v5.4.2-13, round 2 (frozen)

| Artefact | Lines | md5 |
|---|---|---|
| `sql/v5.4.2-13-backbilling-caps.sql` (= `review/patch-13-frozen-r2.sql`) | 3376 | `9844fc48f924133068019605917f4275` |
| `tests/v5.4.2-13/battery-13.sql` (= `review/battery-13-frozen-r2.sql`) | 1341 | `ed1cbbb510c8e30947ba1210cadd9580` |
| `tests/v5.4.2-13/fence-and-race-13.sh` (new) | — | `1bbf0a90d3de0068aad796ae7b1e93be` |

The files are frozen as in round 1: review these copies, edit nothing in either repo, and put every repro under your scratch directory. The round-1 brief (`review-brief-13.md`) still holds for the patch's purpose, its authority, how to run it, and the rules of engagement. Read it if you have not.

## Verification (re-run it)

- Strict apply ×2 is clean and AC-32 passes.
- `battery-13.sql`: **128 PASS**. The 116 from round 1 plus group **M**, which has one discriminating check per round-1 finding.
- Regressions: 09 **28**, 10 **58**, 11 **41**, 12 **116**.
- **62 planted mutations** (`mutations-13.py`), all caught at the check written for them. Round-1 guards are M50–M63. M43 was retired: the frozen branch's own substance check became redundant with the general "a status change carries nothing" check, which M51 now proves at I2.
- `fence-and-race-13.sh` runs **four checks that need separate transactions**:
  - **A.** Re-pointing a case at a fresh copy of its test doesn't admit a predecessor meter entered after the finding.
  - **B.** An acquisition recorded after the finding doesn't validate a predecessor hold.
  - **C1 and C2.** A correction of the discovering test racing a freeze, in both orders. Each verifies first that the freeze alone would succeed.

  Each is proven by a planted mutation. A fails with the round-1 fence. B fails without the acquisition fence. C1 and C2 fail without the lock.

  Run it with `sh tests/v5.4.2-13/fence-and-race-13.sh`. It builds its own database, `fr13x`, and drops it afterwards. `PATCH13=<file>` runs it against another copy.

## Round-1 findings and what I did with each

| Finding | Reviewer(s) | Disposition |
|---|---|---|
| Freeze, unfreeze and withdraw skip the derived-column fence, so direction flips and tamper evidence swaps | Fable F1 (CRIT), Opus F2 (HIGH) | Fence moved first. A status change may carry only status, its stamps, withdrawn_reason and notes: a whole-row jsonb comparison, so new columns are fenced by default. (M1, M2) |
| Withdrawal while the test still finds the meter fast | Opus F1 | Withdrawal reads the latest row of the discovering test's supersession chain. (M3) |
| The discovering test's supersession is not an input; a case freezes on a corrected test; race | Fable F2, Opus F4 | `discovering_test_superseded_by` is now in the inputs; evaluation and freeze refuse it; the case surface shows it. The section-13 trigger takes FOR SHARE on the meter's cases before checking. (M4, fence-and-race C1/C2) |
| A $0 refund on every period | Fable F3, Opus F8 | Refused on a period with non-zero billed_units in a test-anchored case. (M10) |
| Deployment evidence forgeable: re-pointing moves the filter; whole closed rows can be inserted; predecessor hold unfenced | Opus F3, Fable F4a/c | **Both fixes, combined.** `meter_correction_evidence_fence()` returns the earliest recorded_at of the discovering test's chain, or of any defective test within six months before the anchor (Opus). tally_app cannot INSERT a deployment that already has a removal (Fable's option i). The predecessor hold also requires `d.created_at` and `a.recorded_at` to be at or before the fence. (M5, fence-and-race A/B) |
| An ancient predecessor corroborates an onboarding-date start | Fable F4b | Corroboration requires `removal_date >= statutory start`. (M6) |
| A completed hold still covers its days and blocks re-holding them | Opus F5 | Completed holds cover nothing; the exclusion constraint is now `WHERE status <> 'completed'`, dropped and re-added. (M7) |
| Reissue gate: exact period and location only | Opus F6, Fable F5 | **Both fixes, combined.** Overlapping days, matched by premise or by a meter the two bills share. The cost is stated as R21: a bill spanning a voided month and a new one, charging more, is refused. (M8) |
| Opposite same-day findings | Opus F7 | Refused as a discovering test while an opposite standing finding exists that day. An accurate test on the same day is still allowed. (M9) |
| Fast findings with no case | Opus (gap) | New `meter_fast_findings_without_case` view. (M12) |
| Two live cases on one test | Fable F6 | Partial unique index. (M11) |
| LOW items | both | R6, R15 and R16 rewritten; R18 (R-36 scope, for Kyle), R19 (class read as of now), R20 (meter_deployments' own FKs), R21 (spanning bill) added; hold completion locks the case; the gate's message no longer says "at this premise". Withdrawal carrying a cause change is now refused by the general status rule. |

Your repro scripts all refuse on this revision. Opus r1–r11: r2, r3 and r10b now stop at the closed-insert refusal, which is why fence-and-race A and B exercise the fence directly. Fable P1–P6: P4 stops at the closed-insert refusal, which is why M6 covers P4b directly.

## What I most want from round 2

1. **Confirm each fix against your own repro, and hunt its siblings.** In particular:
   - Can the fence be moved by any route other than re-pointing? For example, a defective test entered with an earlier date but a later recorded_at, or supersession chains that fork.
   - Can a deployment still be fabricated without inserting a closed row? For example, insert an open deployment and remove it later (R16), or use `sync_meter_deployments` via meter status changes (active → inactive sets a removal).
   - Does the whole-row comparison refuse anything legitimate, such as the -10 snapshot mutex's `updated_at` touch on a case? (Cases have none, but check.)
2. **The overlap reissue gate against the existing corpus.** Is there any legitimate issuance it now refuses beyond R21? Try a regular bill after a void with `rebill_expected = false`, and consolidated parents and children.
3. **The FOR SHARE handshake.** Look for deadlocks against evaluation (which locks the case, then reads tests), against the -12 test insert (tenant KEY SHARE, then meter NO KEY UPDATE, then cases FOR SHARE), and against a freeze.
4. **Anything new the revision introduced.**

End with **"sound enough to mirror"** or **"not yet"**. Keep each message under about 3 KB: the delivery channel truncated round-1 reports. Send the report as several messages if you need to.
