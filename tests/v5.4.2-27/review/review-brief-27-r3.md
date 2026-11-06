# Review brief: v5.4.2-27 r3 — a credit applied to a bounced payment's shortfall (AC-44's netting, recorded)

**Date:** 2026-11-06. **Kind:** patch review, round 3.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's r3 files. Your own r1 and r2 files, and the merged plans, you may read.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-27/review/patch-27-frozen-r3.sql` | `135242ab0b14159bfea2b3045ce1312d` |
| `tests/v5.4.2-27/review/battery-27-frozen-r3.sql` | `f44547c8e2816cc3a5c819326029ae33` |
| `tests/v5.4.2-27/review/shortfall-27-frozen-r3.sh` | `939b0cbb22ca3b37f392dc8792861ade` |
| `tests/v5.4.2-27/review/mutations-27-frozen-r3.py` | `2e325488d7b98e789e01295c4c99e3a6` |
| `tests/v5.4.2-27/review/r2-to-r3.diff` | `d58402023878e191bf0fd58c9fc939c0` (the patch, r2 to r3) |

The live copies (`sql/v5.4.2-27-shortfall-applications.sql`, `tests/v5.4.2-27/battery-27.sql`, `races/shortfall-27.sh`, `mutations-27.py`) are identical today. `tests/ci.sh` is unchanged since r1 (`ci-27-frozen-r1.diff`).

## What r2's reviews found and what r3 does

The merged plan is `application/wave2-build-2026-10-15/v5.4.2-27-r3-plan.md`. Round 2: Fable ready; Opus and Codex not yet, one blocking item each. Both were settled by rule; no new ruling from Ryan.

- **An undo dated in the future** (Opus B1, executed: an undo dated 2099-12-31 let the refund's return through, and the ended payment read +30 until 2099).
  - `check_shortfall_repaid`, for a move giving money back (NULL `p_from`), now makes two readings. The first is r2's: from the first repayment's date, with an undo at the date of the row it undoes. The second is new: from today on, every row at its own date.
  - "Today" is the latest date anywhere: `(now() AT TIME ZONE 'Etc/GMT-14')::date`. This mirrors -22's close, which reads a period's end at UTC-12. So an undo the utility dates today in its own zone is never later than "today". R5 now says the interval reaches at most one local day ahead in a zone behind UTC+14.
  - Found while testing: the window only read dates on which some row falls, so with nothing dated between today and the undo, the second reading saw nothing. A zero row at the reading's first date fixes it (mutation M58).
  - Not chosen: refusing an undo's future date outright (Opus's option 1). -23 never limits a money date to today; it limits recorded times. The plan explains this.
- **A carry born ended** (Codex B1; author-run: a superuser's history load inserted a carry `escheated`, holding 30, accepted). `enforce_shortfall_reissue` now refuses any status but `active` at birth, for every role. -23's `enforce_cash_birth` returns early for a superuser; this check does not.
- **The undo a carry names** (Opus S1, executed). The undo must have been recorded at or after the old credit's move to escheated. The plan named `escheated_at`. The author used `status_recorded_at` instead, which is the database's stamp of the move; `escheated_at` is written by the app (write-once only), and PATCH-LESSONS says a guard reads the database's facts. Say if you disagree.
- **Tests** (Fable S1, Opus S2, Codex S1):
  - E7d: the escheated credit's `cash_source_draws` lists the carry (mutation M63).
  - S3c: a carry naming an undo of a credit that was never escheated is refused (M62). K9e: one naming a payment's undo is refused.
  - E17: the depth bound. The bound (999) is lowered to 2 inside the check's own subtransaction (M61).
  - E16, E18–E18d: the mixed lines both ways, from Codex's probe 08 as a standalone fixture: overpayment → shortfall_reissue → refund_reissue → shortfall_reissue, generations 1–3, and the root payment's later bounce reaching the third.
  - E19, E19b: an escheated credit's bill-application undo (through the bill writer itself, with a real bill) and its donation undo are still refused.
  - C2b: a true partial undo of the later repayment (probe 09).
  - E7c: compares the customer's balance before and after, as K3b does.
  - R1, R1b, R2, R2b: the future-dated undo, with the boundary on both sides (2099 and the day after "today" refused, "today" admitted). Mutations M56, M57, M57b, M58.
  - E6c, E6d: the carry born escheated or voided, as the owner (M59). E15: the undo recorded before the escheat (M60).
- **Two items not done as asked:**
  - **A bill-application undo on a repaid family, at the caller (Codex S1).** It cannot be reached. -23's R15 holds a payment's bounce while it or any credit of its family is applied to a bill, so no family credit can have a bill application to undo once the payment has bounced. E19 tests the caller with the escheated-source refusal instead.
  - **Mutations for `cash_drawn_at`'s source-shortfall and repaid terms (Codex S1).** Both were written and both survive, by construction. The one reader (`overpayment_shares`) asks at a take-back's instant. A take-back waits while the source's shortfall applications net to more than 0 (R15). A payment is repaid only after it ended, when nothing more is taken back under its entry. So both terms read 0 at every instant asked. They are kept so the function lists what `cash_source_draws` lists. The patch comment and the runner say why there is no mutation. Say if you can construct an instant where either term is not 0.
- **Notes taken:**
  - the race script's monitoring and reaping queries now have a 5-second statement timeout and a connect timeout (Codex N2);
  - the header, the table comment and section 3 qualify "never holds money" with R5's interval (Codex N5);
  - `repaid` prints 0.00 (Fable N6), so K0, F0 and B1b now expect `/0.00`;
  - the battery's payment numbers use four id digits, so the new `…29xx` fixtures don't collide.

## Drafting calls to check in particular

- **The two readings.** Can any sequence of repayments, partial undos and leaving moves pass both readings and still leave the family holding money at a date the positions read, outside R5's interval before today? Can the new reading refuse a correction the operator has no other way to make (an undo dated today, or a repayment dated in the future with its undo)?
- **"Today" at UTC+14.** Is the latest date anywhere the right bound, rather than the tenant's own zone? Is there any zone-free alternative that is tighter without refusing an undo dated today locally?
- **The born-active check.** It fires in an AFTER trigger. Is there a path where a carry is born active and moved to escheated or voided in a way that skips -23's checked moves? (-27's own trigger refuses the void.)
- **The recorded-after-escheat check.** Is `status_recorded_at` the right stamp for a superuser's history load, which may choose it? A chosen time cannot be in the future (-23).
- **The mixed-line fixture.** Does it exercise what probe 08 claimed? Are generation, root and family right at each step?

## Results so far (reproduce them)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`; the second run is skipped by its marker.
- **`battery-27.sql`:** 135 checks, one transaction, rolled back. On frozen r2 the new fix checks fail (K0, F0, B1b, E6c, E6d, E15, R1, R1b) and the other new checks pass.
- **`races/shortfall-27.sh`:** SR1–SR9, 16 results.
- **`mutations-27.py`:** 67 of 67 caught, each at its named check as the first failure. M64 and M65 were written and dropped (see above).
- **-23's own tests with -27 r3 applied:** battery-23 409/409, races cash-23.sh 51/51.
- **`tests/ci.sh`:** 55 steps, all pass, with -27 pending (behind -25 and -26).

## What to answer

1. Are your r2 findings fixed? Say so for each, by its label.
2. Does r3 implement the r3 plan? Name anything missed or half-done.
3. Is there a path around any rule, old or new? Consider:
   - each role, isolation level and statement shape (multi-row, writable CTE, COPY);
   - a superuser history load, with chosen times;
   - dates on both sides of "today", in zones ahead of and behind the server.
4. -23's properties (caps, cover, shares, recorded order) with the new reading and the deeper lines.
5. Concurrency: lock order, and any cap read without the lock that orders it.
6. The invariants: is any claim narrower than its check?
7. The tests: is any check weaker than its label, and does any mutation pass for the wrong reason? What is missing?
8. Residuals R1–R5, R5 as amended: is any of them blocking?

## How to probe

As r2. Opus and Fable clone `tally` into `rv27opus` or `rv27fable` with TEMPLATE, revoke TEMP from PUBLIC, `tally_app` and `tally_core`, copy the frozen r3 patch in with `docker cp`, and apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

**Codex reviews source only.** Every database claim must be a probe file in `tests/v5.4.2-27/review/codex-r3-probes/`. Each probe:
- runs as the owner, on a fresh clone with frozen r3 applied;
- ends in ROLLBACK;
- prints SQLSTATE and message for each caught error with RAISE NOTICE. A COPY probe must print its own error.

The author runs them.

**Restrictions (everyone):**
- Do not create, drop or alter any role.
- Do not run `mutations-27.py` or `tests/ci.sh`.
- Run `shortfall-27.sh` only against your own clone.
- Modify no file except your output (and Codex's probes).
- Drop your clone when done.

**Output:** `tests/v5.4.2-27/review/<you>-r3.md` (opus, fable, codex). Give a verdict, "ready" or "not yet", and list items as B (blocking), S (should fix) or N (note). Mark each item executed or predicted, with the evidence.
