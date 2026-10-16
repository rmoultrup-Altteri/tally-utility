# Review brief: v5.4.2-22 r1 — wave 2, part 1: accounting periods as freeze boundaries, the close snapshot, GL mapping, receivables aging, write-off recovery

**Date:** 2026-10-15. **Kind:** patch review, round 1.
**Reviewers:** Opus, Fable, Codex, independently. Do not read each other's files.

## Frozen files

Review exactly these. Check the hashes first, and stop and report if one differs.

| File | md5 |
|---|---|
| `tests/v5.4.2-22/review/patch-22-frozen-r1.sql` | `99acfac6675597e7d2de4d5a2c7a1254` |
| `tests/v5.4.2-22/review/battery-22-frozen-r1.sql` | `e6070dfdb509ff4ba1eded52eb33733a` |
| `tests/v5.4.2-22/review/close-22-frozen-r1.sh` | `73b157d2966a64a8a00fe537763716ea` |
| `tests/v5.4.2-22/review/mutations-22-frozen-r1.py` | `931d9091e15709121de6dd6b6947d47b` |

The live copies (`sql/v5.4.2-22-periods-snapshot-gl-aging.sql`, `tests/v5.4.2-22/battery-22.sql`, `tests/v5.4.2-22/races/close-22.sh`, `tests/v5.4.2-22/mutations-22.py`) are identical to the frozen ones today. Review the frozen copies.

## Background

The base is the `tally` database: `sql/tu.sql` through v5.4.2-21. -20 sealed the version check and the void with owner roles `tally_seal` and `tally_void`. -21 added retention, bill-line arithmetic, lineage and identity.

The rulings this patch builds are in `gas-billing-memory/application/`:
- **D-2** (`kyle-decisions-2026-08-18-coda-items.md` Part 2) says the platform is a receivables subledger that exports, not a GL. Accounting periods are freeze boundaries, not a reporting grain. It requires a close snapshot and GL code mapping held as tenant configuration. The unbilled-revenue accrual is never a ledger row.
- **D-3** (same file, Part 3) says the aging carries the customer's status.
- **R-02** (`kyle-decisions-2026-10-15-…`) says a reversal names its entry and is capped. Here it applies to the write-off recovery only; the general rule is -23's.

The source inventory, `application/wave2-build-2026-10-15/source-inventory-wave2.md`, lists the requirements (P, S, G, W). Its "-22 as drafted" section maps them to checks and lists seven drafting calls. Those calls are also in `application/DECISION-LOG.md` (2026-10-15). The residuals left on purpose are R1–R9 in the patch header.

Drafting calls to check in particular:
- **The head.** The freeze is a per-tenant `closed_through` date, not a lookup of the containing period. Writers take it FOR SHARE and the close takes it FOR UPDATE. Is the handshake complete? Can any write dated on or before a closed period's end commit after the close has read? Consider:
  - each isolation level;
  - a writer that has not touched the head yet;
  - a writable CTE or a multi-row statement;
  - a definer that writes money (`void_invoice`);
  - a superuser load (`created_at` is the superuser's to choose on the ledger).
- **The recorded instant.** It is `clock_timestamp()` taken after the head lock, and ledger `created_at` is the writer's transaction start. Is the snapshot exactly reproducible at `(period_end, recorded_at)`, as CR7 claims?
- **Supervisor-only close.** `tally_close` reads three columns of `users`. Is the exact grant list right, and is it the least the close needs?
- **Aging.** It is balance-forward from the ledger, netted by lineage within a customer, and aged newest first. Is the netting right for chains, for reversals dated before their originals, and for reversals of other customers' entries? Does the newest-first allocation ever produce a wrong bucket or a negative open amount?
- **GL mapping.** It has wildcards, specificity, ties that raise, and an end known in recorded time. Can a row's effect inside a closed period change, by an insert, by a close, or through recorded time?

## Results so far (reproduce them)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`. The second run is skipped by its marker, the table `accounting_periods`.
- **`tests/ci.sh`:** passes in full with -22 pending (35 steps): batteries 09–22 and the -15/-17 runners, every race script (-22's included), and the tenant-isolation, core-role, seal-role, rule-table, retention, wave-1 and new periods invariants.
- **`battery-22.sql`:** 115 checks. **`races/close-22.sh`:** CR1–CR8.
- **`mutations-22.py`:** 38 of 38 caught at their named checks.
- **No older test was changed.** battery-21 voids posted bills, so it exercises `tally_void`'s new lock on the head.

## What to answer

1. **Does the patch implement the inventory and the rulings?** Name any requirement missed or half-done.
2. **Is there a path around any new rule?** Consider:
   - money dated in a closed period, by any table, role, isolation or statement shape;
   - a period reopened, edited, deleted, or born closed;
   - a gap or overlap in periods;
   - a close out of order or before the period ends;
   - a snapshot written or changed outside the close;
   - a head moved backward or by anyone but the close;
   - a recovery past the cap, of the wrong customer or sign;
   - a GL mapping changed in place, or in force inside a closed period.
3. **The seal.** Does `tally_close` meet the -20 seal pattern? Check: NOLOGIN, no BYPASSRLS, no members, an exact grant list, owns only its definer, pinned. Is the re-issued `assert_seal_role_invariants()` exactly -21's plus the third role? Is `tally_void`'s new grant (SELECT and `updated_at` UPDATE on the head) the least it needs?
4. **The snapshot.** Are the figures right (opening, activity, closing, entry count, aging lines)? Is anything passed in that should be computed, or computed that cannot be?
5. **The aging function.** Is it correct for the cases in item "Aging" above? Is it safe under RLS for a platform admin and for a tenant user? Are the coordinates required, with no live fallback?
6. **The invariants.** Does `assert_periods_guard_invariants()` catch what it claims? Is any claim narrower than its check?
7. **The tests.** Is any check weaker than its label? Does any mutation pass for the wrong reason? What is missing?
8. **Residuals R1–R9.** Is any of them actually blocking?

## How to probe

You may query the running `tally-pg` read-only. For experiments, clone into your own scratch database, named for you only:
- Opus: `rv22opus`;
- Fable: `rv22fable`.

Clone with `CREATE DATABASE <name> TEMPLATE tally`. Revoke TEMP from PUBLIC, `tally_app` and `tally_core` on the clone right after creating it. Then apply the frozen patch strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

(`docker cp` the file into the container first.)

**Restrictions:**
- Roles are cluster-wide. Do not create, drop or alter any role. The patch creates `tally_close` if it is missing. It already exists in the cluster, from the author's scratch runs.
- Do not run `mutations-22.py`: it uses the fixed name `m22`.
- Do not run `close-22.sh` against anything but your own clone.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file.
- Drop your clone when done.

## Output

Write your full review to `tests/v5.4.2-22/review/<reviewer>-r1.md` (`opus`, `fable` or `codex`). It contains:
- a verdict: "ready" or "not yet";
- blocking items (B1…), each with the concrete path or repro;
- should-fix items (S1…);
- notes (N1…).

Mark each claim as **executed** or **predicted**. Your final message, under 2 KB, gives the verdict, the blocking items in one line each, and the file path. If you cannot write the file, send the review to main as several messages, each under 3 KB.
