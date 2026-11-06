# Review brief: v5.4.2-27 r4 — a credit applied to a bounced payment's shortfall (AC-44's netting, recorded)

**Date:** 2026-11-06. **Kind:** patch review, round 4.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's r4 files. Your own earlier files, and the merged plans, you may read.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-27/review/patch-27-frozen-r4.sql` | `a31850a02ca0b7259da5baeb119ce69c` |
| `tests/v5.4.2-27/review/battery-27-frozen-r4.sql` | `50a3895686f60bbb51733738484cc29c` |
| `tests/v5.4.2-27/review/shortfall-27-frozen-r4.sh` | `aa30b429d11ecb44268003c7fe608216` |
| `tests/v5.4.2-27/review/mutations-27-frozen-r4.py` | `56a61b306b3dc8f82fb2f0eb1c07c40a` |
| `tests/v5.4.2-27/review/r3-to-r4.diff` | `a8380a6bb640953d3f3cc98dc6d98d89` (the patch, r3 to r4) |

The live copies (`sql/v5.4.2-27-shortfall-applications.sql`, `tests/v5.4.2-27/battery-27.sql`, `races/shortfall-27.sh`, `mutations-27.py`) are identical today. `tests/ci.sh` is unchanged by this stream since r1. The rates stream has since added -30 to its PENDING list after -27, and ported -23's battery to -30's required answers. So -23's battery now runs with -27 and then -30 applied.

## What r3's reviews found and what r4 does

The merged plan is `application/wave2-build-2026-10-15/v5.4.2-27-r4-plan.md`, and the DECISION-LOG entry is 2026-11-06 (-27 r3). Round 3: Codex ready; Opus and Fable not yet, with the same blocking item, found independently.

- **An undo dated after today, recorded alone (Opus B1, Fable B1).**
  - New rule: an undo of a shortfall application is dated no later than the later of today and the date of the row it undoes. This is -23's R-02 rule for a ledger reversal. r3's plan wrongly said -23 never limits a money date to today.
  - "Today" is still the latest date anywhere (UTC+14).
  - r3's second reading in `check_shortfall_repaid` is removed, along with its zero row. The function is r2's text again, plus a comment. With every undo dated no later than today or its own repayment's date, the second reading could never refuse what the first admits.
  - The four mutations are now on the date rule: M56 (rule off, R0), M57 (UTC-12, R2), M57b (a day late, R0b), M58 (no exception for a repayment dated ahead, R3b).
- **The undo a carry names (Fable S1).** r3 compared two recorded times, which are equal within one transaction. r4 records the fact itself:
  - `shortfall_applications.gave_to_escheated` is stamped by `stamp_shortfall_gave_to_escheated` (BEFORE INSERT, every role, whatever the caller sent), under a CHECK that only an undo of a credit's repayment carries it;
  - it is read again under the credit's lock in `enforce_shortfall_application` (40001 if the credit was escheated while the undo waited);
  - `enforce_shortfall_reissue` admits only an undo with it true;
  - the invariant lists the new trigger and CHECK.
  - Ryan was asked, and the plan recommended "strictly later" (`<=`). It was built this way instead because a single battery transaction cannot order the two without owner-chosen times all the way down (DECISION-LOG). Say if you see a path the stamp misses.
- **`cash_drawn_at`'s repaid term is observable (Codex S2; author-run probe 13: -20 at the bounce's instant, root share 80).** The comment is corrected. Battery J1 and mutation M65 now cover it. The source-shortfall term is still said to read 0 at every take-back's instant (no M64). Say if you can construct an instant where it does not.
- **A carry pays a bill (Codex S1):** E20 and E20b, through the bill writer, on a real bill.
- **R5's wording (Codex S3):** up to one local day ahead in Texas and two in the far west; `now()` is the transaction's instant.
- **Tests (Opus S1, N):**
  - SR10 runs the app's carry in a transaction after the escheat's;
  - SR11 is the escheat committing while the undo waits;
  - E18e pins the split of the root's take-back across the deep line (the deepest carry 5, OQ 35, OQ reading 35 owed).

## Drafting calls to check in particular

- **The date rule.** Is "no later than the later of today (UTC+14) and the undone row's date" right for every undo: partial undos, two undos of one row, a repayment dated ahead? Does any correction become impossible?
- **Removing the second reading.** Is it truly redundant under the date rule? Look for a sequence where the first reading admits a leaving move that leaves the family holding money at a date on or after today.
- **The stamp.** BEFORE INSERT reads the credit's status without its lock; the AFTER check re-reads it under the lock. Is there any role, statement shape (multi-row, writable CTE, COPY) or history load where the stamp is wrong and the re-read does not catch it? Is the 40001 the right signal?
- **-23's `refund_reissue`** may have the same gap (a reissue naming a refund that came back before the escheat). This is noted for a later money-stream patch, not -27. Say if you think it blocks.

## Results so far (reproduce them)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`; the second run is skipped by its marker.
- **`battery-27.sql`:** 142 checks, one transaction, rolled back. On frozen r3, E15, R0, R0b and R3 fail, and E15a fails on the missing column; the other new checks (J1, E18e, E20, E20b) pass.
- **`races/shortfall-27.sh`:** SR1–SR11, 21 results.
- **`mutations-27.py`:** 72 of 72 caught, each at its named check as the first failure. M60b and M60e (a wrong stamp) are caught at S3 and E3 by the re-read under the lock, before E15a reads the stamp.
- **-23's own tests with -27 r4 applied:** battery-23 409/409 (with -30 applied after -27, as its port now needs), races cash-23.sh 51/51.
- **`tests/ci.sh`:** 58 steps, all pass, with -25, -26, -27 and -30 pending.

## What to answer

1. Are your r3 findings fixed? Say so for each, by its label.
2. Does r4 implement the r4 plan? Name anything missed or half-done.
3. Is there a path around any rule, old or new? Consider each role, isolation level, statement shape, a history load with chosen times, and dates on both sides of "today".
4. -23's properties (caps, cover, shares, recorded order) with the date rule and the stamp.
5. Concurrency: lock order, and any read a guard depends on that is taken without the lock that orders it.
6. The invariants: is any claim narrower than its check?
7. The tests: is any check weaker than its label, and does any mutation pass for the wrong reason? What is missing?
8. Residuals R1–R5: is any of them blocking?

## How to probe

As r3. Opus and Fable clone `tally` into `rv27opus` or `rv27fable` with TEMPLATE, revoke TEMP from PUBLIC, `tally_app` and `tally_core`, copy the frozen r4 patch in with `docker cp`, and apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

**Codex reviews source only.** Every database claim must be a probe file in `tests/v5.4.2-27/review/codex-r4-probes/`. Each probe:
- runs as the owner, on a fresh clone with frozen r4 applied;
- ends in ROLLBACK;
- prints SQLSTATE and message for each caught error with RAISE NOTICE. A COPY probe must print its own error.

The author runs them.

**Restrictions (everyone):**
- Do not create, drop or alter any role.
- Do not run `mutations-27.py` or `tests/ci.sh`.
- Run `shortfall-27.sh` only against your own clone.
- Modify no file except your output (and Codex's probes).
- Drop your clone when done.

**Output:** `tests/v5.4.2-27/review/<you>-r4.md` (opus, fable, codex). Give a verdict, "ready" or "not yet", and list items as B (blocking), S (should fix) or N (note). Mark each item executed or predicted, with the evidence.
