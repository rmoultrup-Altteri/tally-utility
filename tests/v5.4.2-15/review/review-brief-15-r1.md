# Review brief — v5.4.2-15 deposits at parity, round 1 (frozen)

| Artefact | Lines | md5 |
|---|---|---|
| `sql/v5.4.2-15-deposits-law-to-core.sql` (= `review/patch-15-frozen-r1.sql`) | 1529 | `4f9468eb257d4423b88a545c157d6ed4` |
| `tests/v5.4.2-15/battery-15.sql` (= `review/battery-15-frozen-r1.sql`) | 1011 | `e2497c40e5a3ffb13464be9137ce0e58` |
| `tests/v5.4.2-15/mutations-15.py` | 241 | `7e3e661cb586c4cf31b0e37fb1105e5f` |
| `tests/v5.4.2-15/evidence-txn-15.sh` | 68 | `8b8e6a20a12ad27b808f2db69a7ae3eb` |
| `tests/v5.4.2-15/races/due-mutex-15.sh` | 90 | `bb643764982ae428db1441c03d25b600` |

Nothing in this table changes while the round is open. Three reviewers (Opus, Fable, Codex) work independently on the same frozen hash.

## What this patch is

v5.4.2-06 (landed; `sql/v5.4.2-06-account-lifecycle-and-deposits.sql`) built Texas's deposit law (16 TAC §7.45) into triggers, a function and a view. Ryan ruled on 2026-09-28:
- **The schema represents; the C# core evaluates.** Triggers protect record integrity. They never compute law: who may be charged a deposit, the cap's size, when interest accrues and how much, when a refund falls due.
- **A Texas-only launch is not a Texas-only architecture.** Law is platform-held, dated rows keyed by (state, service, class, basis). Texas is only the first set of rows.

v5.4.2-15 drops -06's law and keeps its record integrity, following the v5.4.2-13 pattern (`sql/v5.4.2-13-backbilling-caps.sql` §5, §9).

Read, in this order:
1. `application/deposits-parity-rescope-2026-09-30.md`: the design. §1 keep, §2 drop, §3 rule tables (§3.5 the return-due record), §3.6 as built, §4 Ryan's decisions R-D1 to R-D3.
2. The patch header, which lists what the database still refuses and one stated **DIVERGENCE** (accrued interest must be credited by the deposit's last event).
3. `application/deposits-rules-for-the-core.md`: everything the dropped code decided, now the core's.

## The two questions — and only these

**Q1. STORE.** Can the schema hold everything deposit law and the core need, without a schema change?
- Every rule parameter the sources need (decision tables #53–#55 in GBM `application/configurable-rules/decision-tables/deposit-*.md`, and rules-for-the-core §1) is on `deposit_rules` or a vocabulary.
- Every **input** the core needs, and every **output** it produces, is recorded: the deposit's rule and cap; the accrual's rate row, rule row and core version; the return-due row, its evidence and withdrawals. Each output names the rule row and core version.
- A second state with different law fits as rows alone. Battery group Z (fictional `ZZ`) is the existing proof. **Find a plausible statutory shape that does NOT fit.**

**Q2. PROTECT.** Are the records protected, whoever writes, as `tally_app`?
- Tenant isolation on every new table and view.
- A deposit's identity, rule and cap are frozen; status is only a projection.
- The sub-ledger's arithmetic (header list).
- An accrual's citations are coherent.
- Law rows are cited, never overlap, are never edited (only a stamped close, never on or before a date they are cited for), and the app can't write them.
- Return-due rows: at most one live row per deposit, serialised on the deposit row; evidence in the due row's own transaction only; append-only; a withdrawal once each.
- Stamps come from the database, not the caller.

Also flag any **state literal, or a basis, class or waiver-class name branch,** left in a trigger, function or CHECK. The stopping rule is that no patch lands with one. `legacy_unknown` in comments and seeds is expected.

## Out of scope (do not report)

- Whether a deposit, cap, interest amount or refund is **lawful**. That is the core's job by design (design §2). "The DB accepts an unlawful accrual" is not a finding.
- Kyle questions K1–K8 and the disagreements DG1–DG9 (rules-for-the-core §7), and residuals R1–R7 at the end of the patch. They are known and stated.
- The account-lifecycle half of -06 (out of scope per design).
- Contrived multi-step attacker chains. The bar: a plausible app bug, or a plausible second state, that the schema gets wrong.

## Rules

- Do **not** edit anything in the repo. Write probes in your scratch space only.
- Your database is built: `tally` (the -14 build) plus the frozen patch, applied strictly. Use `docker exec -i tally-pg psql -U tally -d <your db>`, and act as `SET ROLE tally_app` (with `SET LOCAL app.user_id`) for app-path probes. The battery's fixtures show the minimum rows each table needs (invoices need `location_id`).
  - Opus: `rev15_opus`. Fable: `rev15_fable`. Codex: `rev15_codex`.
  - Clone yours with `CREATE DATABASE x TEMPLATE rev15_<you>` if you need a fresh copy. **Never write to `tally` or another reviewer's database.**
- Every finding needs a **runnable repro** and the observed result, or it isn't a finding.
- Rank by severity. Say which question (Q1/Q2) each finding answers.
- **Verdict:** "sound enough to mirror" or "not yet", with the findings that block it.
