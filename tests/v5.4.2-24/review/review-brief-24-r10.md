# Review brief: v5.4.2-24 r10 — unmatched cash and agency pledges

**Date:** 2026-11-22. **Kind:** patch review, round 10.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's files.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-24/review/patch-24-frozen-r10.sql` | `72fdcfdcb52c94098c4e54e8f649b139` |
| `tests/v5.4.2-24/review/battery-24-frozen-r10.sql` | `e7bbce6f85f8c70059aedcab4f104d6f` |
| `tests/v5.4.2-24/review/suspense-24-frozen-r10.sh` | `55c631999a54b336848e18cb06c80331` |
| `tests/v5.4.2-24/review/mutations-24-frozen-r10.py` | `b15bec4ea9869b8f1cc4288ba2d3e3b8` |
| `tests/v5.4.2-24/review/ci-24-frozen-r10.diff` | `c343828be614b5abf30a15944402ee0c` |
| `tests/v5.4.2-24/review/r9-to-r10.diff` | `31b5de1846a33de65bac7758a96c7670` |

The live copies (`sql/v5.4.2-24-unmatched-cash-and-pledges.sql`, `tests/v5.4.2-24/battery-24.sql`, `races/suspense-24.sh`, `mutations-24.py`) are identical today. `r9-to-r10.diff` is the patch, battery and mutation changes since round 9 (`r8-to-r9.diff` and earlier for the rounds before). The race script is unchanged from round 6. The ci diff is unchanged from round 1. The diff is -24's change to `tests/ci.sh` (PENDING, battery, races, invariants) and its port of `tests/v5.4.2-23/battery-23.sql`: an agency's payment there now names an agency.

## Background

The base is the `tally` database: `sql/tu.sql` through v5.4.2-27, with -23 (cash: reversals, derived positions, per-line application, overpayment credits), -27 (shortfall applications), -28 and -29 mirrored. In `ci.sh`, -24 applies after -25, -26 and -30 (all pending). -24 re-issues no existing function. It adds tables, nullable `payments` columns with CHECKs and two new triggers on `payments`, a CHECK on `tenants`, a trigger on `customer_program_enrollments`, and a description change on `program_types`.

What it is for:
- **CI-053** (GBM `application/canonical-invariants.md`): money that cannot be matched to a customer is held, never dropped, never applied to a guessed account, never revenue. It resolves to an account (with the reason recorded) or is refunded to the sender after the tenant's retention period.
- **CI-056**: pledges and suspense items are processed within a service level; past it, fail loud (an operator surface, a disconnection pause, reporting).

The rulings and sources:
- **Ryan, 2026-10-16** (DECISION-LOG): -24 is U (unmatched cash) and L (agency pledges), new tables that point at payments, additive.
- **Ryan, 2026-11-07** (DECISION-LOG): a refund of an agency's money goes to the agency, never the customer, for every agency. 10 TAC §6.312(f): "A Vendor Refund is program income and must be reimbursed to the Subrecipient, and not the customer." TDHCA's 2026 CEAP vendor agreement: 45 days to pay a pledge, during which the pledged portion is not delinquent.
- **The two workflow files:** GBM `application/configurable-rules/workflows/unapplied-cash-resolution.md` and `agency-pledge-posting.md` (their Open questions are the findings -24 answers).

The design is `application/wave2-build-2026-10-15/v5.4.2-24-design.md`. Section 0 lists the sources, sections 1–6 the calls settled by rule, section 6 the known limits L1–L6, and section 8 where the build differs from the plan. -26 (pending) names the collections conditions `agency_pledge` and `aged_suspense`; -24 supplies the rows the core reads for them.

## Rounds 1 to 9, and what changed

The plans are `application/wave2-build-2026-10-15/v5.4.2-24-r2-plan.md` to `-r10-plan.md`, one per round's findings; read them first (r10's especially: it says which fix was taken and which was not). In round 9 all three said not yet: Codex one blocking item, Opus three should-fix, Fable one should-fix. The author executed the claims (all ten Codex probes as predicted; Opus Q1 to Q3).

Round 9's findings and their fixes, to check in particular:

- **The returns-due reader was wrong at past coordinates** (Codex B1, Opus S1, Fable S1). `suspense_misposted_share_as_of(payment, date, instant)` walks only rows dated and recorded by the coordinates, and gives the date since when the share has been above 0 without a break; the reader lists by it, not by the payment's status. Is it right at every coordinate, both ways (nothing twice, nothing nowhere)? Is `since` right for repeated undo and reversal, several rows on one date, and a payment dated after its reversal? Does the pruning of nsf rows hold when some of the tree is not yet visible?
- **A partly misposted payment stranded its share** (Opus S2). A bounced (`nsf`) payment now returns its misposted share, its code notwithstanding; `reversed` takes a return code only where the share is 0 or the whole payment (refused while 0 < share < amount); a bounce's code may arrive after its return; the recorded-order check reads a bounce's recorded time. **Not taken:** Opus's rule (a code bars the return only when the tree has no nsf row that takes money), because the bank may take 40 as nsf and 60 as a coded reversal, and that rule would return 60 it had taken. Is the rule taken sound? Attack it: the nsf ending's lock order and races (SU1 to SU12 do not cover an nsf return), statement shapes, COPY, a history load, a payment whose tree has undos of nsf rows (a redeposit), an `nsf` status whose named row was undone, a share of the whole payment on an nsf payment.
- **Tests** (Opus S3, Codex S1, Fable): S4b includes the amount due; S4c is the other direction; S8f to S8s, O1i, P12a, P15 to P15h, P16, P16b; mutations M120 to M144. S4c covers seven receipts: is that enough, and is its list hand-picked to pass?

Put to you directly:
1. **A possible limit L7.** A clerk who reverses part of a payment as misposted and part as the bank's take-back, **both as plain reversals**, and ends it `reversed` with the bank's code, loses the misposted part: share equals the whole payment, so the code is admitted and the return barred (as since r2). The database cannot tell the two rows apart. Acceptable, or is there a rule?
2. **Inserts.** The code check runs on UPDATE. The author found that a payment inserted (as owner) already reversed with a code takes no ledger rows afterwards (-23, 23514), so the mixed tree cannot be loaded that way; such a payment, with no rows, uses up its receipt. r10 does not change inserts. Can `tally_app` do it? Does it matter?
3. A return code has no recorded time of its own, so a later one takes a payment off the list at earlier instants too (stated in the comment). Acceptable?

Earlier rounds' fixes stand as before:
- round 7: a misposting return gives back exactly the share; the refusal of a chosen earlier time is tested (P14i4);
- round 8: money waiting on a return is listed; refusals match the share's amount; the comments say exactly;
- round 6: the return recorded no earlier than every row under the posting entry (40001/23514), the redundant reversal-date check removed, the invariant lists a missing helper, the conservation sweep S4b;
- the misposted share (r5: nsf rows that take money left out; r6: dated on or after every row under the posting entry);
- a misposting return is dated on or after its payment's date (r4 Opus S1);
- the cap also refuses a date below zero;
- releases are ordered, and self-exclusion is per table;
- NaN is refused;
- the invariant's exact lists (`fill-manifest.py`);
- tenant checks with foreign keys off;
- the provider pin and the late write;
- misposting returns rather than reversals, and recorded order;
- clocks, and the settings CHECK.

## Drafting calls still worth a look

- **The receipt's cap** (`check_suspense_receipt_cap`): for every date a payment or disposition falls on, the non-voided payments dated by then plus the dispositions dated by then never exceed the receipt.
- **Pledges**: the agreement and pay-by are chosen by the database; there is no cap on agency money; the state precedence; the lock between payments and events.
- **Where a refund goes** (`cash_money_agency`), within limits L5 and L6.
- **Tenancy**: two-column keys (R-12), RLS and FORCE RLS, grants.

## Results so far (reproduce them)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`; the second run is skipped by its marker, the table `suspense_receipts`. The patch's tail runs every earlier invariants function.
- **`battery-24.sql`:** 309 checks, one transaction, rolled back.
- **`races/suspense-24.sh`:** SU1–SU12, 24 results.
- **`mutations-24.py`:** 142 of 142 caught, each at its named check as the first failure (the full run caught 141; M77's search text was stale and was repaired, then run alone).
- **`tests/ci.sh`:** 63 steps, all pass (2026-11-22, beside -30 r5), with -24 pending last (after -25, -26 and -30), including battery -23 as ported.

## What to answer

1. **Is every round-9 finding closed, and every earlier one still?** Name any that is not, by its round and id. Then: does the patch implement the design and the rulings (CI-053, CI-056, Ryan's 11-07 rule within L5 and L6)?
2. **Is there a path around any new rule?** Consider:
   - a receipt spent twice;
   - a payment from a receipt dated or effective out of bounds, of another tenant, or missing its reason;
   - a guessed application that the database makes;
   - a provider transaction recorded twice;
   - a pledge paid by another agency or customer, or ended twice;
   - a lapse recorded early;
   - a payment naming a pledge recorded in error;
   - a refund of agency money paid to the customer, or of the customer's money to an agency;
   - an agency brought back;
   - an agreement edited.

   Try each role, isolation level and statement shape (multi-row, writable CTE, COPY), and a superuser history load.
3. **-23's and -27's properties.** Does anything in -24 change what -23's positions, caps or recorded-order rules see? The new triggers on `payments` run beside -23's: does their order matter?
4. **Concurrency.** Is the lock order followed everywhere? Is any cap a read without the lock that orders it?
5. **The invariants.** Does `assert_suspense_pledge_guard_invariants()` catch what it claims? Is any claim narrower than its check?
6. **The tests.** Is any check weaker than its label? Does any mutation pass for the wrong reason? What is missing?
7. **Known limits L1–L6.** Is any of them actually blocking?

## How to probe

**Opus and Fable** may query the running `tally-pg` read-only. For experiments, clone into your own scratch database (Opus `rv24opus`, Fable `rv24fable`):
1. `CREATE DATABASE <name> TEMPLATE tally`.
2. Revoke TEMP on the clone from PUBLIC, `tally_app` and `tally_core` right after creating it.
3. `docker cp` the frozen patch into the container, then apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

`tally` does not carry -25, -26 or -30. -24 applies over `tally` alone; to test beside them, apply -25, -26 and -30 strictly first, in that order.

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim must be a probe file in `tests/v5.4.2-24/review/codex-r10-probes/`. Each probe runs as the owner, on a fresh clone with frozen r10 applied, ends in ROLLBACK, and prints SQLSTATE and message for each caught error with RAISE NOTICE (a COPY probe must print its own error: psql leaves LAST_ERROR_SQLSTATE at 00000 after a failed COPY). The author will run the probes.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role.
- Do not run `mutations-24.py`; it uses the fixed name `m24`. Do not run `tests/ci.sh`.
- Run `suspense-24.sh` only against your own clone; it commits rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.

**Output:** `tests/v5.4.2-24/review/<you>-r10.md` (opus, fable, codex): verdict "ready" or "not yet"; items B (blocking), S (should fix), N (note), each marked executed or predicted, with the evidence.
