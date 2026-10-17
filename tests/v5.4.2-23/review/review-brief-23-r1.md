# Review brief: v5.4.2-23 r1 — cash: the general reversal cap, derived positions, per-line payment application, overpayment approvals, the within-bill order

**Date:** 2026-10-17. **Kind:** patch review, round 1.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's files.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-23/review/patch-23-frozen-r1.sql` | `bf3b0967108fd0b8b5f91fca698fa750` |
| `tests/v5.4.2-23/review/battery-23-frozen-r1.sql` | `7d5b575d23e16f5bb384a4a0ab152313` |
| `tests/v5.4.2-23/review/cash-23-frozen-r1.sh` | `92e5424766121b8362dfdc21dc2dc9d5` |
| `tests/v5.4.2-23/review/mutations-23-frozen-r1.py` | `76de756ce7c9c57cb1d46ed6b5b6e0d2` |
| `tests/v5.4.2-23/review/older-tests-23-frozen-r1.diff` | `9a513066de9b060a6e71ac3266075c90` |

Today the live copies are identical to the frozen ones. Review the frozen copies. The live copies are `sql/v5.4.2-23-cash-reversals-positions-application.sql`, `tests/v5.4.2-23/battery-23.sql`, `tests/v5.4.2-23/races/cash-23.sh` and `tests/v5.4.2-23/mutations-23.py`. The diff holds every change -23 made to earlier tests (batteries -10 to -22, races -19, -21 and -22), measured against the -22 mirror commit `eef5122`.

## Background

The base is the `tally` database: `sql/tu.sql` through v5.4.2-22. -22 added accounting periods as freeze boundaries, the close (`tally_close`), aging, and the write-off recovery cap. That cap was R-02 for one case only.

These are the rulings -23 builds (in `gas-billing-memory/application/`):
- **R-02** (`kyle-decisions-2026-10-15-waves-1-to-7-and-texas-first.md`): a reversal names its entry and is capped by it.
- **R-05** (same file): money is add-only; a correction is a reversal plus a new row.
- **R-06** (same file): application per bill line; a payment, a line and an undo are each capped.
- **K-05:** oldest first; a deposit is not applied to bills; Texas law sets no within-bill order, so the utility's tariff does.
- **K-07:** no assumed default.
- **D7-1 b:** an agency payment's restriction.
- **CI-050:** regulated charges first.
- **Q1 (a):** status columns are kept; each move names the row behind it.

The requirements are X1–X4, M1–M4, A1–A6 and C1–C2 in `application/wave2-build-2026-10-15/v5.4.2-23-design.md`, the design and a mapping to checks in one file. The triage, including four drafting calls settled by standing rule, is in `application/wave2-build-2026-10-15/source-inventory-wave2.md` ("-23 triage"). The decisions are in `application/DECISION-LOG.md`:
- 2026-10-16: cash split into -23 and -24;
- 2026-10-17: Ryan kept the reversal depth bound at 1,000.

The residuals left on purpose are R1–R8 in the patch header.

**The split.** -24 holds U (unmatched cash) and L (agency pledges). Neither is a gap in -23.

**One open question, for Kyle, not for you.** An agency restriction may point at an unregulated line while regulated charges are unpaid. The patch records both answers (`restriction`, and `floor_over_restriction` naming the line it took instead) and decides neither. Review that it records both faithfully.

## Drafting calls to check in particular

- **The general cap (X2).** For every entry on the new row's path up to the root, the net of that entry's tree stays between 0 and minus its amount, at every date (rows of one date net together). The check is one walk down from the root. It carries `m`, the number of path entries above each row, and nets pairs (path ancestor j, row) per j by date. Is it the same check as netting each ancestor's subtree separately? Look at siblings, at rows of one date, at an earlier-dated row under a later one, and at a row added on a branch off the path.
- **One lock per tree, on the root,** taken after the tenant's close head. The void (`void_invoice`) locks the root of its charge, then reverses what is left (`ledger_entry_remaining`), not `-(amount_due)`. Can two writers on one tree ever see different roots, or a reversal slip between the void's read and its insert?
- **The recorded-order rule,** made general. A row may not be recorded before a row already in its tree, its source or its line: 40001 for a row stamped at its transaction's start, 23514 for a chosen time. Every ledger row is recorded at a finite time already reached. Is that enough for the as-of positions to be reproducible at any `(money date, recorded instant)`?
- **Positions replace counters (M1).** `payment_position_as_of`, `customer_credit_position_as_of`, `invoice_line_position_as_of` and `invoice_position_as_of` all require their coordinates. Does any read fall back to live state? Is a refund's status, read as it is now (R2), a real hole?
- **Write-once and status moves (M2, M3).** The fixed and write-once column lists. Forward-only moves, each naming its cause in `status_cause_id`. "Guard the act" on nsf, reversed, voided and refunded. Can a column that defines the money move, or a move skip its cause?
- **The caps (A3, C1).** Payment and credit sources: applications, overpayment credits and pending or posted refunds, under a per-source advisory lock. A line, under its own lock, taken after the source's. An undo never exceeds what it undoes. Is any draw left out of `cash_source_draws`? Is the lock order (head, then tariff row shared through `rule_row_cite`, then source, then line) always followed, including by the payment and credit status moves?
- **Overpayment approvals (C1).** The FK on five columns and one credit per approval. Can a credit draw more than its approval or its payment?
- **The within-bill order (A5).** A law table plus a tariff table on the rule-terms convention. The Texas rows delegate to the utility. The tariff's insert check covers both "own utility" and completeness. Is the close floor (the latest application citing the row) right?
- **The line class (A1b).** `invoice_line_items.regulatory_class` is NOT NULL, checked at issue against a one-off charge or a rate item's version (`enforce_invoice_line_class`, deferred). Is it gated like `enforce_invoice_line_arithmetic`?
- **The depth bound.** It stays 1,000. Appending one row at depth d costs about d² (measured: 70–170 ms at 500 deep, 0.3–0.8 s at 1,000). A whole chain posted in one statement costs about d³. The cap's walk up fails closed if it stops before the root. Is any walk left unbounded or unpinned (`enable_seqscan`, `enable_hashjoin` and `enable_mergejoin` off)?

## Results so far (reproduce them)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`. The second run is skipped by its marker, the table `customer_credit_approvals`.
- **`tests/ci.sh`:** passes in full (38 steps) with -23 pending. That covers:
  - batteries 09–23 and the -15/-17/-18 runners;
  - every race script;
  - all eight invariant steps, the new `assert_cash_guard_invariants()` included.
- **`battery-23.sql`:** 107 checks, one transaction, rolled back. **`races/cash-23.sh`:** CR1–CR8 (11 results).
- **`mutations-23.py`:** 71 of 71 caught, each at its named check as the first failure of any kind.
- **Earlier tests changed** (in the diff):
  - -19: payment moves and refunds; races C8/C9, now one-session refusals;
  - -21: credits, the reversal type check, line class;
  - -22: cross-customer and same-sign reversals, dates, recorded time, the depth tests R10g, R11 and R11b–R11e;
  - -10, -11, -13, -19, -20 and -21: `regulatory_class` added to line inserts.

  Patch residual R8 names them. Check that every change follows a rule -23 adds and that none just loosens a test.

## What to answer

1. **Does the patch implement the design and the rulings?** Name any requirement missed or half-done.
2. **Is there a path around any new rule?** Consider:
   - a reversal past its entry's cap at any date, or of the wrong customer, sign or date;
   - money applied past a payment, a credit, a line or an undo;
   - a payment or credit changed in place;
   - a status moved without its cause, or backward;
   - bounced or unarrived money still applied;
   - a credit without an approval, or drawing more than it;
   - an application from a deposit or a pending payment, to a draft or void bill, or to a credit line;
   - a restriction ignored or claimed falsely;
   - a tariff of another utility, or not in force;
   - a line issued with the wrong class.

   Try each role, isolation level and statement shape (multi-row, writable CTE, COPY), and a superuser history load.
3. **Concurrency.** Is the lock order stated as a rule and followed everywhere? Is any cap a count without a lock handshake? Can two writers deadlock in a way no retry resolves?
4. **The seal.** `tally_void` gains EXECUTE on four `ledger_*` helpers. Is that the least it needs? Is the re-issued `assert_seal_role_invariants()` exactly -22's plus that?
5. **The invariants.** Does `assert_cash_guard_invariants()` catch what it claims (28 trigger definitions, 34 constraint definitions, the approval index, the counters absent, plan settings, `tally_app`'s reach)? Is any claim narrower than its check?
6. **The tests.** Is any check weaker than its label? Does any mutation pass for the wrong reason? What is missing?
7. **Residuals R1–R8.** Is any of them actually blocking?

## How to probe

**Opus and Fable** may query the running `tally-pg` read-only. For experiments, clone into your own scratch database, named for you only (Opus `rv23opus`, Fable `rv23fable`):
1. Clone with `CREATE DATABASE <name> TEMPLATE tally`.
2. Revoke TEMP on the clone from PUBLIC, `tally_app` and `tally_core` right after creating it.
3. `docker cp` the frozen patch into the container, then apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim must be a probe file in `tests/v5.4.2-23/review/codex-r1-probes/`. Each probe:
- runs as the owner, on a fresh clone with frozen r1 applied;
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

Write your full review to `tests/v5.4.2-23/review/<reviewer>-r1.md` (`opus`, `fable` or `codex`). It should contain:
- a verdict: "ready" or "not yet";
- blocking items (B1…), each with the concrete path or repro;
- should-fix items (S1…);
- notes (N1…).

Mark each claim as **executed** or **predicted**. Your final message, under 2 KB, gives the verdict, the blocking items in one line each, and the file path. If you cannot write the file, send the review to main as several messages, each under 3 KB.
