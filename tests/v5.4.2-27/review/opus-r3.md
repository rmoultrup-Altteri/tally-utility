# Opus review: v5.4.2-27 r3 (shortfall applications)

**Verdict: not yet.** One blocking finding, executed. r3 fixes r2's B1 only when the undo and the refund's return are checked together. An undo dated after today, recorded on its own before the refund comes back, is still admitted. After that the bank's return of the refund cannot be recorded until the undo's date, and nothing in the database can make room for it. The customer's credit also reads 0 until that date, as in r2. -23 already settled the same question for ledger reversals: a reversal is dated no later than today (R-02, tu.sql:43165–43172). An undo of a shortfall application should keep to the same rule, with the corrected row's own date allowed when that is later. Everything else in r3 holds. My r2 S1 is fixed, the born-active check holds, the mixed lines are right, and the battery, races and -23's battery reproduce.

## Hashes and reproduction (executed)

- All five frozen md5s match the brief: patch 135242ab…, battery f44547c8…, races 939b0cbb…, mutations 2e325488…, r2-to-r3.diff d5840202…. The brief's own md5 (8b093403…) matches `review-brief-27-r3.md5`.
- Clone `rv27opus`: `CREATE DATABASE … TEMPLATE tally`, then TEMP revoked from PUBLIC, tally_app and tally_core. I applied the frozen r3 patch strictly (`search_path=`, `check_function_bodies=on`) twice. The first run returned rc=0. The second was skipped by its marker ("already applied"), rc=0.
- `battery-27-frozen-r3.sql`: 135 PASS, no FAIL.
- `battery-23.sql` with -27 r3 applied: 409 PASS, rc=0.
- `shortfall-27-frozen-r3.sh rv27opus`: 16 PASS (SR1–SR9), rc=0. I ran it last, on a fresh clone.
- I did not run the mutations or ci.sh. The clone was re-made twice: after my two-session race, which commits rows, and before the races. It was dropped at the end. No role was touched.

Probes: each one is the battery's helper prelude and fixtures (lines 1–143), plus a `pg_temp.try` helper that prints ADMITTED or REFUSED with the SQLSTATE and message, then the probe, in one transaction ending in ROLLBACK. The race was two psql sessions on committed fixtures. The probe files are in my scratchpad, not the repo.

---

## r2 findings

| r2 | What it was | r3 |
|---|---|---|
| B1 | An undo dated in the future let a returned refund through, while the ended payment read the money until the undo's date | **Half fixed** (executed: battery R1, R1b, R2, R2b; my P2). It is fixed when the undo and the return are checked together. It is still open when the undo is recorded first: see B1 below. |
| S1 | A carry could name an undo recorded while the credit was active, as a label for other money | **Fixed** (executed: E15; my race R). `status_recorded_at` is the right stamp; see N2. |
| S2 | Rules kept but not tested | **Fixed.** S3c (not escheated), K9e (payment source), E17 (depth bound, with M61), E7d (carry leg, with M63), E16–E18d (mixed lines both ways), E19/E19b (ordinary undos of an escheated credit, the bill one through the bill writer). The carry is still refunded rather than applied to a bill. That was acceptable in r2 and still is. |
| N7 | The carry may be dated after the undo | Unchanged. It is consistent with -23, and the battery dates it on the undo's day. |

---

## B1 (executed). An undo dated after today, recorded before the refund comes back, makes the return unrecordable until that date

The r3 plan says "a future-dated undo is refused". The patch does not refuse it. It adds a second reading to `check_shortfall_repaid(…, NULL)`, which a move giving money back runs. The undo itself runs it too (`check_cash_source`, purpose `shortfall_undo`). But while the refund is still out, a repayment and its future undo hold nothing on any date, so the undo is admitted. The second reading only bites later, at the return, and by then the undo cannot be taken back.

Probe P1. P pays 50 (03-10), is refunded 30 (03-11) and bounces (03-12), leaving 30 short. Goodwill credit G (30) repays it, dated 03-13. Then, as tally_app:

```
P1a undo dated 2099-12-31 while the refund is still out            ADMITTED
    P at 2026-12-31: 0.00/30.00; G: 0.00
P1b the refund check comes back (status nsf)
    REFUSED 23514 … on 2026-11-07 … would leave it … holding 30.00 … dated no later than today
P1c … with the return dated today                                     REFUSED 23514 (same)
P1d a second undo of the same row, dated today, for 0.01
    REFUSED 23514 … its undos would come to 30.01, more than its 30.00
```

- **The bank's return cannot be recorded until 2099.** The return is a fact; the app has to write it. Every way out is closed. An undo is never undone. The repayment is already undone in full. A new repayment only adds to what P holds. Voided and reversed take the same check as nsf.
- **The customer's 30 stays locked until 2099.** G reads 0 at every date before then (P1a). This half of r2's B1 does not depend on the refund at all. A mistaken repayment undone with a typo date (2062 for 2026) freezes the credit for decades.
- The same thing happens on a smaller scale with a repayment dated in the future. Repay on 12-01, undo dated 12-05 while the refund is still out, and the return is refused until 12-05 (P2c is the same-transaction version of this).

**-23 already has the rule.** `enforce_ledger_reversal` (tu.sql:43165–43172, -23 r2 Opus S2) refuses a ledger reversal dated after `CURRENT_DATE`: "an undo is of something that happened, dated no later than today". My probe P6 tried a donation undo dated 2099 under -23 and it was refused with that message. So the plan's reason for not choosing option 1, "-23 never limits a money date to today", does not hold for undos. -23 limits exactly this act. (-23's bill-application undo has no such limit. That gap is -23's, but it does not reach -27: see the note on E19 below.)

**Fix.** In `enforce_shortfall_application`, for an undo: `applied_on <= greatest(<today>, the undone row's applied_on)`. Here `<today>` is r3's UTC+14 date, or `CURRENT_DATE` to match R-02 exactly. The second term keeps P2d working: an undo of a future-dated repayment, dated on that repayment's own date. With this rule the two readings agree from today on, so the second reading becomes redundant. It can stay as a second guard. Tests to add: an undo dated 2099 recorded alone is refused; an undo dated today + 1 is refused; an undo of a 12-01 repayment dated 12-01 is admitted, and one dated 12-02 is refused. Each needs a mutation.

---

## What I checked and found holding

### The two readings (executed: P2, P2e; read)

- **No sequence I found leaves the family holding money outside R5's interval before today.** Both readings agree at every date on or after the latest row's date. At a date d on or after today, the only difference is an undo dated after d whose row is dated on or before d. The second reading counts that exactly as the positions do. Before today, the difference is R5's interval by definition.
- **The second reading never traps a correction made in one transaction.** With the repayment dated before today, an undo dated today settles it (R2; my P2e, with a partial undo of the earlier of two rows dated today and the later one undone on its own date: admitted). With a repayment dated in the future (P2a, 12-01, admitted), the return alone is refused (P2b), an undo dated 12-02 is refused (P2c), and an undo dated 12-01, the row's own date, is admitted (P2d). Afterwards P reads 0.00/0.00 and G 30.00. The only trap is the cross-transaction order in B1.
- P2e's strict positions: P reads 20.00/20.00 at the server's 11-06 and 0.00/0.00 at 11-07 (the UTC+14 date). This is R5 as amended, at most one local day ahead.
- `SELECT v_from, 0` (M58) is right. Without it, with nothing dated between today and the undo, the second reading would see no date to test.

### "Today" at UTC+14 (read)

- It is the right bound for the stated aim: an undo dated today in the utility's own zone is never refused. It mirrors -22's close (UTC-12, tu.sql:41660).
- Nothing tighter is available without a zone. The schema has no tenant zone, only a premise's zone (`premise_time_zone_as_of`), and a payment or credit has no premise. A tighter bound would need a tenant zone, which is a separate decision. -23's R-02 uses `CURRENT_DATE`, the server's zone, for the same kind of act. The two disagree by up to a day. That is harmless, but worth one line in R5. If B1's fix uses `CURRENT_DATE`, an operator west of the server cannot date an undo with their own today during the hours when the server is already a day ahead. UTC+14 avoids that. I would keep UTC+14 and note the difference.

### The born-active check (read; executed by E6c, E6d)

- The check is placed before every read of the row and refuses for every role, as it should.
- **No way around it.** A carry born active ends only through `enforce_customer_credit_immutable`, which fires for every role (ENABLE ALWAYS). Its moves are active → escheated or voided, both terminal. Escheated needs its escheatment event and nothing left (tu.sql:44960–44975). Voided is refused by -27's own trigger. `reissues_shortfall_application_id` cannot be set by an UPDATE after birth (r2 N5).
- **Multi-row inserts and writable CTEs work** (executed, P5). Two carries of 20 in one INSERT, for undos of 20 and 10, were refused 23514 by the size rule. A carry of 10 and a carry of 20 in one writable-CTE statement were admitted and then checked at commit. Afterwards the credit read 0 and the two carries 10 and 20.

### The recorded-after-escheat check (executed: race R; read)

- **The race is covered by -23.** Session A began (17:11:49.89) and slept. Session B undid G's 20 repayment on the still-active G and committed (17:11:51.46). Session A then inserted G's escheatment event and was refused 40001 by `check_cash_order`: "a row drawing on it is recorded at …49.89, before …e9 (recorded at …51.46) already counted … retry it". So an escheat cannot end up stamped before an undo it saw. The retry stamps a later `status_recorded_at`, after the undo.
- **A history load cannot get around it.** A superuser's chosen `status_recorded_at` on the move to escheated is refused if it falls before `cash_lineage_recorded` (tu.sql:45098–45105). That function covers `cash_source_draws('credit', …)`, which lists the credit's shortfall applications and undos. So a chosen escheat time cannot be placed before an undo already recorded, and it cannot be in the future (tu.sql:44937–44942).
- `status_recorded_at` is better than `escheated_at`. The app writes `escheated_at` (write-once only), and PATCH-LESSONS' "app-written logs are not guards" applies. I agree with the author's choice.

### The mixed-line fixture (read; executed as battery)

- It follows probe 08 and my r2 P3. OQ → KQ (shortfall_reissue, generation 1) → R (refund_reissue, generation 2) → K3 (shortfall_reissue, generation 3). E16 and E18b check the root (OQ), the generation, family membership and what each holds. E18d checks that Q's bounce reaches K3.
- E18d checks only that K3 reads 0. In r2 I also read the shares (35/5). A check that the shares sum to Q's take-back, and that none goes negative, would make the claim "reaches the third" exact (N4).
- E17's bound is replaced inside the check's own subtransaction, so the replacement rolls back with it. The message match proves the depth check fired, not some other check.

### E19 instead of the caller-level bill undo (read)

- I agree it cannot be reached. A bounced payment's applications, and its overpayment credit's and reissues', must net to 0 before the bounce (-23). After the bounce no new application from the family is possible. A credit outside the family (goodwill) has no payment behind it, so the check returns early for it.

### `cash_drawn_at`'s two terms (executed: P3, P4; read)

- I could not build an instant where either term is not 0. A give-back under a bounced payment's entry is refused by -23 (P3: "gives money back to payment …, which has ended", 23001). The move to reversed requires that nothing is left under the posting entry (P4a). So once the payment has ended, nothing more is taken back under it, and a repayment needs the payment ended. The source term reads 0 at a take-back's instant by R15. Dropping both mutations is justified, and the comment says why.

### -23's properties, concurrency, invariants

- Caps, cover, shares and recorded order are unchanged by the second reading. It is a read under the lock the first reading already holds (the payment's), and it takes no new lock. -23's battery gives 409/409.
- Lock order is unchanged from r2. The second reading reads nothing new and reads it under the same lock. `v_today` is the transaction's start, so a transaction that crosses midnight reads at most one day early. That is in the strict direction, since it refuses more, never less.
- Claims against checks: the table comment and the header now name R5's interval "dated no later than today". With B1 open, the comment's claim is true while its check covers less than the claim. An undo can still be dated later; it simply cannot settle a return. The invariant (`assert_shortfall_guard_invariants`) checks objects, not bodies, and the battery and mutations cover the bodies.

---

## S1 (read; tests). Two tests worth adding with B1's fix

- The opposite side of E15: an undo recorded in a later transaction than the escheat is admitted. Today only E7 covers it, where both happen in one transaction and the times are equal. Running it through the race script would cover the strict-greater case.
- B1's own regressions, listed under its fix.

## Notes

- **N1.** R5's text should name the zone difference with -23's R-02 (server date against UTC+14) whichever way B1 is fixed.
- **N2.** I agree with `status_recorded_at` over `escheated_at` (see above). Nothing to change.
- **N3.** P2b's message comes from the first reading, so it does not carry r3's "dated no later than today" suffix. That is right: the return alone fails before any undo exists.
- **N4.** E18d could check the shares (that they sum to the take-back and none is negative), not only K3's 0.
- **N5. Residuals R1–R4** are unchanged and none blocks. **R5 as amended** is acceptable once B1's fix makes "dated no later than today" true for every undo, not only for one checked together with a return.
- **Housekeeping.** Two `crystaldba/postgres-mcp` containers were running on this host when I started (the CLAUDE.md check). I left them alone.
