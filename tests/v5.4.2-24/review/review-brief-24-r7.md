# Review brief: v5.4.2-24 r7 — unmatched cash and agency pledges

**Date:** 2026-11-07. **Kind:** patch review, round 7.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's files.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-24/review/patch-24-frozen-r7.sql` | `b82ca100ca9f6a6a4ba02b2b4da851e4` |
| `tests/v5.4.2-24/review/battery-24-frozen-r7.sql` | `f910a8ba77447db88106dd203d64465f` |
| `tests/v5.4.2-24/review/suspense-24-frozen-r7.sh` | `55c631999a54b336848e18cb06c80331` |
| `tests/v5.4.2-24/review/mutations-24-frozen-r7.py` | `d89f7cb5cda1be0542e92c5869310659` |
| `tests/v5.4.2-24/review/ci-24-frozen-r7.diff` | `c343828be614b5abf30a15944402ee0c` |
| `tests/v5.4.2-24/review/r6-to-r7.diff` | `e1e99c4822282eea7c6dd8e9eb719f41` |

The live copies (`sql/v5.4.2-24-unmatched-cash-and-pledges.sql`, `tests/v5.4.2-24/battery-24.sql`, `races/suspense-24.sh`, `mutations-24.py`) are identical today. `r6-to-r7.diff` is the patch, battery and mutation changes since round 6 (`r5-to-r6.diff` and earlier for the rounds before). The race script is unchanged from round 6. The ci diff is unchanged from round 1. The diff is -24's change to `tests/ci.sh` (PENDING, battery, races, invariants) and its port of `tests/v5.4.2-23/battery-23.sql`: an agency's payment there now names an agency.

## Background

The base is the `tally` database: `sql/tu.sql` through v5.4.2-27, with -23 (cash: reversals, derived positions, per-line application, overpayment credits), -27 (shortfall applications), -28 and -29 mirrored. In `ci.sh`, -24 applies after -25, -26 and -30 (all pending). -24 re-issues no existing function. It adds tables, nullable `payments` columns with CHECKs and two new triggers on `payments`, a CHECK on `tenants`, a trigger on `customer_program_enrollments`, and a description change on `program_types`.

What it is for:
- **CI-053** (GBM `application/canonical-invariants.md`): money that cannot be matched to a customer is held, never dropped, never applied to a guessed account, never revenue. It resolves to an account (with the reason recorded) or is refunded to the sender after the tenant's retention period.
- **CI-056**: pledges and suspense items are processed within a service level; past it, fail loud (an operator surface, a disconnection pause, reporting).

The rulings and sources:
- **Ryan, 2026-10-16** (DECISION-LOG): -24 is U (unmatched cash) and L (agency pledges), new tables that point at payments, additive.
- **Ryan, 2026-11-07** (DECISION-LOG): a refund of an agency's money goes to the agency, never the customer, for every agency. 10 TAC §6.312(f): "A Vendor Refund is program income and must be reimbursed to the Subrecipient, and not the customer." TDHCA's 2026 CEAP vendor agreement: 45 days to pay a pledge, during which the pledged portion is not delinquent.
- **The two workflow files:** GBM `application/configurable-rules/workflows/unapplied-cash-resolution.md` and `agency-pledge-posting.md` (their Open questions are the findings -24 answers).

The design is `application/wave2-build-2026-10-15/v5.4.2-24-design.md`. Section 0 lists the sources, sections 1–6 the calls settled by rule, section 6 the known limits L1–L5, and section 8 where the build differs from the plan. -26 (pending) names the collections conditions `agency_pledge` and `aged_suspense`; -24 supplies the rows the core reads for them.

## Rounds 1 to 6, and what changed

The plans are `application/wave2-build-2026-10-15/v5.4.2-24-r2-plan.md` to `-r7-plan.md`, one per round's findings; read them first. In round 6, Opus said ready (notes only), Fable ready (one test-only should-fix), and Codex not yet (one blocking item and two should-fix, all predicted; the author's runs of its nine probes confirmed every prediction). Each found every earlier finding closed.

Round 6's findings and their fixes, to check in particular:

- **A misposting return recorded before the ledger row that gives its money back** (r6 Codex B1). In an owner's history load a reversal can be recorded after its transaction began while the payment's status and the return keep the start stamp; a read at that instant saw the return without the reversal, and one receipt counted twice as known then. The return is now recorded no earlier than every row under the posting entry, read in the same walk as the dates: a start stamp that meets a later row retries (40001), a chosen earlier time is refused (23514). Checks P14i0 to P14i3; mutation M113. Is there still an instant, or a pair of date and instant, at which one receipt's money counts twice?
- **The separate reversal-date check removed** (r6 Codex S1): the reversal the payment names is a row of the tree, so the tree-date rule always beat it. P9b2 now expects the tree-date message; M74 removed; M112 is met first at P9b2.
- **The invariant lists a missing helper** (r6 Codex S2): `coalesce(has_function_privilege(…), false)`. Check I9d2 (-23's `cash_source_lock_key` dropped); mutation M114.
- **A conservation sweep** (r6 Fable S1): check S4b reads every receipt at every date and every recorded instant of the tenant's rows: held, plus what its payments still hold on the ledger, plus what left to a sender, a bank or a state, never exceeds the receipt. The author laid it over Codex's r5 and r6 probe 01 on the frozen r5 and r6 patches; it flags both. Is the sweep's sum right, and does it cover every way money leaves a receipt?

**Codex:** your round-6 probes and the author's runs are in `codex-r6-probes/` (`*.author-run.txt`). Every probe came out as you predicted.

Earlier rounds' fixes stand as before:
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
- **`battery-24.sql`:** 275 checks, one transaction, rolled back.
- **`races/suspense-24.sh`:** SU1–SU12, 24 results.
- **`mutations-24.py`:** 114 of 114 caught, each at its named check as the first failure.
- **`tests/ci.sh`:** 63 steps, all pass, with -24 pending last (after -25, -26 and -30), including battery -23 as ported.

## What to answer

1. **Is every round-6 finding closed, and every earlier one still?** Name any that is not, by its round and id. Then: does the patch implement the design and the rulings (CI-053, CI-056, Ryan's 11-07 rule within L5 and L6)?
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
7. **Known limits L1–L5.** Is any of them actually blocking?

## How to probe

**Opus and Fable** may query the running `tally-pg` read-only. For experiments, clone into your own scratch database (Opus `rv24opus`, Fable `rv24fable`):
1. `CREATE DATABASE <name> TEMPLATE tally`.
2. Revoke TEMP on the clone from PUBLIC, `tally_app` and `tally_core` right after creating it.
3. `docker cp` the frozen patch into the container, then apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

`tally` does not carry -25, -26 or -30. -24 applies over `tally` alone; to test beside them, apply -25, -26 and -30 strictly first, in that order.

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim must be a probe file in `tests/v5.4.2-24/review/codex-r7-probes/`. Each probe runs as the owner, on a fresh clone with frozen r7 applied, ends in ROLLBACK, and prints SQLSTATE and message for each caught error with RAISE NOTICE (a COPY probe must print its own error: psql leaves LAST_ERROR_SQLSTATE at 00000 after a failed COPY). The author will run the probes.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role.
- Do not run `mutations-24.py`; it uses the fixed name `m24`. Do not run `tests/ci.sh`.
- Run `suspense-24.sh` only against your own clone; it commits rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.

**Output:** `tests/v5.4.2-24/review/<you>-r7.md` (opus, fable, codex): verdict "ready" or "not yet"; items B (blocking), S (should fix), N (note), each marked executed or predicted, with the evidence.
