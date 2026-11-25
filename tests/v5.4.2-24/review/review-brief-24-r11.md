# Review brief: v5.4.2-24 r11 — unmatched cash and agency pledges

**Date:** 2026-11-24. **Kind:** patch review, round 11.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's files.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-24/review/patch-24-frozen-r11.sql` | `5518d76343e41cc9b6927dd3884a0233` |
| `tests/v5.4.2-24/review/battery-24-frozen-r11.sql` | `8328337768052b456974cd2590dfc84b` |
| `tests/v5.4.2-24/review/suspense-24-frozen-r11.sh` | `360dea4db148825d696134bfa30e0502` |
| `tests/v5.4.2-24/review/mutations-24-frozen-r11.py` | `46f7ef4850ba5c50347ade59f366ab81` |
| `tests/v5.4.2-24/review/ci-24-frozen-r11.diff` | `ec30f74364228bf3f325a1958583d01b` |
| `tests/v5.4.2-24/review/r10-to-r11.diff` | `f428a197b0c908aa6402030a2d9a5da4` |

The live copies (`sql/v5.4.2-24-unmatched-cash-and-pledges.sql`, `tests/v5.4.2-24/battery-24.sql`, `races/suspense-24.sh`, `mutations-24.py`) are identical today. `r10-to-r11.diff` is the patch, battery, race and mutation changes since round 10 (`r9-to-r10.diff` and earlier for the rounds before); this round the race script changed too (SU13 to SU15b). The ci diff is -24's change to `tests/ci.sh` (PENDING, battery, races, invariants) and its port of `tests/v5.4.2-23/battery-23.sql` (an agency's payment there names an agency), regenerated against today's `ci.sh`: the only difference from round 10's is that -30 has left PENDING.

## Background

The base is the `tally` database: `sql/tu.sql` through v5.4.2-30, with -23 (cash: reversals, derived positions, per-line application, overpayment credits), -27 (shortfall applications), -28, -29 and **-30 (tax levies, mirrored 2026-11-22; new since round 10)**. In `ci.sh`, -24 applies after -25 and -26 (both pending). -24 re-issues no existing function. It adds tables, nullable `payments` columns with CHECKs and two triggers on `payments`, **one trigger on `account_ledger` (new in r11)**, a CHECK on `tenants`, a trigger on `customer_program_enrollments`, and a description change on `program_types`.

What it is for:
- **CI-053** (GBM `application/canonical-invariants.md`): money that cannot be matched to a customer is held, never dropped, never applied to a guessed account, never revenue. It resolves to an account (with the reason recorded) or is refunded to the sender after the tenant's retention period.
- **CI-056**: pledges and suspense items are processed within a service level; past it, fail loud (an operator surface, a disconnection pause, reporting).

The rulings and sources:
- **Ryan, 2026-10-16** (DECISION-LOG): -24 is U (unmatched cash) and L (agency pledges), new tables that point at payments, additive.
- **Ryan, 2026-11-07** (DECISION-LOG): a refund of an agency's money goes to the agency, never the customer, for every agency. 10 TAC §6.312(f): "A Vendor Refund is program income and must be reimbursed to the Subrecipient, and not the customer." TDHCA's 2026 CEAP vendor agreement: 45 days to pay a pledge, during which the pledged portion is not delinquent.
- **The two workflow files:** GBM `application/configurable-rules/workflows/unapplied-cash-resolution.md` and `agency-pledge-posting.md`.

The design is `application/wave2-build-2026-10-15/v5.4.2-24-design.md` (section 0 the sources, sections 1–6 the calls settled by rule, section 6 the known limits L1–L6, section 8 where the build differs from the plan). -26 (pending) names the collections conditions `agency_pledge` and `aged_suspense`; -24 supplies the rows the core reads for them.

## Rounds 1 to 10, and what changed

The plans are `application/wave2-build-2026-10-15/v5.4.2-24-r2-plan.md` to `-r11-plan.md`, one per round's findings; **read r11's first**: it says which fix was taken for each round-10 finding, and which was not. In round 10 Fable said ready (two should-fix); Opus not yet (five should-fix); Codex not yet (one blocking, two should-fix). The author ran all 14 Codex probes (as predicted). The limit put to you in round 10 (L7: a misposted part lost under a coded `reversed`) is closed by a rule, not recorded.

Round 10's findings and their fixes, to check in particular:

- **What the bank took was ambiguous when a receipt's payment ended** (Codex B1; Opus S1, S3). Now, when a receipt's payment ends (`enforce_payment_suspense_pledge`, UPDATE):
  - `reversed` takes a bank return code only where the row it names takes back the whole payment (`ledger_entry_remaining(status_cause_id) >= amount`), or the share is 0 (the bank took it all as nsf rows);
  - `nsf` needs an nsf row that stands (refused when the share is the whole payment);
  - no row under a bounce takes money without being typed nsf (`suspense_untyped_take_back`, new; undone rows do not count);
  - `reversed` takes its code with the move and never afterwards: a take-back learned later is recorded as the return to the receipt, then `bank_returned` there with its code.
  - **Not taken:** a receipt's payment never takes a code on `reversed`, every take-back typed nsf. `nsf` is counted against a customer (`nsf_count_12mo`, the deposit triggers); an unauthorized debit (R10) is not a bounce. P12a (one whole reversal with R10) stays admitted.
- **A code took the payment off the returns-due list at instants before the move** (Opus S2): the reader now gates the code by `status_recorded_at`.
- **A pending receipt's payment whose posting entry was undone was stranded** (Opus S4): refused by `enforce_ledger_suspense_posted`, AFTER INSERT on `account_ledger`. Its first form joined `payments` and refused every void of a bill, because `void_invoice()` runs as `tally_void`, which may not read `payments`; the trigger now reads the ledger entry first and returns before touching `payments` unless that entry is a payment's posting entry. -24's own tests did not catch it; ci.sh did.
- **A receipt's payment loaded born ended** (Fable S2): refused at insert for every role (`reversed`, `nsf`).
- **Conservation** (Fable S1, Codex S2, Opus N4): S4c covers every receipt of T1 on every day, the bank's part being the net of each nsf tree plus what a coded `reversed` took as of the day.
- **Tests** (Opus S5): checks S8t to S8za, S8y, S8yb, P12a, P17 to P22, O7, O7b; mutations M145 to M167 (M153 dropped; M122, M123, M125 replaced); races SU13 to SU15b.

Put to you directly:
1. **A receipt's payment that is a deposit has no test.** The entry type `deposit` is in every walk (`suspense_misposted_share`, `suspense_untyped_take_back`, `enforce_ledger_suspense_posted`), but no fixture makes one. Does any rule behave differently for it? Is it blocking, or a note for the deposit patch?
2. **Can the four ending rules be got round?** In particular: the order of moves (a code with the move, then rows added after the end; rows undone after the end, making the named row no longer the whole); a status moved `reversed` → `nsf` or the reverse; a cause row that is itself undone; several statements in one transaction; COPY; a history load as owner.
3. **The new trigger on `account_ledger`.** List every role that inserts into `account_ledger` (`tally_app`, `tally_core`, `tally_void`, any SECURITY DEFINER writer in `tu.sql`, the owner) and say for each whether the trigger can refuse a legitimate write or fail for lack of a grant. Does `ENABLE ALWAYS` matter for a replica load? Does it fire for every row of a multi-row insert in the order the guards need?

Earlier rounds' fixes stand as before (see the r10 brief's list): the reader at its coordinates (r10); a misposting return gives back exactly the share (r7); money waiting on a return is listed (r8); recorded order (r6); the misposted share and its date (r4–r6); the cap; release order; NaN; the invariant's exact lists; tenant checks with foreign keys off; the provider pin and the late write; clocks and the settings CHECK.

## Drafting calls still worth a look

- **The receipt's cap** (`check_suspense_receipt_cap`): for every date a payment or disposition falls on, the non-voided payments dated by then plus the dispositions dated by then never exceed the receipt.
- **Pledges**: the agreement and pay-by are chosen by the database; there is no cap on agency money; the state precedence; the lock between payments and events.
- **Where a refund goes** (`cash_money_agency`), within limits L5 and L6.
- **Tenancy**: two-column keys (R-12), RLS and FORCE RLS, grants.

## Results so far (reproduce them)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`; the second run is skipped by its marker, the table `suspense_receipts`. The patch's tail runs every earlier invariants function.
- **`battery-24.sql`:** 335 checks, one transaction, rolled back.
- **`races/suspense-24.sh`:** SU1–SU15b, 29 results.
- **`mutations-24.py`:** 161 of 161 caught, each at its named check as the first failure, in one full run (2026-11-24).
- **`tests/ci.sh`:** 61 steps, all pass (2026-11-24, on `tally` carrying -30), with -24 pending last (after -25 and -26), including battery -23 as ported.

## What to answer

1. **Is every round-10 finding closed, and every earlier one still?** Name any that is not, by its round and id. Then: does the patch implement the design and the rulings (CI-053, CI-056, Ryan's 11-07 rule within L5 and L6)?
2. **Is there a path around any new rule?** Consider, beside the three questions above:
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
3. **-23's and -27's properties.** Does anything in -24 change what -23's positions, caps or recorded-order rules see? The triggers on `payments` and `account_ledger` run beside -23's: does their order matter?
4. **Concurrency.** Is the lock order followed everywhere, including the new ending rules and the ledger trigger? Is any cap a read without the lock that orders it?
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

`tally` carries -30 but not -25 or -26. -24 applies over `tally` alone; to test beside them, apply -25 and -26 strictly first, in that order.

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim must be a probe file in `tests/v5.4.2-24/review/codex-r11-probes/`. Each probe runs as the owner, on a fresh clone with frozen r11 applied, ends in ROLLBACK, and prints SQLSTATE and message for each caught error with RAISE NOTICE (a COPY probe must print its own error: psql leaves LAST_ERROR_SQLSTATE at 00000 after a failed COPY). The author will run the probes.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role.
- Do not run `mutations-24.py`; it uses the fixed name `m24`. Do not run `tests/ci.sh`.
- Run `suspense-24.sh` only against your own clone; it commits rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.

**Output:** `tests/v5.4.2-24/review/<you>-r11.md` (opus, fable, codex): verdict "ready" or "not yet"; items B (blocking), S (should fix), N (note), each marked executed or predicted, with the evidence.
