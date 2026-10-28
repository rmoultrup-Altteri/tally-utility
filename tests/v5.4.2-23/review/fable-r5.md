# Fable review: v5.4.2-23 r5 — cash (round 4's findings, the take-back split, the reissue's remainder)

**Date:** 2026-10-28. **Frozen hashes:** all six match the brief (executed, `md5 -r`).
**Clone:** `rv23fable` from `tally`, TEMP revoked from PUBLIC, tally_app, tally_core (`has_database_privilege` false for both); frozen r5 strict-applied twice (`search_path=''`, `check_function_bodies=on`): first run clean, second skipped by the marker (executed). Rebuilt once from the template after the race script's committed fixtures collided with the battery's ids (the battery and the races are not meant to share a database); dropped at the end.
**Reproduced (executed):** `battery-23-frozen-r5.sql` 293 PASS, rolled back. `cash-23-frozen-r5.sh rv23fable` 33 PASS (CR1–CR22), no other line. Mutation runner not run (brief); N171–N191 read. Not read: `opus-r5.md`, `codex-r5.md`.

Every claim is marked **executed** (on the clone; single-transaction probes run as tally_app under `app.user_id` on the frozen battery's fixture, as its last statement before ROLLBACK, owner where marked; two-session probes commit into the clone under a tenant of their own) or **predicted** (from the code). Probe files in my scratchpad: `probes.sql`, `probes2.sql` (single transaction, P1–P12), `rr2.sh`/`rr3.sh` (RR-A, RR-B, RR-C), `rr4.sh` (RR-D).

## Verdict: not yet

r5 closes every round-4 finding it claims (table below), applies K-10 and Ryan's two decisions faithfully, and the B2 refinement is the right reading of K-10 (W3 is Kyle's refund cap to the dollar; V1/V2 unchanged). The split itself is sound in every single-instant and in-order shape I tried: both positions, both caps and the escheat check read it alike, each position's remainder is exactly what its cap admits, the two add up to the ledger, and the as-of reading is not rewritten by a later status move across transactions (RR-C). One thing is blocking, and it is the recorded-order question the brief asked about: a take-back under a payment's posting entry is the one row that reads the draws on the payment and its credit at its instant and is **not** ordered against them. A take-back whose transaction began before a draw's but posted after it is admitted with the earlier instant, so the split reads the credit as still holding money it had already paid out, or reads a credit that existed as not yet there. The pool cap keeps K-10's money, but the positions then disagree with the caps for good (B1, executed two ways). Two should-fix items: a lock-order cycle r5 opened on the mandatory return-and-reissue transaction (executed deadlock, the settlement the victim), and a give-back refused where it would only cancel a K-10 deficit on an escheated credit.

## Round-4 findings

| r4 finding | Status | Evidence |
|---|---|---|
| Opus B1 / Fable B1 / Codex S1: a take-back read differently by the payment and its credit | **closed as a rule; its recorded order is open (B1 below)** | `overpayment_split` read by `payment_position_as_of`, `customer_credit_position_as_of`, `check_cash_source` (both caps and the pool) and the escheat check (patch 1468–1523, 1548–1553, 1583–1588, 2551–2613, 2043–2048; predicted from the code, executed by W2–W4, W12). Opus P1 and P2 are W2 and W3 (executed). My shapes, each with "position's remaining = what its cap admits, one cent more refused" on both sides (executed, probe `agree()`): a credit partly donated then a take-back larger than it held (P1: payment 65, credit 0); the payment's own part exhausted by a posted refund, then a take-back (P2: payment −20, credit 0, nothing admitted either side); a credit refunded 15 of 20, take-back 10 (5 absorbed), then given back (P3: 35/0, then 40/5); an escheated credit beside a payment whose own part holds (P10: the deficit does not touch the escheated credit while the payment has 10 to give; the payment's cap admits exactly 10). The deficit never sits on one side while the other has money, in recorded order. |
| Opus B2 / Fable S1 / Codex B1: a returned refund paid out again | **closed** | patch 782–801; W1, W1b, W1c, CR21 executed; a superuser under the nsf row refused too (P5, executed, ENABLE ALWAYS); a second return under the refund's +30 refused by the tree cap (P5b). |
| Fable B2 / Codex B2: a give-back onto an escheated credit | **closed** (and S2: it also refuses cancelling a deficit) | patch 749–761; W5/W5a executed; P11 below. |
| Codex B3: K-10 through an escheated overpayment vs the required reissue | **closed** | patch 2809–2826, 2878–2884; W6–W6d (10 bounced: 20 carried), W7–W7b (bounced in full: nothing carried, −70 owed) executed. A reissue from a credit still active carries exactly the refund (P6: 20 refused, 30 admitted; executed). |
| Codex B4: a future status time hides the commit check | **closed** | patch 1802–1810, 1941–1949, 2084–2091; W10–W10e executed, for the owner. |
| Fable B3: an arrival row at REPEATABLE READ | **closed** | the pin at the top of `enforce_ledger_reversal` (508–519), the reversal path's gone; CR20/CR20b executed. |
| Opus S1: a reissue dated before the return | **closed** | patch 2801–2808; W8/W8a executed. |
| Fable S2 (R15), S3 ("either order"), N1 (history loads post pending); Codex S2 (N170, W9), S3 (pending wording) | **closed** | R15 restated (patch 264–273); the commit check's comment (2857–2865); the birth comment (2072–2075); W9; the reader's comment (1533–1539). |
| Fable N2 (lock order: no cycle in r4) | **r5 opened one: S1 below** | |
| Opus N2 (two-transaction R17) | **open by design, now R17** | and N1 below. |

## Rulings

- **K-10, the B2 refinement:** W3 is Kyle's example turned around (60 paid, 20 refunded from the credit, 10 taken back: 30 left; a refund of 31 refused, 30 admitted), and the pool cap is his refund cap stated once for the payment and its credit together. The plan's "up to the credit's amount" would have given 40; the decision log's reason is right. V1/V2 (through the credit, full and partial) unchanged (battery executed). Faithful.
- **Ryan, statuses and the reissue (option 1):** the reissue still carries exactly what came back wherever the credit has it (W6b when 20 of 30 is left, W8a, P6); where the payment also bounced it carries what is left, at most the refund, and the customer owes the rest: K-10 decides between two of Ryan's rulings, and the refinement is reported, not assumed. Faithful.

## Blocking

### B1. A take-back under a payment's posting entry is not recorded in order with the draws on the payment and its credit, so the split can read the credit as holding money it had paid out, or a credit as absent (executed, two sessions, `rr3.sh` RR-A and `rr2.sh` RR-B; history-load variant P7b)

`overpayment_split` reads, for each take-back, what the credit and the payment's own part still held *at the take-back's instant* (`cash_drawn_at(…, r.created_at)`), and `r.created_at` is the take-back's transaction start (`stamp_log_created_at`: `now()`). Every draw is ordered against the tree: `check_cash_source` refuses a draw recorded before a take-back already in the tree (2522–2535: 40001, or 23514 for a chosen time), and `enforce_ledger_reversal` orders tree rows among themselves (667–687). Nothing orders a take-back against a draw already counted on the payment or its credit, or against the credit itself: the payment-source branch (738–781) takes the payment's lock, reads the credit's applications and pending refunds, and admits the row with whatever instant its transaction began at. A *posted* refund of the credit, a donation, a remittance, or the credit's creation do not hold the bounce, so the shape is an ordinary one.

**RR-A.** PA 60 posted, KA 20 (committed). Session A: `BEGIN; SELECT now(); pg_sleep(2)`, then the take-back 10 under PA's posting entry, `COMMIT`. Session B, one second in: a refund of KA for 20, posted, committed before A's row. Both commit (A waits on nothing: B's locks are gone).

```
split:   take-back 10 at 17:02:27.89, absorbed 10      (B's refund is at 17:02:28.92: "not yet there")
KA:      issued 10, refunded 20, remaining -10
PA:      received 50, credited 10, remaining 40
refund 40 of PA (what it reads): refused by the pool ("and its overpayment credit")
refund 30 of PA: admitted
```

Money: K-10's 30 holds, by the pool cap only. The record: the customer "owes" 10 on the credit and the payment shows 10 it can never give — the exact reading Opus's r4 P2 showed and r5 set out to remove, reached by two writers in the wrong order. Nothing later repairs it: the split is as-of, and the instants are fixed.

**RR-B.** PB 60 posted. Session A as above; session B creates KB, an overpayment credit of 60, before A's take-back 10 lands.

```
split:   take-back 10 at 17:01:51.05, absorbed 0        (KB is at 17:01:52.06: "recorded before the credit")
KB:      issued 60, remaining 60;  PB: received 50, credited 60, remaining -10
refund 60 of KB (what it reads): refused by the pool; 50 admitted
```

The credit was there when the take-back was written (the guard saw it) and reads as sized after it. Same class.

**P7b (owner, executed).** The history-load variant: payment, credit and the credit's posted refund loaded at −3h, −3h, −2h; a take-back at −2h30 is admitted (23514 missing) and splits as RR-A (credit −10, payment 40); the mirror — a credit draw at a chosen time before the refund — is refused 23514 by `check_cash_source`'s draw leg (control, same probe). A superuser's chosen past status time rewrites the split the same way (P12), consistently with the chosen times.

**Fix:** in the payment-source branch (and the refund-tree branch needs nothing: a refund's rows are read by status, not by instant), after the payment's lock, refuse a row under a payment's posting entry recorded before any row already counted against the payment or its live credit — `cash_source_draws('payment', …)` (which includes the credit itself), `cash_source_draws('credit', …)` of the live credit, and the leaving moves `check_cash_source` already lists (2497–2518) — 40001 when `NEW.created_at = now()`, 23514 otherwise; the same three legs, with the same messages, so the retry contract is one. Then the "began earlier, posted later" writer retries and lands after. Tests: a race leg (RR-A's shape: the take-back's session begins first; expect 40001 and a clean retry), a battery check at chosen times (P7b), and a mutation dropping the leg. Give-backs can take the same leg for the cost of nothing; they read `v_abs` at their instant too.

## Should fix

### S1. A lock-order cycle on the return-and-reissue transaction (executed, `rr4.sh` RR-D)

The header's order is "a source before what draws on it: payment, then its credit" (r5: every credit draw, the give-back, the reissue — 2816–2818). A credit's refund that leaves takes the refund's own lock, then the *credit's* (1907–1913), never the credit's payment. Ryan's rule requires the return, the move and the reissue in one transaction, and the reissue then takes the payment's lock while the credit's is already held: credit → payment, against every payment → credit path.

```
P 100 posted; K 100 (overpayment), refund R 30 posted, 70 remitted, K escheated; take-back 10 under P (all committed)
A: BEGIN; -30 under R's posting row; R -> nsf (holds R, K); sleep 3; reissue 20   -> needs P
B: BEGIN; give-back -10 under the take-back (tree -> P -> K)                       -> waits on K
A: ERROR: deadlock detected (40P01) — the settlement transaction is the victim
B: proceeds, refused by the escheated-credit guard (as it should be)
```

A retry of A succeeds. Not unsafe; but it is a cycle on the one transaction the design mandates, with the void of K, any (mistaken) draw on K, and any give-back under P on the other side, and the stated order claims there is none. **Fix:** the leaving move of a credit's refund takes the credit's payment lock first when the credit is an overpayment credit (as the credit's void does at 1966–1967), and the header says so. Test: a race (RR-D's shape: B waits, no deadlock, A commits), and a mutation dropping the payment lock there (the deadlock, as N191's style).

### S2. A give-back is refused where it would only cancel a K-10 deficit on the escheated credit (executed, P11)

P 100 posted, K 100 held, 100 remitted and escheated; a take-back of 20 under P keyed in error: the split puts it on the credit as a deficit (K −20, P 0). The correction, −20 under the 20, is refused by the new guard ("post a new payment"). No money would come back to be drawn: the credit would read 0 (it absorbed 20 that were never held). As it stands the customer owes a phantom 20 on an escheated credit for good, and the suggested fix invents a payment. Ryan's rule is about money coming back onto an escheated credit; W5 (the credit held 40 of the 60, the 20 would be drawable again) is that; P11 is not. **Fix:** refuse the give-back only as far as it would leave the escheated credit positive — read the credit's position after the row (it is AFTER INSERT) and refuse when `remaining > 0`, or cap the give-back at the credit's deficit. If the author reads Ryan's rule as literal, ask him with P11's shape in plain words: a bounce keyed in error against a customer whose credit was already sent to the state.

### S3. Tests for B1 and S1 as above; and the `agree()` invariant

Opus r4 asked for "position's remaining equals what its cap admits at a far date" as a check; r5 has it by hand (W2a–W2d, W3a–W3c, W4a). One helper over every W pair (remaining admitted, one cent more refused, both sides) would have caught B1's shape the moment a race leg existed, and is what the brief's "does each position's remainder equal what its cap admits" means.

## Notes

- **N1 (executed, P4b; R17).** Within one instant the split floats. In one transaction: credit 20, its refund 20 posted, a take-back 10 (absorbed 0), the refund then returned and moved to nsf — the split re-reads the refund as already nsf (`status_recorded_at` = `now()` = the take-back's instant), absorbs 10, and a refund of 10.01 from the credit is admitted: the new draw shrinks what the credit "held", pushing the take-back onto the payment (payment 39.99). Across transactions the split stays (RR-C, executed: absorbed 0 before and after the return; payment 30, credit 20). This is also why N181 (the pool removed) is caught at W3a: the individual cap admits 31 there once the split floats, and only the pool refuses. R17 covers it; the header's "post each act in a transaction of its own" is the operative rule. Worth one sentence in R17: within one instant the individual caps are the pool.
- **N2 (predicted).** The escheat move takes the credit's lock only (1997) and reads `overpayment_split`, which reads the payment's tree; a take-back takes the payment's lock and, in r5, not the credit's. A take-back landing between the move's "nothing left" read and its commit leaves the credit escheated with a deficit the check would have refused (`v_left <> 0`). The state is one K-10 produces anyway (W7); not harmful. The remittance event that usually precedes the move takes payment → credit, so in practice the two serialise.
- **N3 (predicted).** A refund's return keyed in error (the check cleared) has no correction on the record once the refund is nsf: the status is terminal and the tree is closed. "A re-sent refund is a new refund" then means a refund row for a check never sent; the money is right, the history says two refunds. The same family as r4 N3; say it where the refund-tree rule is stated.
- **N4 (predicted).** The status-time check (1805) runs before the stamp (1831) replaces a non-superuser's value, so an app that passes a future `status_recorded_at` with its move now gets 23514 where it got the stamp. Harmless; the app should pass none.
- **N5.** Mutations N171–N191 (read, not run): each new leg has one, named at its check; N145's retirement is right (CR22/N191 cover the order). None reaches B1 (every W shape is one instant or in recorded order) or S1 (no race holds the credit's lock through a reissue). N181's anchor is W3a for the reason in N1; W12 is the explicit check.
- **N6 (executed).** The pool cap was never stricter than K-10 in the shapes tried (P1, P3, P10, RR-A, RR-B: it admits exactly the K-10 remainder) and never missing where a live credit exists; rightly absent when the credit is voided (no `v_pool_pay`).
- **N7 (executed, P6).** A reissue from a credit still active is admitted for exactly the refund and moves the money from the old credit to the new (carried). Consistent; the "active or escheated" purpose says so.
- **N8.** Residuals R1–R17: none blocking. R15's new text matches the guard; R16's sentence (Opus N1) is right; R17 as in N1.
- **N9.** `tests/v5.4.2-23/red-r5-against-r4.txt` not reproduced (the brief lists it; I reviewed r5 only).

## Probe record

Fixture: the frozen battery's own (tenant …23a1, customer C5, op1), probe ids …2f00xx; two-session probes under tenant …2f00a1 (committed into the clone). Order: battery, P1–P10, the race script (33 PASS), RR-A/B/C on the first clone; the clone rebuilt from the template (the battery's ids collide with the races' committed rows); P11, P7b, P12 and RR-D on the rebuilt one. Clone dropped after this file was written.
