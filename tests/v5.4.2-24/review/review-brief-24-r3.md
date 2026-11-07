# Review brief: v5.4.2-24 r3 — unmatched cash and agency pledges

**Date:** 2026-11-07. **Kind:** patch review, round 3.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's files.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-24/review/patch-24-frozen-r3.sql` | `209260b584258dddfcea275ef3c21e55` |
| `tests/v5.4.2-24/review/battery-24-frozen-r3.sql` | `f7fab3032a7feabcb93610af52643057` |
| `tests/v5.4.2-24/review/suspense-24-frozen-r3.sh` | `88c9c30b4bb11609a4f7f684673e2129` |
| `tests/v5.4.2-24/review/mutations-24-frozen-r3.py` | `a28920276acc9a69358ee5dca05b3836` |
| `tests/v5.4.2-24/review/ci-24-frozen-r3.diff` | `c343828be614b5abf30a15944402ee0c` |
| `tests/v5.4.2-24/review/r2-to-r3.diff` | `4921c86edc06b7230dde48d41b139306` |

The live copies (`sql/v5.4.2-24-unmatched-cash-and-pledges.sql`, `tests/v5.4.2-24/battery-24.sql`, `races/suspense-24.sh`, `mutations-24.py`) are identical today. `r2-to-r3.diff` is the patch, battery and race changes since round 2 (`r1-to-r2.diff` the round before). The ci diff is unchanged from round 1. The diff is -24's change to `tests/ci.sh` (PENDING, battery, races, invariants) and its port of `tests/v5.4.2-23/battery-23.sql`: an agency's payment there now names an agency.

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

## Rounds 1 and 2, and what changed

Round 1 (all three not yet) is settled in `application/wave2-build-2026-10-15/v5.4.2-24-r2-plan.md`. Round 2: Opus and Fable said not yet, and each found every round-1 finding closed. Codex reached its usage limit before writing its review. Its nine probes were run by the author, and each prediction held (`codex-r2-probes/*.author-run.txt`). Round 2's fix list is `v5.4.2-24-r3-plan.md`. Read both plans first. Ryan, 2026-11-07 (DECISION-LOG): agency money in a deposit (L5) and in a credit with no typed source (L6) stays a known limit.

Check in particular that each round-2 finding is closed, and that the fixes open nothing:

- **Releases are ordered** (r2 Opus B1, Fable B1, Codex probe 03). Every disposition, negative ones included, runs `check_suspense_recorded_order`. Its union now also reads a payment's reversal time (`status_recorded_at` of voided and reversed payments).
- **Self-exclusion in the order check is per table** (Codex probe 02): `p_self_is_payment`.
- **A misposting return gives back at most what non-NSF rows reversed of the payment's posting entry** (Codex probe 01).
- **NaN** is refused on receipt, disposition and pledge amounts (Codex probe 07).
- **The invariant's reach** (r2 Opus S1, Fable S1, Codex probe 06):
  - 28 function bodies by md5;
  - their volatility, security and settings (`c_attrs`);
  - tally_app's EXECUTE on the helpers its guards call;
  - the seven tables' NOT NULL columns.

  The lists are regenerated from a build by `tests/v5.4.2-24/fill-manifest.py`. The mutation runner re-fills the md5s after each mutation, and a mutation of a pinned constraint removes its entry, so the behavioural check meets the mutation.
- **A load with foreign keys off.** The disposition and pledge-event guards check the receipt's or pledge's tenant.
- **Notes.** The stale comments are corrected. A payment carrying a provider id is written at READ COMMITTED (an application contract, recorded at the mirror). -23's tables accept NaN amounts; a payment from a receipt is still capped, and the general fix is a later money patch.

## Drafting calls still worth a look

- **The receipt's cap** (`check_suspense_receipt_cap`): for every date a payment or disposition falls on, the non-voided payments dated by then plus the dispositions dated by then never exceed the receipt.
- **Pledges**: the agreement and pay-by are chosen by the database; there is no cap on agency money; the state precedence; the lock between payments and events.
- **Where a refund goes** (`cash_money_agency`), within limits L5 and L6.
- **Tenancy**: two-column keys (R-12), RLS and FORCE RLS, grants.

## Results so far (reproduce them)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`; the second run is skipped by its marker, the table `suspense_receipts`. The patch's tail runs every earlier invariants function.
- **`battery-24.sql`:** 251 checks, one transaction, rolled back.
- **`races/suspense-24.sh`:** SU1–SU12, 24 results.
- **`mutations-24.py`:** 106 of 106 caught, each at its named check as the first failure.
- **`tests/ci.sh`:** 62 steps, all pass, with -24 pending last (after -25, -26 and -30), including battery -23 as ported.

## What to answer

1. **Is every round-2 finding closed (and every round-1 finding still)?** Name any that is not, by its round and id. Then: does the patch implement the design and the rulings (CI-053, CI-056, Ryan's 11-07 rule within L5 and L6)?
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

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim must be a probe file in `tests/v5.4.2-24/review/codex-r3-probes/`. Each probe runs as the owner, on a fresh clone with frozen r3 applied, ends in ROLLBACK, and prints SQLSTATE and message for each caught error with RAISE NOTICE (a COPY probe must print its own error: psql leaves LAST_ERROR_SQLSTATE at 00000 after a failed COPY). The author will run the probes.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role.
- Do not run `mutations-24.py`; it uses the fixed name `m24`. Do not run `tests/ci.sh`.
- Run `suspense-24.sh` only against your own clone; it commits rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.

**Output:** `tests/v5.4.2-24/review/<you>-r3.md` (opus, fable, codex): verdict "ready" or "not yet"; items B (blocking), S (should fix), N (note), each marked executed or predicted, with the evidence.
