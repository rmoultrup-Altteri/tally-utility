# Opus review: v5.4.2-27 r2 (shortfall applications)

**Verdict: not yet.** One blocking finding, executed. An undo of a repayment can be dated in the future. The new return check then counts it from the repayment's own date, so a returned refund is admitted while the ended payment holds the money on every date up to the undo's. The customer's credit is locked for that whole span, and nothing can correct it afterwards. The fix is small. Everything else in r2 holds: my five r1 findings are fixed, the carry is sized and closed correctly, the five re-issued functions only add, and the mixed reissue lines walk correctly.

## Hashes and reproduction (executed)

- All five frozen md5s match the brief: patch 79e7e66e…, battery 649c6819…, races 23de6644…, mutations 8bad2a3c…, r1-to-r2.diff 0e91aa15…. The brief's own md5 (30a0fc2a…) matches `review-brief-27-r2.md5`. The live copies are identical to the frozen ones.
- Clone `rv27opus`: `CREATE DATABASE … TEMPLATE tally`, then TEMP revoked from PUBLIC, tally_app and tally_core. The frozen patch was strict-applied twice (`search_path=`, `check_function_bodies=on`). The first run returned rc=0. The second was skipped by its marker ("already applied"), rc=0.
- `battery-27-frozen-r2.sql`: 116 PASS, no FAIL.
- `shortfall-27-frozen-r2.sh rv27opus`: 16 PASS (SR1–SR9).
- `battery-23.sql` on a fresh clone with -27 r2 applied: 409 PASS.
- I did not run the mutations or ci.sh. The clone was dropped afterwards, and was re-cloned fresh once after the races, since they commit rows.

Probes: each one is the battery's helper prelude and fixtures (lines 1–140), then the probe, in one transaction ending in ROLLBACK. The probe files are in my scratchpad, not the repo.

---

## r1 findings

| r1 | What it was | r2 |
|---|---|---|
| B1 | The return check started at the latest row's date, so earlier dates went unchecked | **Fixed** (executed: battery C1–C3, C6, C7). The check now starts at the first repayment's date, and an undo counts at the date of the row it undoes. A new hole opens through the same retroactive reading; see B1 below. |
| B2 | A repayment from an escheated credit could never be undone (the escheat trap) | **Fixed** (executed: E3–E14, and my P3, P4, P5). Ryan's carry is implemented. |
| S1 | A bounced deposit was admitted as a target | **Fixed** (T1, M36). |
| S2 | A refund was refused as a target only by accident | **Fixed** (T2, M37; its own message). |
| S3 | Test gaps | **Fixed**, except the invoice-application undo, which the brief leaves out on purpose. I agree with leaving it out. `enforce_invoice_application` calls `check_cash_source(…, 'undo')` (tu.sql:45937–45938), the same call U2/M15 cover for the donation undo. SR9 is the family-credit refund race, and M16c/M16d are the target cap's family and arrival-entry legs. |
| N6 | The invariant was narrower than its claim | **Fixed.** The core's SELECT is required, and its REFERENCES and TRIGGER are refused, each asked alone. |

---

## B1 (executed). A future-dated undo lets the returned refund through while the ended payment holds the money until the undo's date; nothing can repair it

r2's return check reads an undo "from the date of the row it undoes" (`check_shortfall_repaid`, `p_from IS NULL`: `coalesce(u.applied_on, s.applied_on)`). Nothing bounds the undo's own date from above. `check_cash_source` skips the date test for `undo`/`shortfall_undo`, and `enforce_shortfall_application` only requires the undo to be dated on or after the row it undoes. The positions read the undo at its own date (residual R5). So the interval R5 accepts, "between a repayment and the undo that corrects it", is chosen by the operator, and it can run arbitrarily far ahead.

Probe P1. Payment P pays 50 (03-10), is refunded 30 (03-11) and bounces (03-12), leaving 30 short. Goodwill credit G (30) repays the 30, dated 03-13. The refund check comes back (nsf row dated 03-20). Then, as tally_app:

```sql
SELECT pg_temp.sa(k('69'), C6, k('60'), NULL, k('65'), -30, DATE '2099-12-31', 'undo', k('67'));
UPDATE payments SET status='nsf', nsf_date=DATE '2026-03-20', status_cause_id=k('68') WHERE id=k('62');
-- NOTICE: P1 ADMITTED: undo dated 2099-12-31 and the refund's return
```

| date | P remaining/repaid | G remaining (at 12-31) |
|---|---|---|
| 2026-03-12 | 0.00/0 | |
| 2026-03-13 … 2099-12-30 | **30.00/30.00** | 0.00 |
| 2099-12-31 | 0.00/0.00 | |

- **The ended payment holds 30 on every date the readers will use.** This is r1 B1's state (Ryan's option 1 not enforced), for decades instead of days. The table comment's claim, "from the first repayment's date on, the target and its overpayment family never hold money", is broken for all practical dates.
- **The customer's 30 is locked.** G reads 0 until 2099, and every draw cap is cumulative from the row's date, so G cannot be applied or refunded before then.
- **Nothing can correct it.** An undo is never undone. G's repayment is already undone in full (undos ≤ the row). The table is add-only. A new repayment to P is refused at any date before 2099 (P1b: 0.01 dated 2026-04-01, refused, "holding 30.01"). A typo such as 2062 for 2026 is enough to cause it. The same holds for any date past the return: dated 2026-12-31, the payment reads money and the credit is frozen for nine months.
- With the carry, a future-dated undo on an escheated credit also forces the carry to the same future date or later (E5's rule). The new credit then does not exist until that date.

**Fix (cheap, either one):**
1. An undo of a shortfall application is dated no later than the day it is recorded: `applied_on <= current_date` in the tenant's zone, the zone the freeze uses.
2. Keep any date, but in the return check (`p_from IS NULL`) also read every row at its own date from today on. Then R5 stays in the past, bounded by the day the return is recorded, which is what section 9 describes ("dated today").

I recommend option 2: it changes only the check that needs it. Add P1 as a battery check, plus a mutation that removes the new bound.

---

## S1 (executed). A carry may name an undo that gave nothing to the escheated credit, so the lineage records the wrong event

`enforce_shortfall_reissue` checks three things: the named row is an undo of a credit's repayment, the credit is escheated now, and the size. It does not check that the undo came after the escheat. An undo recorded while the credit was still active leaves its money on an active credit, and the escheat then remits it, so there is never anything of that undo's to carry. Its id can still be used as the label for other money.

Probe P2. G2 (40) refunds 10. G2 repays 20 of P2's shortfall (03-13), and that is undone (03-14) while G2 is active. G2's 30 is escheated. Then G2's refund check comes back, and -23 says that money goes into a `refund_reissue` naming the refund. Instead:

```sql
INSERT INTO customer_credits (…, origin_type, original_amount, issued_date, reissues_shortfall_application_id)
VALUES (…, 'shortfall_reissue', 10, DATE '2026-03-16', k('7a'));   -- 7a: the old undo
SET CONSTRAINTS ALL IMMEDIATE;
-- NOTICE: P2 ADMITTED
-- refund_reissue for the refund exists: f; G2 0.00, new credit 10.00
```

The money comes out right, because both commit checks read the same remainder. But the record now says "an undo of a repayment gave this back after the escheat", which is false. The returned refund has no reissue, and none can now be made: its size would be least(10, 0) = 0. The core, an auditor or a state escheat report reading the lineage would trace the money to the wrong event.

**Fix:** require the undo to be recorded at or after the credit's move to escheated (`v_undo.created_at >= c.status_recorded_at`). It is exact: an undo recorded before the escheat never leaves anything to carry, because the escheat must remit it. (Predicted: -23's `refund_reissue` has the mirror gap, a refund that came back before the escheat being used to name later money. It is worth the same one-line check, as a -23 residual if not here.)

## S2 (executed; tests). Rules the patch keeps but nothing tests

Each of these I ran as a probe and the patch holds. But no battery check or mutation names them, so a later edit could drop them unseen:

- A carry naming an undo of a credit that is **not escheated** is refused (P6: "…its credit is active"). No battery check, no mutation. This is the guard against carrying money out of a credit that was never escheated.
- A carry naming an undo whose source is a **payment** is refused (by "its source is a payment"; not probed separately).
- The carry's **line-depth bound** (`reissue_generation + 1 > reissue_line_bound()`).
- The **carry leg in `cash_source_draws`**. No mutation removes it. Its readers (the escheated credit's cap and recorded order) would likely still pass E7–E14 without it.
- **Mixed lines**, which the plan listed and the battery does not have. I ran both (P3): a `refund_reissue` of a `shortfall_reissue` (root correct, generation 2, in the family, 10 left), and a `shortfall_reissue` of that `refund_reissue` (generation 3, in the family, 5 left). A later bounce of the root payment took its 5 back from the youngest credit, and the shares were 35/5, consistent with K-10. Worth adding as battery checks, since the line walks were re-issued for exactly this.
- **An escheated credit's plain undo** (an invoice-application or donation undo) is still refused (P5b: `check_cash_source(…, 'undo')` on the escheated credit raises 23514). The plan listed it; the battery does not have it.
- **Applying the carry to a bill** (plan: "applied to a bill: admitted"). E9 refunds it instead. That is acceptable, but the label in the plan is not met.

---

## Notes

- **N1 (executed). The five re-issued functions add only.** I diffed `prosrc`, `proconfig`, volatility, ACL and result type against `tally` for `reissue_generation`, `overpayment_root`, `overpayment_family`, `customer_credit_position_as_of` and `cash_drawn_at`. Settings, volatility, ACL and result type are identical. The bodies differ only by the shortfall_reissue branch. In the two upward walks the inner `JOIN payments` became `LEFT JOIN payments` + `LEFT JOIN shortfall_applications` + `coalesce(r.refunds_customer_credit_id, s.customer_credit_id)`. That is equivalent for every refund_reissue row, because a refund_reissue's refund always names a credit (`enforce_cash_draw`). The depth bound is kept in all three walks.
- **N2 (executed). Plan pins hold for the new branches.** EXPLAIN under the pins (sequential scans, hash and merge joins off): the downward branch uses `idx_shortfall_apps_credit`, then the partial unique index `customer_credits_one_per_shortfall_undo` (the join clause proves its predicate). The upward walk uses the shortfall_applications key index. No sequential scan.
- **N3 (executed). The carry's size and the two-undo case.** Two undos (20 and 10) on one escheated credit: one carry of 30 naming the first is refused (it carries at most what that undo gave back, 20); carrying only the first fails the commit check ("gives 10.00 back"); a carry of 20 plus a carry of 10 is admitted (P4). The size is -23 r9's form exactly: own remainder with this credit counted, plus its amount, less its own share as recorded.
- **N4 (executed). History load and keys.** An owner-inserted carry stamped an hour early is refused 23514 by the recorded-order leg (P5a). Its message names "before the credit was issued", not the undo, because the credit's own insert is the later instant; the refusal is right. A carry that also names a `source_payment_id` is refused by -23's `customer_credits_payment_overpayment_check` (P5c).
- **N5 (read). "Never voided" is right.** Its money would go back to a credit that is escheated by construction, which -23's rule (void only back to an active credit) already refuses. An undo made by mistake is corrected by applying the new credit again, so nothing needs the void. The voided-reissue legs left out of `cash_lineage_recorded` and `check_cash_order` are then dead for this origin. So is the ledger guard's leg for rows under a credit_issued entry, since this origin has none. I found no other -23 reader of `refund_reissue` that needs the branch. I grepped every `refund_reissue`/`reissues_refund_id` reader in tu.sql after line 43000: the ledger guard's credit_issued refusal (replaced by `enforce_shortfall_reissue_rows`), the give-back guard at 43369 (needs a credit_issued root), the void legs at 45020/45088 (void refused), and the fixed-column list at 44923 (the new column is fixed by its own trigger).
- **N6 (read). Lock order.** An undo takes the close head, the target, then the source's root payment, then the credit. The carry takes the root payment, then the credit, which the transaction already holds. The commit check reads under the locks the undo still holds (advisory xact locks). Nothing is inverted beyond the stated cross-family deadlock (40P01, retried). An escheat racing an undo on the same credit serialises on the credit's lock. If the escheat wins, the undo sees the escheat and needs a carry at commit; the app retries with one. There is no race test for this, but I predict it holds.
- **N7 (read). The carry may be dated after the undo**, as -23 allows for a refund_reissue. Between the two dates the escheated credit reads the money. That is consistent with -23 and bounded once B1 is fixed, but dating the carry on the undo's own date would be cleaner. The battery already writes it that way.
- **N8 (read). The retroactive and strict readings.** Without future dating they agree from the latest row's date on, and the retroactive reading is never looser than the strict one: moving an undo earlier only lowers what was repaid. So a new repayment dated today is never refused by an older R5 interval, and a return is always settled by undoing repayments, now including from an escheated credit. B1 is the one case where the two disagree in a way that traps the operator.
- **N9. Residuals R1–R5.** R1–R4 are unchanged and none blocks. R5 is acceptable as written ("the operator's undo, dated when it is recorded") only once B1's fix makes that true.
