# Fable review — v5.4.2-27 r2 (a credit applied to a bounced payment's shortfall; the carry)

**Verdict: ready.** No blocking finding. One should-fix (a test gap: one leg of the carry has nothing pinning it), the rest notes. Every r1 finding of mine is fixed or recorded.

Frozen hashes checked first (md5 -q): all five match the brief, and the brief matches `review-brief-27-r2.md5`. Clone `rv27fable` (TEMPLATE tally; TEMP revoked from PUBLIC, tally_app, tally_core; `has_database_privilege(…, 'TEMP')` = f for both app roles), frozen r2 patch applied strictly (`search_path=''`, `check_function_bodies=on`) twice: the second run printed "already applied (shortfall_applications exists); nothing to do". Clone dropped at the end.

## Reproduced

| What | Result |
|---|---|
| strict apply, twice | first applies, second skipped by its marker |
| `battery-27-frozen-r2.sql` | 116 PASS, rolled back (0 rows left) |
| `shortfall-27-frozen-r2.sh rv27fable` | SR1–SR9, 16 PASS, exit 0 |
| the five re-issued functions vs `tally` (`pg_get_functiondef` diff) | additions only — see below |
| `cash_source_draws`, `customer_credit_draws_as_of`, `check_cash_source` vs `tally` | additions only (the carry leg; the carry leg; purpose `shortfall_undo`, the two purposes of r1, the arrival-entry exemption, the undo hook) |

Mutations and `ci.sh` not run (restricted). The mutation file was read: each new anchor is a real line of the frozen patch and each named check exists in the battery or the race script.

## My r1 findings

| r1 | Status | Evidence |
|---|---|---|
| S1 — a repayment from a credit that later escheats could never be undone, so the returned refund could never be recorded | **fixed** by Ryan's carry (option 1): the undo is admitted on an escheated credit and what it gives back goes into a `shortfall_reissue` credit in the same transaction, checked at commit | battery E1–E14c; my probes A, B, D, F, G below; a real COMMIT of the undo alone is refused and leaves nothing (probe-r2-commit) |
| S2 — the credit-refund leg of `enforce_shortfall_source_moves` had no test | **fixed** | battery C6/C7 (KQ's refund leaving a repaid family), mutation M16b, race SR9 (ran: PASS) |
| N1 — a reversed target untested | **fixed** | battery T3/T3b |
| N2 — statement shapes | note, nothing to fix; the carry in a writable CTE with its undo works (probe F1) | |
| N3 — the ended payment reads money between a repayment and its undo | **recorded** as residual R5 and in design §9 | probe E5c reproduces it: on 03-21, with the undo dated 03-22, the ended payment reads remaining 30.00 / repaid 30.00 |
| N4 — a voided overpayment credit's position is -23's shape | note, unchanged | |
| N5 — design §8 said the latest share first and named the wrong invariant function | **fixed** in §9 ("Fable's notes on section 8") | |
| N6, N7 — partial take-backs; a superuser's chosen status time | notes, unchanged | |

## Findings

### S1 (executed) — the carry leg of `cash_source_draws` has nothing pinning it: no check reads it and no mutation names it

`cash_source_draws('credit', C)` now lists C's `shortfall_reissue` credits (patch lines 483–489). The battery never reads that set for an escheated credit, and no mutation touches the leg (M46 is the position's `issued`, M47 is `cash_drawn_at`). I traced what the leg feeds once C is escheated: the cap in `check_cash_source` (a second carry on C passes with or without it — the size check in `enforce_shortfall_reissue` is what holds the amount, and it reads `customer_credit_draws_as_of`, not this function), `check_cash_order`'s recorded-order leg and `cash_lineage_recorded` (C has no further move). So dropping the leg changes no battery outcome: a mutation `WHERE false` on it would pass 116 + 16. Not a money fault — the leg is belt-and-braces beside `customer_credit_draws_as_of`'s — but by the "every branch tested" lesson it should have a fixture that takes it. Cheapest: one `ok` after E7 (`EXISTS (SELECT 1 FROM public.cash_source_draws('credit', CE) d WHERE d.id = KE)`) and a mutation on the leg naming it. Two neighbours are pinned only indirectly and I would not add more: `customer_credit_draws_as_of`'s carry leg (E7b's `carried = 30` catches it) and `reissue_generation`'s branch (E13b's `= 1` catches it; M44 anchors `overpayment_root`'s copy of the same line).

### N1 (executed) — the carry's size with a take-back recorded before it

The brief asks whether the size is right as "-23's r9 form". The battery only has a take-back *after* the carry (E14). Probe A puts one before: Q 50 held whole as OQ; 10 taken back under Q (OQ absorbs 10, reads 40); P 30 refunded 30 and bounced; OQ repays 30 and escheats its other 10 (own 0). P's refund comes back: a carry of 20 is refused ("it carries what the undo gave back (30) … (30 before it)"), 30 is admitted. After: OQ own 0 / remaining 0, KA 30, P 0/0, KA in OQ's family, and `overpayment_shares` gives KA 0 of the earlier take-back and OQ its 10 (as recorded: KA did not exist then). KA then repays another shortfall (20) with no arrival entry, and Q cannot bounce while KA is applied (R15 reaches the carry, 23001 "undo that first"). Q cannot bounce while OQ is applied either, so "a take-back before the carry" can only be a take-back before the repayment, which is what A does.

### N2 (executed) — mixed lines, both ways, and a later take-back

Probe B: (i) two partial undos on one escheated goodwill credit, 10 then 20: the second without its own carry is refused at commit; a single carry of 30 naming the first undo is refused ("what the undo gave back (10)"); each carried, the credit reads 0 with carried 30, KB1 10, KB2 20. (ii) KB2 refunded 5, escheats 15, the refund comes back: a `refund_reissue` of a `shortfall_reissue` is admitted, generation 2, root NULL. (iii) The reverse: Q2 40 → OQ2; OQ2's refund 15 comes back → R1 (`refund_reissue`); R1 repays P2 10 and escheats 5; P2's refund comes back → undo on R1 + KD (`shortfall_reissue` under a `refund_reissue`): root OQ2, generation 2, in OQ2's family; OQ2 25, R1 0, KD 10. Then Q2 bounces: KD takes 10, OQ2 takes 30 (its 25 plus the 5 R1 sent to the state that never came back), OQ2 reads −5, Q2 0/0. That placement is -23's cover rule (what none held falls on the overpayment credit first), not -27's; what matters for -27 is that with the carry in the family the target's cap still reads Q2's shortfall as 5: 5.01 refused, 5 admitted, then Q2 0/5 and OQ2 0.

### N3 (executed) — after the undo, the escheated credit's only outlet is the carry

Probe D: with 30 back on an escheated credit, a new repayment from it, a refund of it and a second remittance are each refused (-23's status rule, 23514). A carry naming an undo whose credit is active ("its credit is active"), one naming a payment's undo ("its source is a payment"), and one for another customer (the new three-column FK) are refused; the right carry closes it, and the new credit cannot be voided. The invoice-application and donation undos of an escheated credit go through purpose `undo` unchanged (`v_status IN ('posted', 'active')`): predicted refused, not run.

### N4 (executed) — the boundary with a partial undo and a back-dated repayment

Probe E: G repays 30 on 03-13; a partial undo of 10 dated 03-20. A repayment of 10 from another credit dated 03-15 is refused (strict reading: the family would hold 10 from 03-15 to 03-19); dated 03-21 it is admitted. The refund comes back: refused; undoing only the 03-21 repayment: still refused (20 of 03-13's stands); undoing both, dated 03-22: admitted, P 0/0, both credits whole. The two readings cannot trap the operator: the retroactive reading (undo at its row's date) moves money back to earlier dates, so at every date it is at most as strict as the strict one; they differ only on the intervals between a repayment and its undo, which is R5 exactly. I found no sequence of back-dated repayments, partial undos and leaving moves that leaves the family holding money at a date the positions read outside those intervals.

### N5 (executed) — superuser shapes

Probe G, as the owner: a carry inserted already voided in the undo's transaction is refused at commit (nothing carried); a carry with a chosen `created_at` before its undo is refused by -23's recorded order. A credit born with any status but active (escheated, voided) is refused by -23's `enforce_cash_birth`, so the carry cannot be born ended. A real COMMIT with the undo alone (probe-r2-commit) is refused by `enforce_shortfall_undo_carried` and the fixture rows are gone.

### N6 (predicted) — cosmetic

`payment_position_as_of(...).repaid` prints `0` for a payment with no shortfall rows and `0.00` otherwise (the battery's `pos()` shows `0.00/0` for Q). A reader comparing text sees two spellings of nothing; `coalesce(sum(...), 0::numeric(12,2))` or `round(…, 2)` would make them one. Nothing depends on it.

## The brief's questions

1. **Ryan's carry and the r2 plan.** Implemented as the plan lists: purpose `shortfall_undo` admitting an escheated credit; origin `shortfall_reissue` and `customer_credits.reissues_shortfall_application_id` with its CHECK, three-column FK and one-per-undo index; `enforce_shortfall_reissue` (undo of a credit's repayment, credit escheated, depth, date, size as -23 r9, then a `reissue` draw on the credit under the payment-then-credit locks); `enforce_shortfall_undo_carried` at commit; `enforce_shortfall_reissue_rows` (no credit_issued row, key fixed, never voided); the five re-issued -23 functions; the carry leg in `cash_source_draws` and `customer_credit_draws_as_of`; the arrival-entry exemption; the boundary; the two targets; the privileges asked alone; the harness. Nothing missed that I found. The two -23 readers the author left out (`cash_lineage_recorded` and `check_cash_order`'s voided-reissue legs; the ledger guard's rows under a credit_issued entry) are rightly left: the credit is never voided (UPDATE refused; born voided refused by -23) and has no entry. Opus S3's invoice-application undo on a repaid family: I agree it is the same call as the donation undo (`check_cash_source` purpose `undo` then `check_shortfall_repaid`), which U2 and M15 pin; no own case needed.
2. **Paths around a rule.** Tried: a carry smaller or larger than what the undo gave back (A2, E4), dated before the undo (E5), naming a repayment / a payment's undo / an active credit's undo / another customer (E6, D4–D6), two per undo (E8), a second undo on the same credit without its carry (B1), one carry for two undos (B2), the carry in a later transaction (real COMMIT refused), the carry before the undo (FK: predicted), the undo's money spent any other way (D1–D3), the credit born ended (-23), a writable CTE (F1), chosen times (G2). The within-family shape cannot reach the carry: a family credit applied to its own payment's shortfall cannot escheat afterwards (the family cap in `check_cash_source` is over its payment by the shortfall itself), so the escheat trap only exists across families, which is what the carry covers.
3. **-23's properties with a carry in a family.** The carry is a family member (`overpayment_family`), so its own row is excluded from the family sums in both caps and its draws count (A4, B10); it takes a share of a later take-back (E14c, B9 shares: KD 10) and none of an earlier one (A3b); the cover order is -23's; `cash_drawn_at` counts it so the escheated credit holds nothing at a take-back's instant (E14c; M47). Positions add up in every probe (OQ −5 + KD 0 + Q2 0 = the 5 that went to the state).
4. **Re-issued functions.** `reissue_generation` and `overpayment_root`: the recursive step becomes two LEFT JOINs and a `coalesce` on the two parents, the origin filter admits `shortfall_reissue`; plan pins and `reissue_line_bound()` kept. `overpayment_family`: the step becomes a LATERAL UNION ALL of the two child shapes; pins and bound kept. `cash_drawn_at`: three legs appended (shortfall rows, the target's repaid, the carry). `customer_credit_position_as_of`: one `IN` list. Nothing else differs (diffed against `tally`, not the patch text).
5. **Concurrency.** The carry's locks (the family's payment, then the credit) are the ones the undo's `check_cash_source` already took in the same transaction, after the target's (`enforce_shortfall_application`), after the head: no new order and no inversion. `enforce_shortfall_reissue` reads the undo and the credit's status before locking; harmless, since the carry can only be in the undo's transaction (the commit check) where the locks are held, and a carry naming an undo that committed without one is refused by the size (the credit then reads 0 of its own, so only 0 would fit). SR9 ran: the returned refund waits on the payment's lock and is then refused.
6. **Invariants.** The new triggers, constraints and index are checked by exact rendering, and each required privilege is asked alone with the prohibitions as lists (where "any one held" is the right reading). Claims match the checks; it still does not pretend to check bodies.
7. **Tests.** None weaker than its label. S1 above is the gap. Each new mutation's named check is its first failure by construction; M42 would be caught by E6 even if the size check answered first (a different message fails `refuses_at` too).
8. **Residuals.** R1–R4 as in r1; R5 is my N3, correctly stated (E5c). None blocking.

## Probe files

In the scratchpad: `/private/tmp/claude-501/-Users-ryanscomputer-code-tally-utility/5e6b8bb5-06a7-4742-b166-ff5f4b04a6c3/scratchpad/probe-r2-fable.sql` (A–G above, one transaction rolled back; built on the battery's helpers) and `probe-r2-commit.sql` (a real COMMIT). Each runs with `docker exec tally-pg psql -U tally -d <clone> -q -f`.
