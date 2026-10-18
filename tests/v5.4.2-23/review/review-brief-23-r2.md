# Review brief: v5.4.2-23 r2 — cash: the general reversal cap, derived positions, per-line payment application, overpayment approvals, the within-bill order

**Date:** 2026-10-18. **Kind:** patch review, round 2.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's round-2 files. You may read every round-1 review (`opus-r1.md`, `fable-r1.md`, `codex-r1.md`, `codex-r1-probes/`): r2 answers all three.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-23/review/patch-23-frozen-r2.sql` | `c3524ee9a6dfce08e33bcf324dd52a33` |
| `tests/v5.4.2-23/review/battery-23-frozen-r2.sql` | `813e06b8019d8d375cdcef752abaa3fd` |
| `tests/v5.4.2-23/review/cash-23-frozen-r2.sh` | `0affa40a74f18000abdd9faabc994cc3` |
| `tests/v5.4.2-23/review/mutations-23-frozen-r2.py` | `46b0a55386c776f68e978f59656b496d` |
| `tests/v5.4.2-23/review/older-tests-23-frozen-r2.diff` | `c2f3d72f924d5178375e4a4fc58804b8` |
| `tests/v5.4.2-23/review/patch-23-r1-to-r2.diff` | `f8fcfe820634527f72cec54933852b5b` |

Today the live copies are identical to the frozen ones. Review the frozen copies. The live copies are `sql/v5.4.2-23-cash-reversals-positions-application.sql`, `tests/v5.4.2-23/battery-23.sql`, `tests/v5.4.2-23/races/cash-23.sh` and `tests/v5.4.2-23/mutations-23.py`.
- `older-tests-23-frozen-r2.diff` holds every change -23 made to earlier tests, measured against the -22 mirror commit `eef5122`.
- `patch-23-r1-to-r2.diff` is the patch's change since round 1, for orientation only. Review the whole r2 patch, not only the diff: r2 moved checks between functions.

## What r2 is

`application/wave2-build-2026-10-15/v5.4.2-23-r2-plan.md` is the fix list: every round-1 finding, merged across the three reviews, and the standing rule that settles each one. Read it first. In short:
1. **Sources are read under their lock.** `check_cash_source(kind, id, row_created_at, purpose, on_date)` takes the source's lock first, then reads and judges the source by purpose. Unknown or invisible sources fail closed. Status moves run at READ COMMITTED only.
2. **Status moves name the act, exactly.** A payment is born pending and a credit active. Posted names a posting entry of the payment's own kind. nsf and reversed leave nothing of that entry. Refunded names a standing refund. A credit's void names the reversal that leaves nothing of its `credit_issued` entry; an overpayment credit's void names nothing. Escheated names an `escheated_to_state` event; donated names a donation row.
3. **Money on the ledger.** A source draws only while its arrival stands (`cash_arrival_stands`). The ledger row that would undo a payment's posting entry, or a credit's `credit_issued` entry, is refused while the money is still drawn on. It takes the tree's lock, then the source's.
4. **Every way money leaves a source is a draw.** Only an overpayment credit names a payment. A voided overpayment credit stops drawing. A credit's donation and escheat are draws.
5. **Positions at fixed coordinates.** `status_recorded_at` is stamped by the database. A line and a bill have no position before their bill was issued (`first_issued_at`). R2 is closed.
6. **Smaller fixes:**
   - recorded order covers the source and the bill;
   - no reversal dated after today;
   - only the reversal types, `adjustment` and `write_off` name an entry;
   - an approver is a user of the approval's own tenant;
   - the invariants check column grants, the status default, the approvals' policy and `check_cash_source`'s grants;
   - the lock order is restated in the header.

The base, rulings and design are as in round 1 (`review-brief-23-r1.md`, "Background").

## Open with Kyle: review both answers

The patch keeps r1's behaviour on two questions sent to Kyle (`application/kyle-brief-2026-10-17-refund-then-bounce.md`; patch header, "Open with Kyle"):
- **K1.** Is a refund an undo of its payment (it names the payment's posting entry and counts in that entry's tree, as now), or its own movement of money?
- **K2.** A payment with a refund still pending moving to nsf or reversed: refused until the refund is voided (now), or does the bounce void it?

Do not skip these parts. Review them as they stand. Then say what would break, or what else would have to change, if Kyle answers K1 "its own movement". Under that answer, refunds leave X1, the posting entry's tree in `cash_arrival_stands`, and the bounce-row guard's exemption. Say also which tests would have to change. Mark these findings **K1-A** so they are not counted against the patch as it stands.

## Drafting calls to check in particular

- **`check_cash_source`.** Is every source read after the lock, in a statement whose snapshot follows it? Is the purpose table right, especially `undo` (any source not yet ended) against `refund` and `application`? Does any caller pass the wrong purpose, date or `created_at`?
- **`cash_arrival_stands`.** A payment's arrival is its `status_cause_id` while posted; a credit's is its `credit_issued` entry at minus its amount. Can a source draw while part of its money is undone? Can a credit with two `credit_issued` rows, or one of the wrong amount, pass?
- **The bounce-row guard** in `enforce_ledger_reversal`. It applies to rows under a payment's posting entry (other than its own refunds' rows) and under a credit's `credit_issued` entry. Can a row undo the money without reaching it: a row under a different root, a nested row, a refund naming another payment, or a void? Is "tree, then source" consistent with every other writer's order?
- **Births and moves.** Can a caller reach posted, nsf, reversed, refunded, voided, escheated or donated without the act? Can `status_recorded_at` be chosen, by a caller or by a move? What does a superuser's history load keep, and is that stated?
- **The positions at (d, R).** Refunds and credits are counted by `status_recorded_at`. A line or bill is counted from `first_issued_at`. Is any read still live? Is the "fixed once R is older than every open transaction" model stated where it is read?
- **The draw set.** `cash_source_draws` covers applications, overpayment credits not voided, refunds pending or posted, donations and escheats. Is any way out of a source missing? Does any row count twice, for example a donation that is also a reversal?
- **Recorded order.** A draw is not recorded before its source, nor an application before its bill was issued: 40001 at the transaction's start, 23514 for a chosen time. Does every path check it?

## Results so far (reproduce them)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`. The second run is skipped by its marker, the table `customer_credit_approvals`.
- **`tests/ci.sh`:** passes in full with -23 pending. That covers:
  - batteries 09–23 and the -15/-17/-18 runners;
  - every race script;
  - all eight invariant steps.
- **`battery-23.sql`:** 168 checks, one transaction, rolled back. That includes R1–R18b for the round-1 findings, LC3, and I1/I2, which now call each invariant directly.
- **`races/cash-23.sh`:** CR1–CR13 (18 results). CR3 is now the bounce row against an application in flight. CR9–CR13 are new:
  - each round-1 race the other way round;
  - status moves under REPEATABLE READ;
  - a move to refunded against the void of the refund it names.
- **`mutations-23.py`:** 110 of 110 caught, each at its named check as the first failure of any kind. The 71 round-1 mutations are re-anchored, and N72–N110 are new.
- **Earlier tests changed since round 1** (in the diff):
  - -19: P1 is now the move to posted with no effective date; P-2 and R4-PARENT are posted by their entries; B1's balance changes as a result.
  - -21: credit 2161 has its `credit_issued` entry; payment 2181 is posted.

  Patch residual R8 names them. Check that every change follows a rule -23 adds and that none just loosens a test.

## What to answer

1. **Does r2 close each round-1 finding it claims to close?** Go through the r2 plan item by item. Say for each: closed, partly closed (what is left), or not closed.
2. **Did r2 open anything new?** Consider:
   - a new guard that refuses a legitimate act;
   - a lock order with a cycle;
   - a check that moved and no longer runs on some path;
   - a superuser or role path around the births, the stamps or the causes.
3. **Is there still a path around any rule?** The round-1 list stands (`review-brief-23-r1.md`, "What to answer", 2). Try each role, isolation level and statement shape (multi-row, writable CTE, COPY), and a superuser history load.
4. **Concurrency.** Is every cap behind a lock taken before its read? Can two writers deadlock in a way no retry resolves?
5. **The invariants.** Does `assert_cash_guard_invariants()` catch what it claims? Is any claim narrower than its check?
6. **The tests.** Is any check weaker than its label? Does any mutation pass for the wrong reason? What is missing?
7. **K1-A and K2:** as above.
8. **Residuals R1–R11 and the notes left unchanged** (r2 plan, last section). Is any of them actually blocking?

## How to probe

**Opus and Fable** may query the running `tally-pg` read-only. For experiments, clone into your own scratch database, named for you only (Opus `rv23opus`, Fable `rv23fable`):
1. Clone with `CREATE DATABASE <name> TEMPLATE tally`.
2. Revoke TEMP on the clone from PUBLIC, `tally_app` and `tally_core` right after creating it.
3. `docker cp` the frozen patch into the container, then apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim must be a probe file in `tests/v5.4.2-23/review/codex-r2-probes/`. Each probe:
- runs as the owner, on a fresh clone with frozen r2 applied;
- ends in ROLLBACK;
- prints SQLSTATE and message for each caught error with RAISE NOTICE.

A COPY probe must print the error itself, because psql leaves LAST_ERROR_SQLSTATE at 00000 after a failed COPY. The author will run the probes.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role.
- Do not run `mutations-23.py`; it uses the fixed name `m23`.
- Run `cash-23.sh` only against your own clone; it commits rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.

## Output

Write your full review to `tests/v5.4.2-23/review/<reviewer>-r2.md` (`opus`, `fable` or `codex`). It should contain:
- a verdict: "ready" or "not yet";
- the round-1 findings, each marked closed, partly closed or not closed;
- blocking items (B1…), each with the concrete path or repro;
- should-fix items (S1…);
- notes (N1…);
- K1-A items.

Mark each claim as **executed** or **predicted**. Your final message, under 2 KB, gives the verdict, the blocking items in one line each, and the file path. If you cannot write the file, send the review to main as several messages, each under 3 KB.
