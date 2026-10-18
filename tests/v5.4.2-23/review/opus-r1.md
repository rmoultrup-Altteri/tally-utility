# Opus review: v5.4.2-23 r1

**Date:** 2026-10-17. **Reviewer:** Opus. **Verdict: not yet.**

Frozen md5s checked (`md5 -r`): all five match the brief. Scratch clone `rv23opus` (TEMPLATE tally, TEMP revoked from PUBLIC, tally_app and tally_core), frozen patch strict-applied twice (`search_path=''`, `check_function_bodies=on`). The second run skipped on its marker. All eight invariant functions pass on the clone. Every claim below is marked **executed** (run on the clone) or **predicted** (from reading the code). The probe files are in my scratchpad, not the repo. The clone is dropped.

Fixture: battery-23's own helpers and fixtures (lines 1–180: tenant T1, customer C1, bills I1–I3, tariff `…23ab`, payments P61–P65), committed to the clone for the two-session probes and wrapped in BEGIN…ROLLBACK for the one-session probes.

---

## Blocking

### B1. A source's status is read before its lock: money is applied from a payment that bounced, or a credit that was voided, while that move commits (executed)

`enforce_invoice_application` reads `v_pay` / `v_cred` (status `posted` / `active`) at the top. Only afterwards does `check_cash_source` take the source's advisory lock, and it never reads the status again. A status move holds that lock from inside its UPDATE trigger. If the move comes first, the application reads the old status (the move has not committed), waits on the lock, gets it after the commit, passes the amount cap and commits. The patch comment's claim "whichever comes second sees the first" holds only when the application comes first, and that is the order CR3 tests.

- **Payment (executed).** Session B posts O‑P6's nsf ledger row, moves O‑P6 to `nsf` (cause = that row), sleeps 4 s, then commits. Session A (tally_app) applies 40 of O‑P6 to I2's gas line. A was seen `Lock|advisory` with B as blocker, then got `INSERT 0 1`. Final state: `nsf | 40.00 applied`.
- **Credit (executed).** Session B moves K71 to `voided` (cause = the reversal of its issuing entry) and holds. Session A applies 10 of K71. A waited on the advisory lock, then got `INSERT 0 1`. Final state: `voided | 10.00`.
- **Refund and overpayment credit (predicted).** `enforce_cash_draw` has the same shape: it reads the status, then calls `check_cash_source`. `enforce_payment_lineage` takes no row lock, so nothing else serialises a refund against an nsf move.
- **Invoice (executed, safe).** A void holding the bill blocks the application's FK check (FOR KEY SHARE against FOR UPDATE). The application then sees `void` and is refused.

**Fix.** Take the source lock before reading the source, or re-read the status after `check_cash_source`, in both triggers. Add the reverse-order leg to CR3, and the same legs for credits and refunds.

### B2. "Guard the act" guards the label: bounced, withdrawn or never-posted money is still applied, and a 1-cent reversal earns `nsf` (executed)

The design says money that bounced, was reversed or never arrived is not still applied. The guard sits only on the optional status UPDATE. The act itself is the ledger row (nsf or reversal of the posting entry), or the missing posting entry, and nothing looks at it.

- **O1 (executed).** tally_app inserts P61 born `posted`. No ledger row references it (`count = 0`), and 60 of it is applied to I1. Q1(a)'s cause rule binds UPDATE moves only. A row born `posted`, or born `refunded` with no cause (O1b, accepted), names nothing. battery-23 A1 itself applies a born-posted payment that has no posting entry.
- **O2 (executed).** O‑P6 is posted properly (entry −50, cause set). Then the full nsf row (+50) reversing that entry is inserted (`ledger_entry_remaining = 0`). The status stays `posted`, and 40 more of O‑P6 is applied to I2, dated after the nsf. Battery-23 M3f leaves the same state behind (the nsf row is in, the move is refused, P1 stays applied).
- **O6 (executed).** Goodwill credit K71 has its issuing entry (−25) fully reversed (+25). It is still `active` and still applied (10).
- **O3 (executed).** O‑P7 (30, posted) gets an nsf row of 1.00 against its posting entry. The move to `nsf` is accepted, while `ledger_entry_remaining` of the posting entry is still −29. The `reversed` cause has the same shape (any row reversing the entry, of any size).

**Fix (shape, the author's call).**
- An application or draw requires the source's arrival on the ledger: for a payment, its posting entry exists and nothing under it is reversed; for a credit, its issuing entry likewise.
- `nsf` / `reversed` / `voided` (credit) require the posting or issuing entry's remainder to be 0.
- A payment or credit is inserted only as `pending` / `active` (or the insert names its cause).
- Whether a ledger reversal of a posting entry is refused while the source is still applied is for the author to decide.

### B3. "Refunded means nothing is left" is checked once, then undone (executed)

- **O4 (executed).** O‑P8 (20, posted) has 5 applied and a pending refund of −15. The move to `refunded` is accepted (remaining 0). Then:
  - (b) the 5 application is undone: accepted;
  - (c) the pending refund cited as the cause is voided: accepted.

  End state: O‑P8 is `refunded` (terminal), `payment_position_as_of` shows remaining 20.00, and no application can ever draw it again (posted is required).
- **O5 (executed).** O‑P5 (10, posted) has a pending refund of −10. Its nsf row goes in, and the move to `nsf` is accepted: the guard counts applications and credits, not refunds. The refund of bounced money is still pending and can post. -19's revised fixture builds the same state (refund P‑4 of P‑2, then P‑2 nsf).
- **R2 is not only a read residual.** Voiding a pending refund changes `payment_position_as_of` at every past instant, so positions are not reproducible across it (follows from O4c; predicted for the as-of reading).
- **Credits (predicted).** The same shapes apply: an undo after `refunded`, `donated` or `escheated`, and a refund void after `refunded`.

**Fix.**
- An undo needs its source still posted or active (or an undo of a terminal source is refused).
- A refund leaves `pending` for `voided` only if its source is not terminal on it as the cause.
- `nsf` / `reversed` require pending and posted refunds to net to 0.

---

## Should fix

**S1. The as-of positions are not reproducible at an instant inside an open transaction (executed).** This answers the brief's question: no, the recorded-order rule is not enough.

Repro:
1. A opens a transaction and applies 15 (stamped `now()` = its start), then sleeps.
2. B reads `invoice_line_position_as_of(line15, 2026-12-31, t1)` with t1 later than A's start: applied 0.
3. A commits.
4. B reads again at the same t1: applied 15.00.

The rule orders rows inside one tree, source or line. It does not stop a reader from reading at an instant that a later commit then fills in. -22 guards this for the close only (C19). Either state it as a residual (positions are reproducible only at instants older than every open transaction), or have the readers refuse an instant at or after the oldest running transaction's start.

**S2. A void is refused while its charge's tree holds a future-dated row (executed, L4).** Setup: I2 charge +90, an adjustment −50 (Mar 2), and a re-reversal +50 dated `CURRENT_DATE + 30`, which was accepted. `void_invoice` then posts −90 dated today, and the tree at today comes to −140, so the void raises 23514. The bill cannot be voided until that date passes. Either refuse future-dated ledger rows, or have the void reverse what is left as of its own date.

**S3. A superuser history load can record an application before its payment (executed, O8).** The payment is loaded at `now()`, the application at `now() − 1 day`, and both are accepted. `invoice_line_position_as_of(… now() − 2h)` shows 7.00 applied from a payment that has no row at that instant. The recorded-order rule covers rows already drawing on the source, and never the source row itself; the bill and line are not covered either.

**S4. Another tenant's user can approve an overpayment credit (executed, O7).** `customer_credit_approvals.approved_by` is an FK to `users(id)` only, and T2's operator was accepted on T1's approval. Bind it to the tenant (a `users (id, tenant_id)` key, or a check).

**S5. `assert_cash_guard_invariants` checks less of tally_app's reach than it claims (executed).** After `GRANT UPDATE (reason) ON invoice_applications TO tally_app` and `GRANT UPDATE (amount) ON customer_credit_approvals TO tally_app`, the function still passes, because `has_table_privilege` ignores column grants. `append_only` still blocks the write. Use `has_any_column_privilege`, or list the column ACLs.

---

## Notes

**N1. The X2 cap is equivalent to netting each ancestor's subtree (predicted, argued; executed on cases).**
- A row's `m` is the depth of its deepest on-path ancestor, so partition j holds exactly the descendants of `v_down[j]`, excluding `v_down[j]` itself.
- Siblings of path nodes inherit their parent's depth. Off-path children keep `m`. The RANGE frame nets rows of one date together. Dates are monotone down a path, so no earlier-dated row sits under a later one.
- Executed:
  - L1: two siblings (−60, −50) of +100 in one INSERT, refused;
  - L2: the same through a writable CTE, refused;
  - L3: a −100/+100/−100 chain plus a −1 sibling in one statement, refused at the root (−101).
- The down-walk bound (`depth < 1000`) is consistent with the path bound. The path walk fails closed, so no row can sit below the walk.

**N2. The seal (executed).** The only change to `assert_seal_role_invariants` is tally_void's grant list, which adds exactly the four `ledger_*` EXECUTEs. Four is the least the void needs: `ledger_entry_remaining` is a SQL function that calls `ledger_tree_ids` as the caller, and the reversal trigger calls `ledger_tree_lock_key` as tally_void.

**N3. The invariants' counts match (executed).** 28 trigger definitions, 34 constraint definitions, the approval index, the counters absent, and four walks pinned.

**N4. The -19 test edits mask the guards below, rather than loosen outcomes.** P9c, P9d, P9f and P9g now stop at the 23001 write-once guard. No test now reaches `payments_refunds_payment_id_fkey`, `payments_lineage_not_self_check` or the lineage trigger's customer message on UPDATE (P9b still covers INSERT). The -22 edits (R10f, R12o, R12n, W8/W14, C19, the R11 planting) each follow X1b, X2 or the time rule. R10g's drop from 300 to 200 deep is R1's cube.

**N5. A tariff citation is not matched to the line (predicted).** Only the tenant and the date are checked, not the tariff's service or system against the bill line.

**N6. A deposit_refund credit draws on nothing (predicted).** A credit of origin `deposit_refund` naming a payment is outside `cash_source_draws`, so nothing caps several of them against one deposit. This may be -15's territory; worth stating.

**N7. One long statement can hold the locks for minutes (predicted from R1's numbers).** A single tally_app INSERT of a ~1000-row chain costs about d³ (minutes). The whole time it holds the tree lock and the head FOR SHARE, which blocks the close. A `statement_timeout` for tally_app bounds it.

**N8. Missing tests.**
- Every reverse-order race in B1.
- A ledger nsf without the status move (B2).
- Born-status payments (B2).
- Undo after a terminal status, and a refund void after `refunded` (B3).
- A future-dated tree row against a void (S2).

**Residuals.**
- R2 is a real hole (B3).
- R1 and R3–R8 are acceptable as stated.
- R6, the core classing sourceless lines, leaves the CI-050 floor resting on whatever class the core writes for tax and other lines. Acceptable given R7.
