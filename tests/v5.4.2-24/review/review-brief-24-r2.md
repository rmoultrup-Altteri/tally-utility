# Review brief: v5.4.2-24 r2 — unmatched cash and agency pledges

**Date:** 2026-11-07. **Kind:** patch review, round 2.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's files.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-24/review/patch-24-frozen-r2.sql` | `9b440cd131f263702c808b4ef27e5229` |
| `tests/v5.4.2-24/review/battery-24-frozen-r2.sql` | `46d5e07646dca3870eccc8576a6ea6e0` |
| `tests/v5.4.2-24/review/suspense-24-frozen-r2.sh` | `f0cd45f04fe5e0e6ff2c3712b09627e3` |
| `tests/v5.4.2-24/review/mutations-24-frozen-r2.py` | `e366080d8a576c172cf90fd2ada7f0e0` |
| `tests/v5.4.2-24/review/ci-24-frozen-r2.diff` | `c343828be614b5abf30a15944402ee0c` |
| `tests/v5.4.2-24/review/r1-to-r2.diff` | `259bc084f328919a76188441aceabfa4` |

The live copies (`sql/v5.4.2-24-unmatched-cash-and-pledges.sql`, `tests/v5.4.2-24/battery-24.sql`, `races/suspense-24.sh`, `mutations-24.py`) are identical today. `r1-to-r2.diff` is the patch, battery and race changes since round 1. The ci diff is unchanged from round 1. The diff is -24's change to `tests/ci.sh` (PENDING, battery, races, invariants) and its port of `tests/v5.4.2-23/battery-23.sql`: an agency's payment there now names an agency.

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

## Round 1 and what changed

Round 1: Opus, Fable and Codex all said not yet. The fix list, with every finding and how it was settled, is `application/wave2-build-2026-10-15/v5.4.2-24-r2-plan.md`. Read it first. Codex's eleven probes were run by the author (`codex-r2-probes/*.author-run.txt`); every prediction held. Ryan, 2026-11-07 (DECISION-LOG): agency money in a deposit (L5) and in a credit with no typed source (L6) stays a known limit.

Check in particular that each round-1 finding is closed, and that the fixes open nothing:

- **A reversal alone gives nothing back** (r1 Codex B3, Opus B1, B2). A payment from a receipt counts unless voided. Money comes back only by a `misposting_returned` disposition: a payment of the receipt reversed with no return code, dated on or after the reversal's ledger date, at most its amount, once, never undone. A return code written later on such a payment is refused under the receipt's lock. Can money come back twice, at the wrong date, or after a bank's take-back recorded another way?
- **Recorded order** (r1 Codex B4: `check_suspense_recorded_order`). A payment from a receipt, and a positive disposition, are recorded no earlier than every row of the receipt (dispositions, payments, a void's recorded time): 40001 for a writer begun before, 23514 for a chosen time. Is any spending row missed, or any release that should be ordered?
- **Provider ids** (r1 Codex B1, B2, B5; Opus B3; Fable B1, B2). The READ COMMITTED pin is inside the check. Self-exclusion is within a table only. A payment's id written later is checked. A receipt's payment keeps the receipt's instrument on update.
- **Clocks** (r1 Codex B6). `b_enforce_recorded_at` on all seven tables; finite dates by CHECK.
- **Settings** (r1 Opus S2). A value CHECK on `tenant_configuration_history` for the two keys (1–9999 days); the reader raises on an unreadable value.
- **The invariant** (r1 Codex S1, Opus S1, Fable S1). Exact constraint and unique-index definitions, required stamp grants, and an md5 of 19 function bodies (filled from the patch by `tests/v5.4.2-24/fill-body-md5.py`; the mutation runner re-fills it after each mutation so the behavioural check, not the body check, meets it).
- **Smaller items.** A pledge toward a bill needs a payment restricted to it. A retired agency's name may be reused. A pledge checks its customer's tenant. Two messages are corrected. The header states the lock and retry rule and limits L5 and L6.

## Drafting calls still worth a look

- **The receipt's cap** (`check_suspense_receipt_cap`): for every date a payment or disposition falls on, the non-voided payments dated by then plus the dispositions dated by then never exceed the receipt.
- **Pledges**: the agreement and pay-by are chosen by the database; there is no cap on agency money; the state precedence; the lock between payments and events.
- **Where a refund goes** (`cash_money_agency`), within limits L5 and L6.
- **Tenancy**: two-column keys (R-12), RLS and FORCE RLS, grants.

## Results so far (reproduce them)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`; the second run is skipped by its marker, the table `suspense_receipts`. The patch's tail runs every earlier invariants function.
- **`battery-24.sql`:** 234 checks, one transaction, rolled back.
- **`races/suspense-24.sh`:** SU1–SU10, 21 results.
- **`mutations-24.py`:** 95 of 95 caught, each at its named check as the first failure.
- **`tests/ci.sh`:** 62 steps, all pass, with -24 pending last (after -25, -26 and -30), including battery -23 as ported.

## What to answer

1. **Is every round-1 finding closed?** Name any that is not, by its round-1 id. Then: does the patch implement the design and the rulings (CI-053, CI-056, Ryan's 11-07 rule within L5 and L6)?
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

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim must be a probe file in `tests/v5.4.2-24/review/codex-r2-probes/`. Each probe runs as the owner, on a fresh clone with frozen r2 applied, ends in ROLLBACK, and prints SQLSTATE and message for each caught error with RAISE NOTICE (a COPY probe must print its own error: psql leaves LAST_ERROR_SQLSTATE at 00000 after a failed COPY). The author will run the probes.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role.
- Do not run `mutations-24.py`; it uses the fixed name `m24`. Do not run `tests/ci.sh`.
- Run `suspense-24.sh` only against your own clone; it commits rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.

**Output:** `tests/v5.4.2-24/review/<you>-r2.md` (opus, fable, codex): verdict "ready" or "not yet"; items B (blocking), S (should fix), N (note), each marked executed or predicted, with the evidence.
