# Opus review: v5.4.2-22 r3

**Date:** 2026-10-16. **Reviewer:** Opus. **Verdict: not yet.** There is one blocking item (B1): the cap is checked on the write-off's tree as a whole, but aging nets the tree date by date. A reversal dated later makes room for a recovery dated earlier, and the earlier period's snapshot freezes the over-recovery. Every r2 finding of mine is closed.

**Hashes verified (executed).** All four frozen files match the brief: patch `ae35e901…`, battery `36edebe0…`, close `de7a2f69…`, mutations `61104fe1…`. The brief's md5 is `155fbbd1…`.

**What I ran (executed).**
- I cloned `rv22opus3` from `tally` and revoked TEMP from PUBLIC, `tally_app` and `tally_core`.
- I strict-applied the frozen patch twice. The second run skipped on its marker.
- The battery passed 149 of 149. Its tail ran both invariants.
- I probed as `tally_app` (an operator, then a tenant admin of my own fixture tenant) and as the owner, including a two-session lock probe. I timed the triggers on a large ledger with `auto_explain`.
- I did not run `close-22.sh` or `mutations-22.py`.
- The clone and every file I put in the container are gone.

Each claim is marked **[E]** (executed) or **[P]** (predicted).

---

## Blocking

### B1. A later-dated reversal makes room for an earlier-dated recovery. The earlier period's snapshot then freezes a recovery past the cap. [E]

**What the cap checks.** The cap sums the write-off's whole tree, at every date at once, and requires the total to be between 0 and the amount written off.

**What aging nets.** Aging nets only the rows dated on or before its date (`transaction_date <= p_on`). The close's aging lines are aging at `period_end`.

**The gap.** The cap admits a row because of rows dated *after* it. Aging at the earlier date sees the row without them.

**Repro.** I ran these as the `tally_app` operator, one statement each. Customer K1 owed 100, and periods Jan, Feb and Mar were open.
1. A `write_off` of −100, dated Feb 1.
2. A `write_off_recovery` of +100 naming it, dated Feb 10. The net is 100.
3. An `adjustment` of −100 naming the recovery, dated **Mar 5** (the payment bounced). The net is 0.
4. A second `write_off_recovery` of +100 naming the write-off, dated **Feb 20**. The net is 100, so the cap accepts it.

Then:
- `receivables_aging_as_of(T, '2026-02-28', now, '{30,60,90,120}')` shows K1 with a **balance of 200.00**. That is 100 in 0-30 and 100 in 61-90, on a debt of 100.
- The supervisor closed January, then February. February's snapshot froze it permanently:
  - activity `write_off_recovery` **200.00 (2 entries) against `write_off` −100.00**;
  - aging `61-90` 200.00, `0-30` 100.00;
  - closing balance 300.00.
- On Mar 31 the same customer reads 100, because the March reversal is now in the window.

**Why this is the cap's act and not just dating.** This is memory `guard-the-act-not-the-label` along a new axis. The act being capped is "what aging nets into the write-off". Aging is evaluated at a date, and the close freezes it at `period_end`.

As of Feb 28, the books carry 200 reinstated against a 100 write-off. That is exactly what R-02's cap forbids. Recovery 4 was admitted only because a reversal from the following month offset it.

The shape is ordinary. A bounced agency payment is reversed in early March while February is still open, and a replacement recovery is then backdated into February.

**A related shape [E].** A recovery dated *before* its write-off is accepted. I recorded a write-off of −40 dated Mar 25 and a recovery of +40 naming it dated Mar 3. Aging on Mar 10 shows +40 owed, not netted into anything, because the write-off is outside the window and the recovery stands alone. That is a recovery of a write-off that has not yet happened.

**Fix (one, for both):**
1. **A row under a write-off is dated on or after the entry it names.** This applies at least within the cap's scope, and it closes the related shape. A row whose path to the write-off is in the window is then simply a row dated on or before the date.
2. **The cap holds at every date of the tree, not only at the end.** For each distinct `transaction_date` d among the tree's rows, the sum of tree rows dated on or before d must be in [0, −W.amount].
   - The down walk already returns the tree, so this is a window sum over it, ordered by date.
   - It costs nothing extra in locks.

Tests:
- a battery row for the repro above, refused at step 4;
- a battery row for a recovery dated before its write-off, refused;
- a mutation that checks only the final net, caught by the first row.

The recorded-time axis (aging at a `recorded_at` between two transactions' `created_at`) I reasoned through and found no over-cap shape [P]. A row's insert check sees every committed row, and the close refuses rows recorded after its instant.

---

## Should fix

### S1. The cap's write-off lookup scans the tenant's ledger for every reversal row on a table the planner thinks is small. A bulk load with reversals goes quadratic. [E]

The brief asks that no step of either walk can scan a ledger. The steps are now index lookups. The **final join of the upward walk** is not:

```sql
SELECT l.* FROM up u JOIN public.account_ledger l ON l.id = u.id
 WHERE l.transaction_type = 'write_off' AND l.tenant_id = NEW.tenant_id AND l.customer_id = NEW.customer_id
```

`auto_explain` showed the plan, with 200,000 rows inserted in the same transaction and statistics still at 9 rows:
- `Index Scan using idx_ledger_tenant_date … Filter: transaction_type = 'write_off' AND customer_id = … Rows Removed by Filter: 200026`;
- the CTE was "never executed";
- about 9 ms per reversal row, whether or not any write-off exists.

**Measured** (one transaction, 200,000 charges, then reversals of them, no write-off anywhere):

| Reversals | Time |
|---|---|
| 5,000 | 51 s (`enforce_write_off_recovery` 56.8 s of 65 s under EXPLAIN ANALYZE) |
| 50,000 | over 10 min (I cancelled it) |

On an earlier run, before autovacuum had touched the clone's statistics, 50,000 took 2.1 s. The cost depends on the statistics, which is the pathology the r3 header says was removed.

This is the onboarding case: a tenant's history, with its reversals, loaded into a statistically empty ledger.

**Fix.** Carry `transaction_type`, `tenant_id` and `customer_id` through the recursive CTE, so the final SELECT reads the CTE and joins nothing. Alternatively, join by id in a `MATERIALIZED` CTE and filter outside it. R10g cannot see this, because the battery's ledger is small. A timed check on a 100k-row ledger in one transaction would.

The −21 reversal FK's RI query shows the same plan, at about 6 ms for one row [E]. It predates −22, so I mention it only.

---

## Notes

**N1. The cap's locks are in id order within one row, not across rows or statements. The header implies more. [E for across statements, P for within one statement]**
- Two sessions each posted a recovery under write-off A and then under write-off B, in opposite orders, in two statements with a sleep between them. PostgreSQL detected the deadlock and aborted one side. Nothing was written by it.
- Within one multi-row statement, each row's AFTER trigger locks its own ancestors in id order, but rows fire in row order. So rows under A then B in one session, against rows under B then A in another, can deadlock in the same way [P].
- No integrity is lost. One header line would cover it: "two transactions posting under the same write-offs in different orders can deadlock; one is aborted".

**N2.** The close reads `tenants.receivables_aging_bucket_days` after taking `v_at`, without a lock [P]. A setting change committed between `v_at` and that SELECT is used, although it was committed after the instant. The snapshot stores the edges it used, so reproducibility holds. This is cosmetic.

**N3.** M53 (the rule moved back to BEFORE) is caught at APPLY by the trigger-definition pin, not by R9's behaviour. The invariant pins it exactly, so the label holds. R9, R9b and R9c are the behavioural test.

**N4.** M63 mutates only the downward walk's step. Nothing mutates the upward walk's step back to a customer join, nor tests the final join (S1).

---

## Answers to the brief

**r2 findings closed?**

| r2 item | Status | How I know |
|---|---|---|
| B1a (row order within one statement) | Closed | AFTER INSERT sees the whole statement; battery R9, R9b and R9c pass [E] |
| B1b (naming the recovery) | Closed for the net at the end; B1 above is the date axis | R10, R10b, R10f [E]; my repro in B1 [E] |
| Fable S1 (gross count) | Closed | R10c–R10e [E] |
| S1 (operator chooses the close's edges) | Closed | the close reads the tenant column; C16b [E]; grants read |
| S2 (withdrawal) | User required, as decided. I accept the reasoning: a withdrawal of the latest open period is undone by recreating it | P9f [E] |
| N1 (deadlock) | Stated in the header | read |
| N2 (message) | Closed | C13b [E] |
| N3 (invariant comment and `closed_by`) | Closed | read the invariant |
| N4 (pins) | Closed | the three constraints are pinned, and the comment now says "named here" |
| N5 (depth comment) | Closed | the walk fails closed at 1,000; R11 [E] |

**The cap's net, by shape.**
- **Trees across statements, and within one:** right at the end [E, R9c, R10, R10g].
- **A write-off under another write-off's recovery [P, reasoning]:**
  - The inner write-off W2 names W1's recovery, so it is counted in W1's net.
  - A row under W2 walks up through both write-offs, locks both in id order, and checks both. For example, W1 −100, R1 +100, W2 −50 naming R1, then R2 +50 under W2: W2's net is 50 and W1's net is 100, both within their caps.
  - A W2 larger than R1 drives W1's net below 0 and is refused. That is acceptable.
- **Another customer's rows naming into the tree:** not counted, and their subtrees are not walked, which matches aging's same-customer tree. R10f discriminates (104 against 99) [E].
- **Every date:** **B1**.

**AFTER versus BEFORE [P, reasoning].**
- Nothing that the r2 BEFORE trigger refused is lost:
  - the same checks run;
  - a recovery without a link is still refused by the CHECK;
  - the ledger is immutable, so there is no UPDATE path;
  - ENABLE ALWAYS covers replica mode;
  - COPY fires row AFTER triggers.
- Within one row, AFTER triggers fire by name, and `enforce_ledger_lineage_acyclic` sorts before `enforce_write_off_recovery`.
- Across rows of one statement, row 1's cap runs before row 2's lineage walk. Both cap walks are bounded (UNION ALL to depth 1,000, and UNION over a tree), so a loop that a later row closes cannot hang the earlier row's cap. The later row's lineage walk then refuses the statement.

**Link-only walks [E, plans read].**
- Each step of both walks is now a primary-key or `idx_account_ledger_reverses` lookup.
- The upward walk applies the same-customer test after the join, so it finds the same write-offs as a customer join would. The downward walk flags rows and does not descend through another customer's rows, so it covers the same tree.
- The remaining scan is the final join (S1).

**The 1,000 bound [P].** Real reversal chains are a few entries deep: a void, a reversal of a void, a recovery and its bounce. The bound limits depth, not tree width (R10g: 300 deep). I see nothing legitimate that it refuses. Every chain that is admitted has at most 999 ancestors, so the cap's upward walk, which reaches depth 1,000, sees them all.

**2. Other paths around the rules.**
- I found no new path in:
  - the freeze;
  - the periods: reopened, edited, deleted, born closed, gaps, overlaps, out of order, closed early;
  - the snapshot, the head and the GL mappings.
- Since r2, those paths changed only in the withdrawal stamp and the close's edges (both checked above). The battery covers the rest [E].
- B1 is the cap.

**3. The seal [E: the invariant passes in the patch tail].**
- `tally_close`'s list is the least the close needs:
  - `tenants(id, receivables_aging_bucket_days)` for its WHERE clause and value;
  - the 4-argument aging function and `aging_bucket_days_valid`, which that function calls;
  - the heads (SELECT and update of two columns), the periods (SELECT and update of three columns), and INSERT on the two snapshot tables;
  - the ledger and `customer_state_events`;
  - three columns each of `customers` and `users`, for aging and the supervisor check.
- It no longer holds the history or `receivables_aging_bucket_days_as_of`.

**4. The snapshot.**
- The figures are right for what aging computes [E: C12 and CR pass in the author's run; my February snapshot added up: opening 200 (two December charges) + activity 100 (−100 + 200) = closing 300].
- The edges are the tenant row's at the instant. See N2 for the window.
- B1 is what the snapshot can be made to freeze.

**5. The aging function.**
- It is unchanged since r2. It is correct for its inputs, its coordinates are required, and it is RLS-safe (W1, W1b) [E].

**6. The invariants.**
- Each catches what it claims, and the comments now match the checks [E: read, and the tail passes].

**7. The tests.**
- Missing:
  - B1's two rows and their mutation;
  - a timed check on a large unanalyzed ledger (S1);
  - an upward-walk step mutation (N4).
- No mutation passes for the wrong reason that I can see. M53 is caught at APPLY (N3).

**8. Residuals.**
- R8 says "-22 caps the net of a write-off's tree". B1 shows that the net at the end is not the net that aging and the snapshot use. Either R8 is narrowed to say so, which I would not accept, or the cap holds at every date.
- R1–R7, R9 and R10 are acceptable.
