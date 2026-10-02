# Review brief — v5.4.2-15 deposits at parity, round 2 (frozen)

| Artefact | Lines | md5 |
|---|---|---|
| `sql/v5.4.2-15-deposits-law-to-core.sql` (= `review/patch-15-frozen-r2.sql`) | 2196 | `026e25d22ca8e25c396168876c795db9` |
| `tests/v5.4.2-15/battery-15.sql` (= `review/battery-15-frozen-r2.sql`) | 1451 | `c5d2ff85f2cfe83432790adbf7ae608e` |
| `tests/v5.4.2-15/mutations-15.py` | 344 | `441d07a2e84f229a0ee15eb40cbc9441` |
| `tests/v5.4.2-15/evidence-txn-15.sh` | 68 | `1f4b73ab4a3a53a3f80560757f9c156b` |
| `tests/v5.4.2-15/races/due-mutex-15.sh` | 195 | `87814b46f95a8db06e8cf1faa8928699` |

Nothing in this table changes while the round is open. Three reviewers (Opus, Fable, Codex) work independently on the same frozen hash.

## Where this round starts

Round 1 (hash `4f9468eb`) ended "not yet" from all three reviewers. Read, in this order:
1. `review/review-findings-15-r1.md`: every round-1 finding, its disposition, and Ryan's decisions B1, B2 and B3.
2. `review/proposal-b3-waiver-reach.md`: the waiver-reach design, already reviewed by the three of you before it was built.
3. The patch header: what changed, the full list of what the database refuses, the DIVERGENCE, and residuals R1–R12.
4. `application/deposits-parity-rescope-2026-09-30.md` §3.7 and `application/deposits-rules-for-the-core.md` §2.1, §2.2 and §5.5.

The ground rules are unchanged:
- the schema represents and the C# core evaluates;
- a Texas-only launch is not a Texas-only architecture;
- nothing is live, so every design is permanent.

## What to check — three questions

**Q0. DID ROUND 1's FIXES HOLD?** For each of A1–A15 and B1–B3, does the revision actually do what the disposition says? Re-run your round-1 probes if you have them:
- Opus: `/private/tmp/claude-501/review15-opus/`.
- Fable: `/private/tmp/claude-501/review15-fable/`.
- Codex: the five R-1..R-5 scripts in your round-1 report.

  The fixtures need updating: a deposit with a cap now also names `cap_source`. A fix that is partial, or that moved the hole, is a finding.

**Q1. STORE.** Can the schema hold every rule parameter, input and output without DDL? Pay most attention to the new surfaces:
- waiver reach per (rule, waiver class, trigger), with an effect;
- the utility's tariff waiver grounds, with their own scope and effect;
- cap source and `cap_other_held`;
- class-specific rates;
- partial returns;
- the refund lookback and disqualifiers;
- the time-held evidence kind;
- reasons tied to rules.

  Find a plausible statutory or tariff shape that does NOT fit.

**Q2. PROTECT.** Are the records protected, whoever writes, as `tally_app`? The new guards to attack:
- the row-version due mutex;
- the rate advisory lock with its READ COMMITTED pin;
- `deposit_rule_citable()` (B1);
- the part-in-the-rule's-transaction rule;
- the tariff-ground close floor;
- the chronology checks;
- the evidence status and date checks.

Also check for **NULL legs** in every CHECK and every trigger `IF`. Two were found and fixed during the revision, so there may be more. Also flag any **state, basis, class or waiver-class name** in a guard.

## Out of scope (do not report)

- Whether a deposit, cap, interest amount or refund is lawful (the core's, by design).
- Kyle questions K1–K8, DG1–DG9, and residuals R1–R12. R12 lists Ryan's open follow-ups: a record of a waived deposit, an explicit "nothing reaches" flag, fail-open on missing input, the pick between two waivers, and a waiver after a deposit is held.
- The DIVERGENCE (Ryan has it).
- Contrived multi-step attacker chains. The bar: a plausible app bug, or a plausible second state or tariff, that the schema gets wrong.

## Rules

- Do **not** edit anything in the repo. Write probes in your scratch space only.
- Your database is built: `tally` plus the frozen patch, strict-applied, with **TEMP revoked**.
  - Opus: `rev15r2_opus`. Fable: `rev15r2_fable`. Codex: `rev15r2_codex`.
  - To clone it, use `CREATE DATABASE x TEMPLATE rev15r2_<you>`, then **`REVOKE TEMP ON DATABASE x FROM PUBLIC, tally_app`**: a clone does not copy the database ACL.
  - Never write to `tally` or another reviewer's database. Drop your clones when done.
- Every finding needs a **runnable repro** and the observed result, or it isn't a finding.
- Rank by severity. Tag each finding Q0, Q1 or Q2.
- **Verdict:** "sound enough to mirror" or "not yet", with the findings that block it.
