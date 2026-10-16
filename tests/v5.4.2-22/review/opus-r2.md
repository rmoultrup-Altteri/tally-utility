# Opus review: v5.4.2-22 r2

**Date:** 2026-10-15. **Reviewer:** Opus. **Verdict: not yet.** There is one blocking item (B1), with two paths and one fix. It reopens my r1 B2. Everything else from round 1 is closed.

**Hashes verified (executed).** All four frozen files match the brief: patch `0d91882c…`, battery `4049de7b…`, close `2b7149d7…`, mutations `7af6f68a…`.

**What I ran (executed).**
- I cloned `rv22opus2` from `tally` and revoked TEMP from PUBLIC, `tally_app` and `tally_core`.
- I strict-applied the frozen patch twice. The second run skipped on its marker.
- The battery passed 135 of 135.
- `close-22-frozen-r2.sh rv22opus2` passed CR1–CR10.
- `assert_seal_role_invariants()` and `assert_periods_guard_invariants()` passed on the clone.
- I probed as `tally_app` (an operator and a tenant admin of a fixture tenant) and as the owner, including a two-session race.
- The clone and every file I put in the container are gone. I did not run `mutations-22.py`.

Each claim is marked **[E]** (executed) or **[P]** (predicted).

---

## Blocking

### B1. Money netted against a write-off still gets past the cap, by two paths. One fix closes both.

r2 refuses a non-recovery row that names a write_off, in a BEFORE INSERT trigger (`enforce_write_off_recovery`). The act being capped is any money that aging nets into the write-off's tree. That act escapes in two ways.

**(a) Row order inside one statement. [E]**
A BEFORE ROW trigger sees the rows inserted earlier in its own statement, but not the rows inserted later. If the adjustment comes before its write-off, `EXISTS (… l.transaction_type = 'write_off')` finds nothing. The immediate FK is checked at the end of the statement, so it passes. I ran this as the `tally_app` operator:

```sql
INSERT INTO account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES
 ('…e3', T, C1, '2026-03-01', 'adjustment', 'reinstated', 500, '…e2', 'x'),   -- names the write-off below
 ('…e2', T, C1, '2026-01-25', 'write_off',  'wo',        -100, NULL, NULL);
```

- It was accepted.
- `receivables_aging_as_of(T, 2026-03-31, now)` then shows C1 at **500.00 in 61-90**, aged from the write-off's date.
- A `write_off_recovery` of 100 was then accepted on top, because the cap counts only the recovery rows. The result is **600 reinstated against a 100 write-off**.
- The same thing is accepted in a writable CTE, with the adjustment's CTE first, as `tally_app` [E].
- It is accepted in a COPY by the owner [E]. COPY is refused for `tally_app` under FORCE RLS [E].
- The reverse row order is refused, which is what R7 tests [E].

**(b) Naming the recovery instead of the write-off. [E]**
I ran these as the `tally_app` operator, in separate statements:
1. a write_off of -100;
2. a `write_off_recovery` of +100 (accepted at the cap);
3. an `adjustment` of **+700** naming the recovery.

The third row names a `write_off_recovery`, not a `write_off`, so nothing fires. Aging nets it into the write-off's tree: C1 shows **700.00 in 61-90**. The header's R8 says "-22 binds the reversals of a write-off". This is a reversal inside the write-off's tree, and it is uncapped and of either sign.

This is memory `guard-the-act-not-the-label` one level down. My r1 fix ("fire the guard for any row whose `reverses_ledger_entry_id` names a write_off") was itself too narrow. The author built what I proposed.

**Fix (one, for both paths):**
- Move the write-off rule into an AFTER INSERT row trigger. It can share the lineage walk, which already sees every sibling, as R8 and P3 below show.
- For each new row whose chain reaches a write_off W:
  - if it names W directly, it must be a `write_off_recovery` (as now);
  - in every case, under W's advisory lock, the net of all of W's descendants must stay within `[0, -W.amount]`.
- Capping the net, not the gross recoveries, also removes r1 N6: re-recovering after a bounced recovery becomes possible, and it is still capped.
- Keep the BEFORE checks for the recovery's own sign and customer.
- Tests:
  - a battery row for each path (adjustment-first in VALUES, and in a CTE; a positive adjustment naming a recovery);
  - a mutation that moves the check back to BEFORE.

---

## Should fix

**S1. An operator still chooses the edges the close uses, through a manual history row. [E]**
- The history CHECK now validates every value, and a snapshot is reproduced from its stored edges. B1 of r1 is therefore closed for **reproducibility**.
- But the operator (not an admin) inserted `('receivables_aging_bucket_days', '[1,2]', effective_from = now(), 'manual')` and then had a supervisor close January. The snapshot stored **`{1,2}`**, with a line `3+` = 40.00, while `tenants.receivables_aging_bucket_days` still reads `{30,60,90,120}`.
- A backdated row also rewrites "the setting as recorded" for any earlier instant. `receivables_aging_bucket_days_as_of(T, yesterday)` returned `{1,2}` for a time before the setting existed, against R9's "unknowable".
- This is memory `app-written-logs-are-not-guards`: the close reads a fact the application writes with its own date.
- **Fix:** for this key, either refuse `manual` and `backfill` rows from `tally_app`, or require `effective_from = now()` with `new_value` equal to the tenant column. Alternatively, have the close read `tenants.receivables_aging_bucket_days` directly. At the close's own instant, the live value *is* the value as of that instant, so this is not a live fallback.

**S2. Any `tally_app` user can withdraw a period, not only a supervisor. [E]**
- The battery's P9 has the operator (`…22b1`) withdraw, and so did my probe.
- The close is gated on `session_is_supervisor()` because it is irreversible. A withdrawal is irreversible too: a withdrawn row never comes back (P9d, [E]).
- `withdrawn_by` is NULL when `app.user_id` is unset [P]. The trigger reads it with `nullif`, and no CHECK requires it.
- Nothing unfreezes. The head is untouched, and the next period must still start the day after `closed_through` [E]. So this is a control gap, not a books hole.
- I suggest the same supervisor gate as the close, and `withdrawn_by` NOT NULL with the withdrawal.

---

## Notes

**N1. A withdrawal followed by a money write deadlocks with a close of that period. The header does not state this. [E]**
- Session A withdraws period P, which takes P's row lock, and then posts a February charge, which needs the head FOR SHARE.
- Session B closes P. It takes the head FOR UPDATE, then waits for P's row lock.
- PostgreSQL detected the deadlock and aborted A. B then closed P.
- No integrity is lost. The withdrawal's lock order is period row then head, the reverse of the close's. One line in the "Lock order" section would cover it.
- Making the withdrawal take the chain advisory lock earlier would not help, because the UPDATE locks the row before the trigger runs.

**N2.** `close_accounting_period` on a withdrawn period says "is already closed; a closed period never reopens" [E]. The message should name the withdrawn status.

**N3.** In the seal invariant, r2 swapped `tally_app`'s `accounting_periods.status` UPDATE check for `closed_at`. That is right, because `tally_app` now holds `status` for withdrawal. But:
- a grant of `closed_by` to `tally_app` would pass. The trigger would still refuse it.
- the invariant's COMMENT still says "only tally_close writes … a period's status", which is no longer true.

**N4.** The constraint pin does not cover the snapshot tables' keys or FKs, nor `account_ledger_reverses_ledger_entry_fkey`. The lineage walk also catches self-reference, so `reversal_not_self_check` does not matter. These are low risk, because only the close writes snapshots.

**N5.** The lineage walk stops at depth 10 000. A pre-existing loop that the new row's chain enters, without the new row being on it, would make the walk run to that depth, and the aging check would then raise. That is fine, but it is worth one comment line [P].

---

## Answers to the brief

**r1 findings closed?**

| r1 item | Status | How I know |
|---|---|---|
| B1 (validator) | Closed | W10e plus the history CHECK; `'["abc"]'` and `[0:1]` refused (battery W10e/W10f) [E] |
| B1 (backdated history) | Closed for reproducibility; S1 remains | snapshot stores its edges and CR7 uses them [E] |
| B2 | Reopened by B1 above | [E] |
| S1 (future `created_at`) | Closed | C19 [E] |
| S2 (precedence) | Closed | Weights 8/4/2/1 give distinct sums for distinct key sets, and identical keys are EXCLUDEd. I found no tie path. A bitemporal tie would need a successor created before its predecessor's close, which the EXCLUDE forbids, and `clock_timestamp()` orders the two within one transaction [P, reasoning; CR8/CR9 E]. |
| S3 (invariants) | Closed | Exact constraint definitions and ledger immutability triggers are pinned [E: invariants pass; read the list] |
| S4 (tests) | Closed | C5 at UTC-12, W4b, W14, CR9 and I4 relabelled are present [E: battery] |
| S5 (correcting a period) | Closed | withdrawal works; see S2 and N1 |
| N1 (`customers.tenant_id`) | Closed | removed |

**New mechanisms.**
- **Loop walk [E]:** complete for multi-row VALUES, a three-row writable CTE and owner COPY. All are refused with "returns to itself". A legitimate two-level chain passes.
- **Two-tenant lock order [P]:** no new deadlock. Writers take heads only FOR SHARE, and the close takes a single head FOR UPDATE and waits on no other head. F2e covers the old tenant's freeze [E].
- **Withdrawal versus a concurrent period insert [P]:** safe. Both take the chain advisory lock, then read with a fresh READ COMMITTED snapshot. CR10 and P9a–e pass [E].
- **Withdrawal versus a close:** see N1. A lone withdrawal makes the close wait, then refuse [P].

**2. Paths around the rules.**
- The freeze, periods (reopened, edited, deleted, born closed, gaps, overlaps, order, early close), the snapshot and the head: no path found [E: battery and CR, plus my probes of reopening a withdrawn period and closing a withdrawn one].
- Recovery past the cap: **B1** [E].
- GL mappings: no path [E: G and CR8/CR9].

**3. The seal.**
- `tally_close` meets the -20 pattern [E: invariant passes, grants read].
- Its grants are now the measured minimum: `aging_bucket_days_valid` is needed by the four-argument aging it calls [P].
- `tally_void`'s two head grants are unchanged and are the least: FOR SHARE needs SELECT and UPDATE on one column [E, r1].

**4. The snapshot.**
- The figures are right. CR1b, CR7 and CR7b pass [E].
- Nothing is passed in that should be computed.
- The edges are computed from a value the operator controls (S1).

**5. The aging.**
- The netting and buckets are right, apart from B1's inputs.
- The coordinates are required and there is no live fallback: W1 [E].
- RLS: another tenant is "not visible" (W1b) [E]. A platform admin works [P].

**6. The invariants.**
- They catch what they now claim [E].
- The COMMENT in N3 overclaims.

**7. The tests.**
- Missing:
  - B1(a) and B1(b) rows and their mutations;
  - a check that the close's edges cannot be set by a non-admin (S1);
  - a non-supervisor withdrawal refused (S2), once decided.
- M30, M50 and M51 are caught at APPLY by the constraint pin, before the battery. W15 and W10f exist for M50 and M44, so the behaviour is also tested [P].

**8. Residuals.**
- R8, as worded ("binds the reversals of a write-off"), is not met for indirect reversals: B1(b).
- R1–R7 and R9 are acceptable. R9 is undermined slightly by S1's backdating.
