# Fable review — v5.4.2-27 r1 (a credit applied to a bounced payment's shortfall)

**Verdict: ready.** No blocking finding. Two should-fix items (one a residual to record and put to Ryan, one a test gap), the rest notes.

Frozen hashes checked first (md5 -q): all five match the brief. Clone `rv27fable` (TEMPLATE tally, TEMP revoked from PUBLIC, tally_app, tally_core; `has_database_privilege('tally_app', …, 'TEMP')` = f), patch applied strictly (`search_path=''`, `check_function_bodies=on`) twice: the second run printed "already applied … nothing to do". Clone dropped at the end.

## Reproduced

| What | Result |
|---|---|
| strict apply, twice | first applies, second skipped by its marker |
| `battery-27-frozen-r1.sql` | 80 PASS, rolled back (0 rows left in `shortfall_applications`) |
| `shortfall-27-frozen-r1.sh rv27fable` | SR1–SR8, 14 PASS, exit 0 |
| six re-issued functions vs `tally` (pg_get_functiondef diff) | additions only: the two `shortfall_applications` legs in `cash_source_draws`; `+ shortfall` in the two `applied` figures; `repaid` as a new column/term; `+ d.repaid` on the payment's own part in the cover; two purposes, the within-family exemption and the undo hook in `check_cash_source` |

Mutations and `ci.sh` not run (restricted). The mutation file was read: every anchor is a real line of the frozen patch and every named check exists in the battery or the race script.

## Findings

### S1 (executed) — a repayment from a credit that later escheats can never be undone, so the target's returned refund can never be recorded

Probe A6 (as tally_app): P pays 50, is refunded 30, bounces (30 short). Credit C (50) repays the 30; C's remaining 20 is remitted to the state (`escheated_to_state` event of 20, status escheated — admitted, nothing of C is left). Then P's refund check comes back uncashed: its row under the refund's posting row is admitted, the move to nsf is refused by `check_shortfall_repaid` ("undo the shortfall application first"), and the undo is refused by `check_cash_source` ("an undo only while its source has not ended", -23 Opus B3). Both refusals are right by their own rules; together they leave the bank's news unrecordable, forever, on this customer.

```
PASS A6  the source credit, 30 to the shortfall and 20 remitted to the state, escheats
PASS A6b the target's refund check comes back: refused until the repayment is undone (23514)
PASS A6c but the undo is refused: its source has ended (escheated) (23514)
```

The same shape is impossible with a voided source (a void needs the draws at 0, and a shortfall application is a draw now) and with a payment source (it cannot end while applied, R15). It is only escheat, which is years out, so it is rare, but a refund check can come back at any age and there is no operator path at all. This is the meeting of Ryan's option 1 with -23's "nothing comes back to an escheated credit" (2026-10-21), so it is Ryan's to settle, not a drafting slip. Options I would put to him: (a) record it as residual R5 and leave it to the core (the core nets before a refund and would not escheat a credit while a repayment it made has a refund still outstanding — but the database cannot know a check's fate); (b) let the undo of a shortfall application onto an escheated source land as a deficit on the credit, the way a give-back under a payment "that only cancels a deficit" is admitted (-23 r6); (c) refuse the escheat of a credit while it has a live shortfall application whose target still has a refund posted. (b) and (c) are meaning changes to -23's rules and I would not fold either without his call. Not blocking: the rule as built does what the decision says.

### S2 (executed) — the credit-refund leg of `enforce_shortfall_source_moves` has no test

The trigger checks the target's cap when a refund *of a family credit* leaves (`overpayment_root(NEW.refunds_customer_credit_id)` → its payment). The battery's S set and SR4 use a refund of the payment itself; SR8 uses a credit's refund but before any repayment (the 40001 path). A mutation that replaces that second `coalesce` leg with NULL would pass all 80 + 14. Probe A7c shows the leg works:

```
C2: PD 100, held whole as overpayment credit KD; KD refunds 60; PD bounces (KD -60). GD (60) repays: PD 0/60, KD 0, GD 0.
KD's refund check comes back (row admitted); the move to nsf:
PASS A7c refused: undo the shortfall application first (23514)
PASS A7d undo + the move together admitted; PD 0/0, KD 0, GD 60
```

Add that case to the battery (S set) and a mutation on the leg (M16b).

### N1 (executed) — a reversed target works; untested by the battery

Probe A3: a posted payment refunded 15 and then reversed by a non-nsf row (status reversed) reads -15/0; 15.01 is refused by the target's cap, 15 admitted. Every battery target is nsf. Worth one `admits` so M02's sibling (dropping 'reversed') is caught.

### N2 (executed) — statement shapes

- Multi-row INSERT of 20 + 20 against 30 short: refused as a whole, nothing lands (the AFTER ROW trigger sums the statement's rows). 20 + 10 in one statement: admitted, positions right. A 20 dated 03-13 with its undo of 5 dated 03-20 in one statement, plus 15 more dated 03-13: refused — the window sum reads 03-13 with the undo not yet there (A1c).
- Writable CTE, undo P2's repayment and take P2 back in one statement: admitted, P2 then moves to nsf (A2). Repayment from a posted P6 and P6's take-back in one statement, either order: refused — by `check_cash_source`'s R-06 cap when the repayment's CTE is first (the take-back row is already in the tree when the repayment's AFTER trigger runs), by `enforce_ledger_shortfall_source` when the take-back is first (A2d, A2e). Refused either way; just note the guard that answers depends on CTE order.
- COPY FROM as tally_app: PostgreSQL refuses it outright ("COPY FROM not supported with row-level security"). As the owner COPY fires the trigger: 31 refused by the target's cap, 30 admitted (P3).

### N3 (executed) — the accepted window reads money on an ended payment

After A7d (repayment 60 dated 03-13, undone 03-20, refund back): `payment_position_as_of(PD, 2026-03-15, now)` reads remaining +60. Design §8 states this. The customer's lines still add to the ledger at that date (the 60 is on PD instead of KD), so it is a which-line matter, not a money one. Mentioning because a reader asking "what did this ended payment hold on 03-15" gets a positive number with no row explaining it; AC-44's text at mirror should say the undo's date closes the window.

### N4 (executed) — "a family credit's void moves no money" holds; a voided overpayment credit's position is -23's shape

A7h–A7k: PF 100, overpayment credit K 70, PF's own refund 30, bounce (PF -30, K 0); G repays 30; K (no draws) is voided; PF still reads 0/30 and `check_shortfall_repaid(PF, NULL)` passes; 0.01 more refused. `customer_credit_position_as_of(K)` reads remaining 70 after the void (the voided credit is outside `overpayment_absorbed_as_of`, so issued = its amount); the same reading exists without -27, so it is -23's reader convention (status says voided), not -27's.

### N5 (predicted) — design vs. build, two lines §8 does not list

- §4 "inside the target's family … in the order a give-back restores them (the latest share first)": the built cover is -23 r7's, the overpayment credit first, then reissues in recorded order (`FOR i IN 1 ..` in both payment-side legs). Totals are the same; only which credit reads 0 first differs. Say so in §8 or change the sentence.
- §5 "`assert_cash_guard_invariants()` gains the new table's rules" / "joins … `assert_periods_guard_invariants()`": built as `assert_shortfall_guard_invariants()`, which does assert the freeze trigger. Fine; list it in §8.

### N6 (predicted) — partial take-backs

`enforce_ledger_shortfall_source` refuses any positive row under an applied source's posting entry, a 1.00 partial reversal included, even when the unapplied part would cover it. That is exactly -23's rule for a payment applied to bills (`enforce_ledger_reversal`'s take-back branch refuses while `sum(invoice_applications) <> 0`), so consistent; K7b tests it.

### N7 (executed) — a superuser's chosen status time is caught by -23's lineage rule for -27's rows

P3a: after a repayment, the refund's move to nsf with `status_recorded_at = now() - 1 minute` is refused by `enforce_payment_immutable` (cash_lineage_recorded reads `cash_source_draws`, which now carries the repayment). A9: an undo with a chosen `created_at` before the row it undoes is refused by the target leg of `check_cash_order` (23514).

## The brief's questions

1. **Design and rulings.** Implemented: the row (add-only, typed FKs with tenant and customer, undo as a negative row naming its target, operator and undo say why and who), the source counted in `applied` and in every cap and order check, `repaid` on the target, the target's cap from a date, the within-family purpose exempt from the family cap, option 1 at every give-back path I could name, R15 for the source's bounce, the freeze, RLS and FORCE RLS, grants, invariants. Half-done only in the sense of S1 above. The core's part (which credit first, when to net, one net balance) is left to AC-44 as the design says.
2. **Paths around a rule.** Tried: a repayment past what is owed at any date (K1/K5/H2, A1, A1c, A5 for a target with no deficit: a bounced deposit); a target not ended (K13/K13b); a source of another customer/tenant (K17/K17b/K22); deposit or pending source (K14/K14b); undo past, of another source, before its row, recorded before its row (K10/K9b/K9/A9); money back to a repaid family by the payment's refund (S2), a family credit's refund (A7c), a donation's undo (U2), a give-back under the posting entry (A4: -23 refuses it, the payment has ended), a family credit's void (A7i: moves nothing in the family sum), a reissue (only after the return, which is where the check runs); a source that bounces (K7/K7b/B2/B3/SR3, A2d/A2e); within-family exemption reached from outside the family — impossible by construction (`overpayment_root(source).source_payment_id = target`), and used to move money out — impossible (the target is the family's own payment, so the row nets to 0 in the family sum; F1a holds a family credit to the cap for another family's target). Isolation (SR7), shapes (N2), superuser loads (K23/K23b/A9/P3a). Nothing found.
3. **-23's properties.** The family sum in `check_shortfall_repaid` is `check_cash_source`'s family cap read the other way; I worked the F fixture by hand (family net 0 before and after the within-family row, after cross-family repayments, and after F6's undo — R1's own 40 beside K's -40) and the sum stayed right at every step. Positions add to the ledger with repayments present (A8 for c4, c2: payments 0, credits 60, balance -60). The re-issued functions differ only by additions (table above). `cash_drawn_at` unchanged is right: the split reads it only at a take-back's instant, a take-back under an applied source is refused, a chosen-time take-back between an application and its undo is refused by `check_cash_order`, and an ended target takes none.
4. **Concurrency.** Lock order followed everywhere I traced: head, target's payment, source's payment, source's credit; `enforce_ledger_shortfall_source` after the tree lock and -23's own payment lock; `enforce_shortfall_source_moves` under the locks `enforce_payment_immutable` took (the refund, then its source's payment, then the credit); the undo hook under the lock `check_cash_source` took. Every writer on a target's family goes through the payment's lock (draws, voids, escheats, reissues, refunds leaving, rows under the entry), so each cap is read under the lock that orders it. The only deadlock is the two-family opposite-direction one the header names; both writers retry 40P01. No instant found where a position reads a repayment and a state it should follow but does not: the target leg of `check_cash_order` orders repayments among themselves and after bounces and leaving moves (SR5, SR6, SR8), and -23's lineage rule orders a chosen status time after them (P3a).
5. **Invariants.** `assert_shortfall_guard_invariants()` checks what it says: the eight triggers by exact PG16 rendering and ENABLE ALWAYS, the fourteen constraints validated, the grants (table and column), the single policy with FORCE RLS, `check_shortfall_repaid`'s reach. I3/I3b/I3c prove it catches drift. Claims match checks; it does not pretend to check function bodies.
6. **Tests.** None weaker than its label that I found. B3 switches the ledger guard off inside a rolled-back subtransaction to reach the status guard — fair. K3b's "no ledger row" leg only looks at rows referencing a customer credit, but the balance-equality leg beside it covers the rest. Missing: S2's credit-refund leg (S2 above), a reversed target (N1), a multi-row shape (N2). Mutations: each named check is the first failure by construction of the fixtures; M17/M18 pin the two `p_from` choices, which is the subtle part.
7. **Residuals R1–R4.** None blocking. R1 and R2 are the core's by the rulings; R3 is -23's reading of a partial reversal; R4 is closed by the row. I would add R5 for S1.

## Probe files

`/private/tmp/claude-501/-Users-ryanscomputer-code-tally-utility/5e6b8bb5-06a7-4742-b166-ff5f4b04a6c3/scratchpad/probe1.sql` (A1–A10, 33 PASS, one transaction rolled back; built on the battery's helpers and fixtures), `probe2.sql` (COPY as tally_app), `probe3.sql` (COPY as owner, chosen status time). Each runs with `docker exec tally-pg psql -U tally -d <clone> -q -f`.
