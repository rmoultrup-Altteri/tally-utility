# Fable review: v5.4.2-22 r3

**Date:** 2026-10-16. **Reviewer:** Fable (claude-fable-5-1). **Round:** 3.
**Frozen files:** all four md5s match the brief (executed): patch `ae35e901…`, battery `36edebe0…`, close-22 `de7a2f69…`, mutations `61104fe1…`; brief `155fbbd1…`.
**Clone:** `rv22fable3` (TEMPLATE tally; TEMP revoked from PUBLIC, tally_app, tally_core), strict apply (`search_path=''`, `check_function_bodies=on`) twice: the first applied (its tail ran all four invariants), the second skipped on the marker (executed). Dropped at the end.
**Read:** my r2 report, `review-findings-22-r2.md`, `diff-22-r2-r3.diff` in full, the four frozen files (the patch in full; the battery's fixtures and the R, P9f, C13b, C16b sections; the race script's CR7–CR12; the mutations' r3 block and runner). Not read: any other reviewer's file.

## Verdict: ready

No blocking item. Every r2 finding is closed by the mechanism the findings table names, and I found no new path around the cap, the freeze, the close or the seal. One should-fix (S1): a detected deadlock the header does not state, in the same class as the withdraw-and-close one it does state. It admits no money and writes nothing.

## Reproduced (executed)

- `battery-22-frozen-r3.sql` on the clone: 149 PASS, no FAIL, no ERROR.
- `close-22-frozen-r3.sh rv22fable3`: CR1–CR12 (18 lines) all PASS.
- Did not run `mutations-22.py` (fixed `m22` name). M53–M63 reviewed by reading; see N8.

## r2 findings, each checked

| # | r3 mechanism | Checked |
|---|---|---|
| 1 row naming a write-off listed before it | AFTER INSERT row trigger | Battery R9/R9b/R9c PASS (executed). Catalog order on account_ledger (executed): `RI_ConstraintTrigger_*` (uppercase, first), then `enforce_ledger_lineage_acyclic`, then `enforce_write_off_recovery`: the FK, then the walk, then the cap, per row. |
| 2 row naming the recovery uncapped | net of the whole same-customer tree, 0..amount | R10/R10b PASS; my E1 (a write-off under a recovery, then its own recovery: W1 −100, R1 +100, W3 −100 names R1, R3 +100 names W3: admitted; +0.01 under R3 refused "100.01, outside 0 to the 100.00" naming W3, the lower id, first; −100 under R3 admitted (both nets 0); −0.01 more refused "−0.01"; a second +100 recovery of W1 then admitted; aging then shows X at 100 in one bucket) — executed. |
| 3 recoveries counted gross (my S1) | same | R10c–R10e PASS; E1e/E1g above: a reversed recovery frees the cap (executed). |
| 4 walk stops at 10,000 without refusing | fails closed at 1,000 | R11 PASS; my E5: an original with 999 reversals above it in one statement admitted (depth 999), one more on top refused "does not reach an original within 1000 entries" (executed). |
| 5 operator chooses the close's edges | reads `tenants.receivables_aging_bucket_days` | C16/C16b PASS (a manual history row of `[1,2]` dated now; the snapshot stores `{15,45}`) (executed). Grants: history SELECT and the as_of EXECUTE gone, `tenants(id, receivables_aging_bucket_days)` added; `assert_seal_role_invariants()` passed in the tail (executed). |
| 6 withdrawal without a user | raises `not_null_violation` | P9f PASS (owner, empty `app.user_id`) (executed). It stays an operator's act: consistent with my r2 N7. |
| 7 comment/C12 use the 3-arg aging | 4-arg with stored edges | C12 PASS; comment reads as the diff shows (executed/read). |
| 8 three constraints unpinned (my N3) | pinned by exact definition | Present in `c_constraints`; the tail passed, so the renderings match the catalog (executed). M61 drops the key CHECK in the tail: caught at apply (predicted from the body). |
| 9 missing tests | R9–R11, CR11, CR12 | Present and passing (executed). |
| 10 runner label match | `FAIL {label}[:\s]` | Read: `R10` no longer matches `FAIL R10b:` (predicted). |
| 11 withdraw+money vs close deadlock | stated in the header | Read. S1 is its sibling on the write-off locks. |
| 12 "already closed" for a withdrawn period (my N1) | "is withdrawn" | C13b and CR12 PASS (executed). |
| 13 seal comment / `closed_by` | invariant refuses tally_app UPDATE on `closed_by` | Read; tail passed (executed). |

## The cap, shapes built (executed unless marked)

- **Across statements:** E1 above (seven statements, two write-offs, nets checked on both).
- **Within one statement, children before the write-off:** E4a — W −100, R +100 names W, A −100 names R, R′ +100 names W, listed children first: admitted (net exactly 100); E4b the same with R′ = 100.01: refused.
- **A write-off under another write-off's recovery:** E1b/E1c: the inner write-off joins the outer net (as −100) and has its own tree; both capped.
- **Another customer's row naming into the tree:** R10f PASS; my E2: Y's +5 under X's recovery admitted and not counted (X's cap then refuses +1 at "101.00" and admits −1 at 99). X's +500 under Y's row is admitted without any cap, and aging ages it as its own 500 debit, not netted into W1 (N1).
- **A loop plus a row under it under a write-off, one statement:** E4c refused "returns to itself" at once; the cap's bounded `UNION ALL` up walk and `UNION` down walk terminate on the row whose turn precedes the loop's refusal.
- **Isolation:** E8: at REPEATABLE READ an adjustment naming a charge (no write-off above) is admitted; a recovery is refused `25000` — the check sits inside the loop, before the lock, so every row under a write-off meets it.
- **Link-only walks find the same tree:** the up walk's `CASE` yields NULL at a customer break, which is where a join on the customer would stop; the final SELECT filters the write-offs by customer; the down walk's `mine` flag stops descent at a foreign row, which is exactly the aging's `c.customer_id = t.customer_id` join. R10f and E2 agree with the aging rows I read back (executed).
- **No step scans a ledger (executed at scale):** on the clone's 10-row unanalyzed ledger the planner chose a seq scan for the recursive step (cheapest for ten rows). With 150,010 rows (120k filler, 30k linked) and `ANALYZE`, the down walk's recursive step is `Index Scan using idx_account_ledger_reverses (reverses_ledger_entry_id = d_1.id)` in a nested loop, the up walk's step a memoized pkey lookup, and R10g's 300-deep tree under one write-off inserted in **1.2 s** on that ledger. Rolled back.

## Lock order (executed, two sessions)

The header says a row takes each write-off's lock above it in id order, after the head. True per row. A **transaction** holding the lock of W2 (a row under W2) and then posting a row under W1, against another holding W1 then posting under W2, deadlocks: session B got `deadlock detected` (40P01), A completed; nothing written by the aborted side. See S1. With the head: writers hold it FOR SHARE and wait on write-off locks held by other share-holders; the close waits FOR UPDATE on all of them; no cycle through the close (predicted).

## Blocking

None.

## Should fix

### S1. A deadlock on the write-off locks across rows of one transaction is not stated — **executed**

Two rows under two write-offs, in one transaction (or one multi-row statement, whose triggers fire in row order), take the advisory locks in row order, not id order; two such transactions in opposite orders deadlock, detected, one aborted. Same class as the withdraw-and-close deadlock the header states (Opus N1, r3). State it in the header's lock-order paragraph ("post under one write-off per transaction, or in the same order"), as that one is. A fix in the trigger cannot reach across statements, so the statement is the right remedy.

## Notes

- N1. **A row under another customer's row stands alone** (executed, E2b): it meets no cap (no write-off of its own customer above it) and aging ages it as its own original. Cap and aging agree, and the amount is as visible as a row naming nothing; its lineage is cut at the customer break. One for -23's general rule, if a cross-customer name should be refused outright.
- N2. **The 1,000 bound** (executed, E5): 999 ancestors admitted, 1,000 refused. A product chain is a few entries; nothing legitimate is lost.
- N3. **Per-row cost of the AFTER walks** (executed): 30,000 single-link reversal rows in one statement took 61 s on the clone (about 2 ms a row: the freeze's head lock, the lineage walk, the cap's up walk and its write-off lookup through `idx_ledger_type (tenant_id, transaction_type)` filtered by customer). Fine for the product's volumes; a bulk migration of linked rows would notice.
- N4. **The close reads the tenant row without locking it** (predicted): a setting committed between `v_at` and the SELECT is the one stored. The snapshot stores its edges, so reproduction is exact; only the 3-arg aging's reading of history at `recorded_at` could differ by that hair (R10's territory).
- N5. **A positive write-off** (predicted): nothing can go under it (a recovery fails the sign test; any net ≥ 0 is outside 0..negative), and it may itself sit under a recovery as a +amount. Fail-closed; no money admitted.
- N6. **The up walk's write-off lookup** on the small clone is an index range over the tenant's write-offs, once per inserted row, not per step (executed plan). With stats the planner may drive it from the CTE instead; either is one lookup per row.
- N7. **Seal** (executed via the tail and C14/C15): `tally_close`'s list is exact and the least the close reads; `receivables_aging_bucket_days_as_of` is no longer granted to it.
- N8. **Mutations M53–M63** (predicted from reading): M53 trips the pinned trigger definition; M54/M56 leave R10's +70 counted against 40 or against nothing; M55 admits R10b's −10; M57 admits R11's ring (no row returns to itself within 1,000); M58/M59/M60 are the direct guards; M62 counts C1's +5 so R10f's −1 is refused before the sentinel; M63 puts the customer back in the join (R10g's 30 s timeout is the catch, which the executed timing above supports); M61 is the invariant. None passes for the wrong reason that I can see; the runner's first-FAIL rule holds for each.
- N9. **Tests not present**: the two-transaction opposite-order lock shape (S1); a write-off under a recovery with its own recovery (E1, cheap to add to R10's run).
- N10. **Residuals R1–R10**: none blocking. R8's new wording is right; R10 is accurately scoped (the close no longer reads the history).

## Answers to the brief

1. Implemented: every P/S/G/W row and the drafting calls; nothing missed or half-done.
2. Paths around a rule: none found. Money in a closed period, period edits, gaps/overlaps, order, snapshot writes, head moves and GL mappings are unchanged since r2 (verified executed then; the diff touches none of their guards). Netting past the cap or below zero: refused in every shape above. Wrong customer or sign: refused. Loops and over-long chains: refused at insert. Only E2b's cross-customer row escapes the cap, and it escapes the netting with it (N1).
3. Seal: meets -20; grants exact and least (N7).
4. Snapshot: figures unchanged from r2 (C9–C12, C17–C18, CR7 executed); edges are the tenant's row at the instant (C16b).
5. Aging: correct for the shapes above; RLS-safe; coordinates required; edges validated.
6. Invariants: the three new pins hold by exact rendering (tail passed); the comment's claim now matches the check.
7. Tests: no check weaker than its label; no mutation passes for the wrong reason that I can see (N8); gaps in N9.
8. Residuals: none blocking.
