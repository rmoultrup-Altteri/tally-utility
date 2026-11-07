# Review brief: v5.4.2-24 r1 — unmatched cash and agency pledges

**Date:** 2026-11-07. **Kind:** patch review, round 1.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's files.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-24/review/patch-24-frozen-r1.sql` | `eae62ab08914d6871f7688f329a13660` |
| `tests/v5.4.2-24/review/battery-24-frozen-r1.sql` | `e2c82852c68e399021ea31a77773d1a8` |
| `tests/v5.4.2-24/review/suspense-24-frozen-r1.sh` | `bb428ea60eb52ecb07a52921f1b23ca7` |
| `tests/v5.4.2-24/review/mutations-24-frozen-r1.py` | `2e5cd7660bed4aee12cc3bc77b8b1d4a` |
| `tests/v5.4.2-24/review/ci-24-frozen-r1.diff` | `c343828be614b5abf30a15944402ee0c` |

The live copies (`sql/v5.4.2-24-unmatched-cash-and-pledges.sql`, `tests/v5.4.2-24/battery-24.sql`, `races/suspense-24.sh`, `mutations-24.py`) are identical today. The diff is -24's change to `tests/ci.sh` (PENDING, battery, races, invariants) and its port of `tests/v5.4.2-23/battery-23.sql`: an agency's payment there now names an agency.

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

## Drafting calls to check in particular

- **The receipt's cap** (`check_suspense_receipt_cap`). For every date a payment or a disposition falls on: the live payments dated by then, plus the dispositions dated by then (undos netted), never exceed the receipt. A payment counts unless voided or reversed (reversed = posted to the wrong customer, so its share comes back), and an NSF one stays counted. Is "every date a row falls on" enough? Is "reversed gives back, NSF does not" right for every way -23 lets a payment reach `reversed` (a return code is allowed on reversed too)? Can a status move, rather than an insert, push a receipt over its cap?
- **Payments from a receipt.** Dated on or after `received_on`, effective no later. They carry the receipt's channel, source system and instrument, never their own provider id, and the receipt's agency where it names one. The checks run BEFORE INSERT (and on an effective-date update). The cap runs AFTER INSERT under the receipt's advisory lock. Is any path around them: COPY, a multi-row insert across receipts, a writable CTE, an update of `payment_date` (-23 freezes it from insert), a superuser history load?
- **One provider transaction across receipts and payments** (`check_provider_transaction_once`). A receipt is checked against receipts and payments; a payment against receipts only (a payment-payment duplicate is left to -19's unique index, which runs after -19's lineage CHECKs). Is the advisory lock on the id enough under READ COMMITTED? Does skipping refunds (amount ≤ 0) open anything?
- **Pledges.** The agreement and pay-by are the database's (the agreement in force on `pledged_on`; no agreement gives NULL, recorded anyway). Events end a pledge once; a lapse only after pay-by has passed everywhere (UTC-12). `recorded_in_error` is allowed only while no non-voided payment names the pledge, and none may afterwards. Paid is what the naming payments received (`payment_position_as_of`), with no cap: an agency's money is never refused. Are the state precedence (void, paid, event from its date, no_agreement, overdue, open) and the lock between payments and events right?
- **Where a refund goes** (`cash_money_agency`). It traces a refund's money to an agency's payment, or to the customer, through -23's and -27's lineage (overpayment credit, refund reissue, shortfall reissue). Is any lineage missed: a credit of another origin holding agency money, a deposit (known limit L5), a transfer credit, a shortfall application moving agency money onto a customer's bounced payment, a refund of a refund?
- **Locks.** Advisory, keyed by `cash_source_lock_key` with the kinds `suspense_receipt`, `agency_pledge` and `agency`. `tally_app` holds no row-lock privilege on the new tables. Order: the tenant's close head (the freeze), the payment's own -23 locks, then the receipt or pledge. Every writer that reads under a lock is pinned to READ COMMITTED. Is any cap read without its lock? Can -23's locks and these deadlock without a retry?
- **Tenancy.** Every key between tenant tables carries `tenant_id` on both sides (R-12), and the invariant checks it generically. RLS and FORCE RLS on all seven tables. Grants: `tally_app` SELECT and INSERT, plus UPDATE of the retirement and withdrawal stamps on the two setup tables.
- **Settings as `tenants.settings` keys** with a CHECK, read from `tenant_configuration_history`. A new column would have extended the history table's known-key CHECK, which -22's and -23's invariants list exactly. Unset is allowed, and the aged reader raises while it is.

## Results so far (reproduce them)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`; the second run is skipped by its marker, the table `suspense_receipts`. The patch's tail runs every earlier invariants function.
- **`battery-24.sql`:** 188 checks, one transaction, rolled back.
- **`races/suspense-24.sh`:** SU1–SU7, 12 results.
- **`mutations-24.py`:** 71 of 71 caught, each at its named check as the first failure.
- **`tests/ci.sh`:** 62 steps, all pass, with -24 pending last (after -25, -26 and -30), including battery -23 as ported.

## What to answer

1. **Does the patch implement the design and the rulings?** Name any requirement missed or half-done (CI-053, CI-056, the design's sections, Ryan's 11-07 rule).
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

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim must be a probe file in `tests/v5.4.2-24/review/codex-r1-probes/`. Each probe runs as the owner, on a fresh clone with frozen r1 applied, ends in ROLLBACK, and prints SQLSTATE and message for each caught error with RAISE NOTICE (a COPY probe must print its own error: psql leaves LAST_ERROR_SQLSTATE at 00000 after a failed COPY). The author will run the probes.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role.
- Do not run `mutations-24.py`; it uses the fixed name `m24`. Do not run `tests/ci.sh`.
- Run `suspense-24.sh` only against your own clone; it commits rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.

**Output:** `tests/v5.4.2-24/review/<you>-r1.md` (opus, fable, codex): verdict "ready" or "not yet"; items B (blocking), S (should fix), N (note), each marked executed or predicted, with the evidence.
