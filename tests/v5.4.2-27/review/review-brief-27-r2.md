# Review brief: v5.4.2-27 r2 — a credit applied to a bounced payment's shortfall (AC-44's netting, recorded)

**Date:** 2026-11-05. **Kind:** patch review, round 2.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's r2 files. Your own r1 file, and the merged plan, you may read.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-27/review/patch-27-frozen-r2.sql` | `79e7e66ec056021ca25ea2fb1f6e0572` |
| `tests/v5.4.2-27/review/battery-27-frozen-r2.sql` | `649c6819e6bae52a1a9df0282ebad621` |
| `tests/v5.4.2-27/review/shortfall-27-frozen-r2.sh` | `23de66442939d138e9136063fd99ec82` |
| `tests/v5.4.2-27/review/mutations-27-frozen-r2.py` | `8bad2a3cb325357e3b87a8d057ea2b26` |
| `tests/v5.4.2-27/review/r1-to-r2.diff` | `0e91aa155354216727ef9a665cd15f51` (the patch, r1 to r2) |

The live copies (`sql/v5.4.2-27-shortfall-applications.sql`, `tests/v5.4.2-27/battery-27.sql`, `races/shortfall-27.sh`, `mutations-27.py`) are identical today. `tests/ci.sh` is unchanged since r1 (`ci-27-frozen-r1.diff`).

## What r1's reviews found and what r2 does

The merged plan is `application/wave2-build-2026-10-15/v5.4.2-27-r2-plan.md`. The new design text is section 9 of `v5.4.2-27-design.md`. In short:

- **The return check's boundary** (Codex B1, Opus B1; Codex's probe 01 ran and confirmed it: accepted, with the payment holding 10 from March 13 to 17).
  - A move giving money back is now checked from the target's first repayment's date.
  - In that check, an undo counts from the date of the row it undoes.
  - A repayment is still checked from its own date, with every row at its own date.
  - Probe 01, re-run on r2: refused (`codex-r1-probes/01-latest-date-hole.author-run-r2.txt`).
- **The escheat trap** (Opus B2, Fable S1). Ryan settled it on 2026-11-05 (DECISION-LOG, "-27 r1": option 1, carry into a new credit):
  - purpose `shortfall_undo` admits an escheated credit;
  - origin `shortfall_reissue` and `customer_credits.reissues_shortfall_application_id` are new;
  - `enforce_shortfall_reissue` sizes and dates the new credit and draws it on the old one;
  - `enforce_shortfall_undo_carried` checks at commit;
  - `enforce_shortfall_reissue_rows` refuses a credit_issued row, a changed key and a void;
  - re-issued from -23, additions only: `reissue_generation`, `overpayment_root`, `overpayment_family`, `customer_credit_position_as_of`, `cash_drawn_at`;
  - `cash_source_draws` and `customer_credit_draws_as_of` get the carry leg;
  - `check_cash_source` treats a `shortfall_reissue` as it does a `refund_reissue` (no arrival entry).
- **Targets** (Opus S1, S2). A bounced deposit is refused as a target, and so is a refund, with its own message. A reversed target is tested (Fable N1).
- **The invariants' privileges** (Codex S1; probe 02 re-run: all three now caught). Each privilege is asked alone. The core's SELECT is required, its REFERENCES and TRIGGER refused.
- **Race harness** (Codex S2):
  - a statement timeout on every session;
  - deadlines on both handshakes;
  - B stays marked until A finishes;
  - B's exit is checked before A is waited for;
  - A is ended and reaped on failure.
  - New race SR9: a family credit's refund comes back while the family is being repaid.
- **Tests.**
  - Codex's sequence plus variants (battery section C): a partial undo of the later repayment, and the same through a family credit's refund (Fable S2).
  - Section E, the carry end to end, including the overpayment line and a later bounce reaching the new credit.
  - Section T, targets.
  - New mutations:
    - the target cap's family and arrival-entry legs (Opus S3);
    - the credit-refund leg (Fable S2);
    - every new rule.
- **Not added: Opus S3's invoice-application undo on a repaid family.** It goes through the same call as the donation undo (`check_cash_source` purpose `undo`, then `check_shortfall_repaid`), which U2 and M15 cover. Say if you think it needs its own case.
- **Residual R5, new** (Fable N3). The positions read an undo at its own date, so between a repayment and the undo that corrects it after a refund came back, the ended payment reads the money. The cap admits this, since the undo corrects from the repayment's date and a closed period cannot be written into.

## Drafting calls to check in particular

- **The boundary.** Is "first repayment, undo at its row's date" right for every move that gives money back? Can any sequence of back-dated repayments, partial undos and leaving moves still leave the family holding money at a date the positions read, other than R5's interval? Is the strict reading for a new repayment (undo at its own date) consistent with the retroactive reading for a leaving move, or can the two disagree in a way that traps the operator?
- **The carry.**
  - Is the size right?
    - the escheated credit's own remainder after the undo, counting this credit as carried;
    - as far as the undo gave back;
    - -23's r9 form.
  - Is there any path that leaves money on an escheated credit, or that carries money out of a credit that was never escheated?
  - Does a `shortfall_reissue` join the line correctly in every walk, including mixed lines: a refund_reissue of a shortfall_reissue, and the reverse?
  - Is "never voided" right?
  - Is any -23 reader of reissue credits still missing the new branch? The author left out two:
    - `cash_lineage_recorded` and `check_cash_order`'s voided-reissue legs, because the new credit is never voided;
    - the ledger guard's rows under a credit_issued entry, because it has none.
- **Re-issued functions.** Diff each of the five newly re-issued functions against its body in `sql/tu.sql`. Does any differ beyond the shortfall_reissue branch? Do the walks keep -23's plan pins and depth bound?
- **Locks.** The carry takes the payment whose money the escheated credit holds, then the credit (check_cash_source's order), inside a transaction whose undo already took the target first. Is any order inverted?

## Results so far (reproduce them)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`; the second run is skipped by its marker.
- **`battery-27.sql`:** 116 checks, one transaction, rolled back.
- **`races/shortfall-27.sh`:** SR1–SR9, 16 results.
- **`mutations-27.py`:** 58 of 58 caught, each at its named check as the first failure.
- **-23's own tests with -27 r2 applied:** battery-23 409/409, races cash-23.sh 51/51.
- **`tests/ci.sh`:** 55 steps, all pass, with -27 pending (behind -25 and -26; -29's three pending-only steps are skipped now that its counties are loaded in `tally`).

## What to answer

1. Are your r1 findings fixed? Say so for each, by its label.
2. Does r2 implement Ryan's carry ruling and the r2 plan? Name anything missed or half-done.
3. Is there a path around any rule, old or new? Consider:
   - each role, isolation level and statement shape (multi-row, writable CTE, COPY);
   - a superuser history load;
   - a carry inserted in a separate transaction, or before the undo;
   - two undos on one escheated credit;
   - an escheated credit's other undos (invoice application, donation), which must still be refused.
4. -23's properties: caps, cover, shares, recorded order, with a carry in a family.
5. Concurrency: lock order, and any cap read without the lock that orders it.
6. The invariants: is any claim narrower than its check?
7. The tests: is any check weaker than its label, and does any mutation pass for the wrong reason? What is missing?
8. Residuals R1–R5: is any of them blocking?

## How to probe

As r1. Opus and Fable clone `tally` into `rv27opus` or `rv27fable` with TEMPLATE, revoke TEMP from PUBLIC, `tally_app` and `tally_core`, copy the frozen r2 patch in with `docker cp`, and apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

**Codex reviews source only.** Every database claim must be a probe file in `tests/v5.4.2-27/review/codex-r2-probes/`. Each probe:
- runs as the owner, on a fresh clone with frozen r2 applied;
- ends in ROLLBACK;
- prints SQLSTATE and message for each caught error with RAISE NOTICE. A COPY probe must print its own error.

The author runs them.

**Restrictions (everyone):**
- Do not create, drop or alter any role.
- Do not run `mutations-27.py` or `tests/ci.sh`.
- Run `shortfall-27.sh` only against your own clone.
- Modify no file except your output (and Codex's probes).
- Drop your clone when done.

**Output:** `tests/v5.4.2-27/review/<you>-r2.md` (opus, fable, codex). Give a verdict, "ready" or "not yet", and list items as B (blocking), S (should fix) or N (note). Mark each item executed or predicted, with the evidence.
