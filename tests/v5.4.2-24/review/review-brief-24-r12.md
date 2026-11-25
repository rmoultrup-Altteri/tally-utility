# Review brief: v5.4.2-24 r12 — unmatched cash and agency pledges

**Date:** 2026-11-24. **Kind:** patch review, round 12 (narrow: the round-11 fixes).
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's files.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-24/review/patch-24-frozen-r12.sql` | `37630681b0dd63235ca3ab5c11b0b326` |
| `tests/v5.4.2-24/review/battery-24-frozen-r12.sql` | `96b21ecde4ab064aef61eb7285c0afa7` |
| `tests/v5.4.2-24/review/suspense-24-frozen-r12.sh` | `360dea4db148825d696134bfa30e0502` |
| `tests/v5.4.2-24/review/mutations-24-frozen-r12.py` | `87d1bec061a3ae71c64d20f335525f8e` |
| `tests/v5.4.2-24/review/ci-24-frozen-r12.diff` | `ec30f74364228bf3f325a1958583d01b` |
| `tests/v5.4.2-24/review/r11-to-r12.diff` | `ecb5feb6ae0fe7f9360bc6e4f002e186` |

The live copies (`sql/v5.4.2-24-unmatched-cash-and-pledges.sql`, `tests/v5.4.2-24/battery-24.sql`, `races/suspense-24.sh`, `mutations-24.py`) are identical today. `r11-to-r12.diff` is the patch, battery and mutation changes since round 11 (`r10-to-r11.diff` and earlier for the rounds before). The race script and the ci diff are unchanged from round 11.

## Background

The base is the `tally` database: `sql/tu.sql` through v5.4.2-30, with -23 (cash: reversals, derived positions, per-line application, overpayment credits), -27 (shortfall applications), -28, -29 and -30 (tax levies). In `ci.sh`, -24 applies after -25 and -26 (both pending). -24 re-issues no existing function. It adds tables, nullable `payments` columns with CHECKs and two triggers on `payments`, one trigger on `account_ledger` (r11), a CHECK on `tenants`, a trigger on `customer_program_enrollments`, and a description change on `program_types`.

What it is for:
- **CI-053** (GBM `application/canonical-invariants.md`): money that cannot be matched to a customer is held, never dropped, never applied to a guessed account, never revenue. It resolves to an account (with the reason recorded) or is refunded to the sender after the tenant's retention period.
- **CI-056**: pledges and suspense items are processed within a service level; past it, fail loud (an operator surface, a disconnection pause, reporting).

The rulings and sources:
- **Ryan, 2026-10-16** (DECISION-LOG): -24 is U (unmatched cash) and L (agency pledges), new tables that point at payments, additive.
- **Ryan, 2026-11-07** (DECISION-LOG): a refund of an agency's money goes to the agency, never the customer, for every agency. 10 TAC §6.312(f): "A Vendor Refund is program income and must be reimbursed to the Subrecipient, and not the customer." TDHCA's 2026 CEAP vendor agreement: 45 days to pay a pledge, during which the pledged portion is not delinquent.
- **The two workflow files:** GBM `application/configurable-rules/workflows/unapplied-cash-resolution.md` and `agency-pledge-posting.md`.

The design is `application/wave2-build-2026-10-15/v5.4.2-24-design.md` (section 0 the sources, sections 1–6 the calls settled by rule, section 6 the known limits L1–L6, section 8 where the build differs from the plan). -26 (pending) names the collections conditions `agency_pledge` and `aged_suspense`; -24 supplies the rows the core reads for them.

## Round 11, and what changed

Read `application/wave2-build-2026-10-15/v5.4.2-24-r12-plan.md` first. Round 11: Opus ready (one should-fix, four notes), Codex ready (one should-fix), Fable not yet (one blocking, two should-fix). The author reproduced Fable's blocking item on frozen r11, and ran all 13 Codex probes (as predicted; probe 08's last steps ran in an author variant, `08b`, because the probe's own helpers were not executable by `tally_void`).

What changed, to check:

1. **A bank code over rows filed beneath the named row's undo** (Fable r11 B1). r11 measured what remains of the named row's subtree; now `reversed` takes a bank code (where the share is above 0) only if the named row itself is at least the payment and nothing is filed beneath it. Stricter for one route: a whole reversal undone and taken again beneath the undo ends without a code, its money comes back, and the bank's part is `bank_returned` at the receipt. Tests P23, P23b–d; mutations M168, M169.
2. **Born posted** (Fable r11 S1): a receipt's payment is born `pending` or `voided`. Test O7c; mutation M170.
3. **A receipt's deposit payment** (all three): fixtures Rd1, Rd6, Re1 (D1–D8, D4b); `fromr()` takes `p_deposit`; mutations M171–M175, one per walk that names `'deposit'`.
4. **The conservation check S4c** (Codex r11 S1, Fable N1, Opus N2): moved to the battery's end; walks each receipt payment's posting tree once, by link (every row in or under the first nsf row that takes money, once); every date anything of T1 is dated on, read now; every receipt (S4d); a pending payment's money counted. Fixtures Re7 (P24, a bounce re-recorded under its undo) and Red (P24b, a bounce with no reference).
5. **Comments** on the lock order both new checks rely on (Opus r11 N1).

Four r8–r9 mutations (M118, M129, M138 at D2; M143 at P24b) are now first caught by the new deposit and link-only fixtures, which sit earlier in the battery than their old checks; their named checks were moved. Each new check tests the same defect (a payment listed with no share at the day before it; a share at the coordinates; what the bank took counted as owed back).

Put to you directly:
1. **Is the new code rule right in every shape?** Can a coded `reversed` still hide a misposted part (another level down, an nsf row beneath the named row, a negative row beneath it, a later row, a named row typed nsf)? Is anything legitimate now refused that should not be, other than the route in item 1?
2. **Is S4c now a sound oracle?** Attack it with a shape the patch gets right and S4c gets wrong, or the reverse.
3. **Do the deposit fixtures and M171–M175 test what they claim?**

Earlier rounds' fixes stand as before (the r11 brief lists them).

## Drafting calls still worth a look

- **The receipt's cap** (`check_suspense_receipt_cap`): for every date a payment or disposition falls on, the non-voided payments dated by then plus the dispositions dated by then never exceed the receipt.
- **Pledges**: the agreement and pay-by are chosen by the database; there is no cap on agency money; the state precedence; the lock between payments and events.
- **Where a refund goes** (`cash_money_agency`), within limits L5 and L6.
- **Tenancy**: two-column keys (R-12), RLS and FORCE RLS, grants.

## Results so far (reproduce them)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`; the second run is skipped by its marker, the table `suspense_receipts`. The patch's tail runs every earlier invariants function.
- **`battery-24.sql`:** 352 checks, one transaction, rolled back.
- **`races/suspense-24.sh`:** SU1–SU15b, 29 results.
- **`mutations-24.py`:** 169 of 169 caught, each at its named check as the first failure (the full run caught 165; M118, M129, M138 and M143 were first caught by the new fixtures, re-pointed, and caught alone).
- **`tests/ci.sh`:** 61 steps, all pass (2026-11-24, r12, on `tally` carrying -30), with -24 pending last (after -25 and -26), including battery -23 as ported.

## What to answer

1. **Is every round-11 finding closed, and every earlier one still?** Name any that is not, by its round and id. Then: does the patch implement the design and the rulings (CI-053, CI-056, Ryan's 11-07 rule within L5 and L6)?
2. **Is there a path around any new rule?** Consider, beside the three questions above (the full list stands; spend most of the round on the changes):
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

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim must be a probe file in `tests/v5.4.2-24/review/codex-r12-probes/`. Each probe runs as the owner, on a fresh clone with frozen r12 applied, ends in ROLLBACK, and prints SQLSTATE and message for each caught error with RAISE NOTICE (a COPY probe must print its own error: psql leaves LAST_ERROR_SQLSTATE at 00000 after a failed COPY). The author will run the probes.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role.
- Do not run `mutations-24.py`; it uses the fixed name `m24`. Do not run `tests/ci.sh`.
- Run `suspense-24.sh` only against your own clone; it commits rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.

**Output:** `tests/v5.4.2-24/review/<you>-r12.md` (opus, fable, codex): verdict "ready" or "not yet"; items B (blocking), S (should fix), N (note), each marked executed or predicted, with the evidence.
