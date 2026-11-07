# Opus review — v5.4.2-24 r5 (unmatched cash and agency pledges)

**Date:** 2026-11-07. **Reviewer:** Opus. **Brief:** `review-brief-24-r5.md` (md5 `c3a8e09cb855f2bf9bc95311bb971e43`, which matches its `.md5`). I read the r2 to r5 plans and my own r4 review. I read no other reviewer's file.

**Verdict: not yet.** One blocking item. Round 5's new walk leaves out every row typed `nsf`, including one with a negative amount, which gives money back to the customer. A row like that can sit only under a reversal, where it can only mean an undo of that reversal. Leaving it out makes the misposted share too large. A receipt of 100 whose payment the bank took half of can then give back all 100, and pay out 100 again. Round 4 counted this shape correctly (it was my r4 probe Q4), so this is a regression. The fix is one condition on the walk, and with it every battery check before the invariant pin passes. Both round-4 findings are otherwise closed, and every earlier finding still is.

## Hashes and reproduction (executed)

- **Hashes.** All six frozen md5s match the brief. The live copies (patch, battery, races, mutations) have the same md5s as the frozen ones.
- **Clone and apply.** I made the clone `rv24opus` (`TEMPLATE tally`) and revoked TEMP from PUBLIC, `tally_app` and `tally_core`. The strict apply (`search_path=`, `check_function_bodies=on`, `ON_ERROR_STOP=1`) ran clean, and the tail's invariants passed. The second run printed `v5.4.2-24: already applied (suspense_receipts exists); nothing to do`.
- **Battery.** `battery-24-frozen-r5.sql`: 260 PASS, 0 FAIL, rc 0.
- **Races.** `suspense-24-frozen-r5.sh rv24opus`: 24 PASS, 0 FAIL, rc 0.
- **Not run.** I did not run `ci.sh` or the mutation runner. I did not apply -25, -26 or -30. r5 changes only one of -24's own functions, so I relied on the author's `ci.sh` result for the ordering beside them (predicted).
- **Restrictions kept.** I created, dropped or altered no role, and I did not touch `tally`. The clone is dropped, and my files in the container's `/tmp` are removed.
- **How the probes ran.** Each probe used battery lines 1–178 (the helpers and fixtures) as a prefix. My helpers (`led`, `try`, `rev`) were created as the owner and granted to `tally_app`. The probe then ran under `SET ROLE tally_app` at READ COMMITTED. Each probe was one transaction, rolled back.

## Round-4 and earlier findings: are they closed?

| Finding | State | Evidence |
|---|---|---|
| r4 Fable B1 (a bank's take-back filed under a reversal's undo) | closed for that shape; see B1 | P14c passes. My D4 (a reversal, its undo, a re-entry, its undo, and the bank's take-back under the last undo) reads 0. Executed. |
| r4 Opus S1 (a misposting return dated before its payment) | closed | The new date rule refuses a return dated before `payment_date`, with a message that names the payment's date. P9b11 and P9b12 pass. My r4 shape Q5 now meets this rule rather than the below-zero cap. Executed (battery). |
| r3, r2 and r1 findings | still closed | The code paths are unchanged apart from the walk. The battery and races pass. Executed. |

Apart from B1, the patch implements the design, CI-053, CI-056's record side, and Ryan's 11-07 rule within L5 and L6.

### The walk: shapes tried (executed, as `tally_app`)

| Case | Tree under the posting entry (−100) | Right answer | r5 gives |
|---|---|---|---|
| P14c (Fable r4) | adj +100; its undo −100; nsf +100 under the undo | 0 | 0 |
| P14d | nsf +100; its undo −100; adj +100 | 100 | 100 |
| D4, four levels | adj +100 / −100 / +100 / −100, then nsf +100 at the bottom | 0 | 0 |
| Deep | a 996-row chain alternating +100/−100 under the posting entry, nsf +100 at the bottom | 0 | 0, in 5.7 ms |
| **B** | nsf +50; adj A +50; a row typed nsf, −50, under A; adj A2 +50 | **50** | **100** |
| **Q4** (my r4 probe) | nsf +40 and its undo −40; nsf +30; adj +70 with a row typed nsf, −20, under it; adj +20 | **70** (r4 gave 70) | **90** |

The walk is bounded. -22's lineage trigger (`enforce_ledger_lineage_acyclic`, ENABLE ALWAYS) refuses any chain that doesn't reach an original within 1,000 entries, or that loops. So the tree is at most 1,000 deep and has no cycle, even in a superuser load. The plan is pinned, and the 997-deep tree took 5.7 ms.

---

## B: blocking

### B1. A row typed nsf with a negative amount, under a reversal, is left out of the misposted share. The share comes out too large, and the receipt pays out money that never arrived (executed)

**The rule as built.** The share is the net of the posting entry's tree, leaving out every `nsf` row and everything beneath it (`enforce_suspense_disposition`, the join `AND l.transaction_type <> 'nsf'`). The design treats each nsf row as the bank's act, wherever it is filed.

**Where that goes wrong.** -23's cap on each ancestor (its remainder stays between 0 and its own amount) means a negative row can sit only under a positive one. And a negative nsf row can't sit directly under the posting entry. So a negative row typed nsf always sits under a reversal. The bank doesn't act on the utility's own adjustments, so a row there can only be an undo of that reversal: money given back to the customer, with the label `nsf` chosen by the clerk. Leaving it out drops a minus, and the misposted share grows by its amount. The `transaction_type` is the writer's label. This is the "guard the act, not the label" lesson in `sql/PATCH-LESSONS.md`.

**Probe B** (as `tally_app`, READ COMMITTED):

- A receipt of 100. Its payment of 100 to C1 is posted.
- The bank takes 50 back (nsf +50, under the posting entry).
- A misposting reversal A (+50). A is undone by a row the clerk typed as nsf (−50, under A). A is entered again (A2 +50).
- Every row was admitted by -23. The posting entry's remainder is 0, so the move to `reversed` (naming A2) was admitted.

```
B return 100.01 => REFUSED 23514 ... (100.00 of its 100.00; what the bank took back stays spent)
B return 100    => ADMITTED
B held          | 100.00
B then 100 from the receipt to C2 => ADMITTED
```

The customer's ledger nets to 0, and the bank kept its 50. So 50 came back as misposted money, but the receipt got back 100 and paid C2 100. The receipt of 100 has now paid out 150 (C2's 100 plus the 50 the bank took). That breaks the cap's purpose (CI-053: suspense money is never applied twice). Round 4's rule (each direct non-nsf reversal at what is left of its own tree) gave 50 here, and 70 for Q4. r5 gives 100 and 90.

**Fix (measured).** Leave out only nsf rows that take money from the customer (`amount > 0`), and what is beneath them. In both legs of the walk:

```sql
... ON l.reverses_ledger_entry_id = e.id AND NOT (l.transaction_type = 'nsf' AND l.amount > 0)
... ON l.reverses_ledger_entry_id = d.id AND NOT (l.transaction_type = 'nsf' AND l.amount > 0)
```

I replaced the function with this one change inside the battery's transaction:

- B gives 50, and Q4 gives 70.
- Every battery check before I1 passed (240 of them), P14a to P14d and P9b among them.
- I1 then failed only on `c_bodies`' md5 pin, as it should.

A negative nsf row under a positive nsf row is already inside a subtree that is left out, so the condition changes nothing there. The safe reading is the right default anyway. When the database can't tell whether a row is the bank's act, it should take the reading that keeps the money spent, which is what "what the bank took back stays spent" promises.

**Tests to add:** B and Q4 as battery cases, and a mutation that removes the `amount > 0` condition.

---

## S: should fix

None.

---

## N: notes

- **N1 (executed). A misposting reversal filed under the undo of a bank's take-back strands the money until it is re-filed.** The shape is nsf +100, its undo −100, then adj +100 filed under the undo. -23 admits all three rows. It refuses the move to `reversed` naming the adjustment, because the move must name a direct non-nsf reversal of the posting entry. So the payment stays `posted` with nothing left, and the return is refused because the payment isn't reversed. The tree isn't frozen while the payment is posted, so the clerk can undo the misfiled row and file it under the posting entry. That gives P14d's shape, and the 100 comes back. This fails toward protection, and the path out exists. No change needed. Possibly worth a sentence in the operator guidance.
- **N2 (read). The walk filters by type inside the join.** The walks lesson says to join on the link alone and apply tests outside. With the plan pinned, and a 997-deep tree at 5.7 ms, this causes no harm. It is a style difference, not a risk.
- **N3 (read). The function-level `SET enable_*`** also applies to whatever `enforce_suspense_disposition` calls, such as the receipt's cap. That is harmless: those reads are indexed and small.
- **N4 (read). -23's helper bodies.** r5 no longer calls `ledger_entry_remaining`, so my r4 note N2 no longer touches -24. The manifest drops it from `c_app_exec`, and `c_bodies` gains the new md5 and the new settings.
- **N5 (carried). `c_app_exec`'s NULL leg.** A missing function makes `has_function_privilege` return NULL, which the check drops. Every listed entry is also pinned in `c_bodies`, so nothing escapes today. `coalesce(…, false)` would make the check say what it means.
- **N6 (judgement). Known limits L1–L5.** None blocks. L4 (what the misposted share counts) is B1.
- **N7 (predicted; executed in r1). Statement shapes and concurrency.** r5 changes only the body of the misposting branch, inside the same AFTER ROW trigger under the receipt's lock. Once the payment is reversed the tree can't change (executed in r4), so reading it without the tree's lock is sound. Multi-row, writable CTE and COPY were not re-probed.
- **N8 (environment).** The two `crystaldba/postgres-mcp` containers (`pgmcp-67591-…`, `pgmcp-67190-…`) are still running beside `tally-pg`. I left them alone.
