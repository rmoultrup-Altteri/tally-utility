# Opus review: v5.4.2-23 r9

**Date:** 2026-11-04. **Reviewer:** Opus. **Verdict: ready.**

r9 closes everything round 8 raised, for all three reviewers. The new rule on money leaving a family covers every move I could find that changes what a credit held when a take-back was recorded. I ran three versions of my round-8 J against it with real sessions:
- the refund's return (CR27);
- a donation's undo, which the existing recorded-order rule already orders;
- a two-reissue void that would otherwise leave an escheated reissue holding money.

All three are refused for retry. The family-cap skip lets nothing leave the family. agree() now pins each line's figure: my mA and mB fail it. I have no blocking item.

One should-fix (tests only, S1): CR28 does not show what the void leg protects. In CR28's shape the void is refused anyway. I ran a shape where the void leg matters: without it, an escheated reissue ends holding 10.

## Setup

- **Frozen files.** All six md5s match the brief (executed).
- **Clone.** `rv23opus` from `tally` (TEMPLATE); TEMP revoked from PUBLIC, tally_app and tally_core right after; both read `f` (executed). Rebuilt once the same way after the race script's committed rows.
- **Strict apply, twice.** Clean; the second skipped, "already applied" (executed).
- **Battery.** 409 PASS, no FAIL, rolled back, 63 s after `VACUUM payments, customer_credits, account_ledger` (executed).
- **Races.** `cash-23-frozen-r9.sh rv23opus`: 47 PASS, rc 0, 100 s; CR27, CR27a, CR27b, CR28, CR28a, CR28b pass (executed).
- **Probes.** The files are in my session scratchpad, not the repo:
  - three real-session races on the race script's committed tenant (V, V-mut, D);
  - three mutated copies of `check_cash_source`, each created inside the battery's own rolled-back transaction (mA, mB, mC);
  - one mutated `enforce_customer_credit_immutable` (the void leg off), on my clone only, restored afterwards; the clone was then dropped.
- **Not run.** `ci.sh` and `mutations-23.py`, per the brief. I read N227–N233 and the `ci.sh` vacuum (line 127).
- **Cleanup.** The clone is dropped and my files are removed from the container (executed). `docker ps` shows 2 `crystaldba/postgres-mcp` containers. I did not touch them.

Each claim is marked **executed** (run on the clone) or **predicted** (read from the code).

---

## Round-8 findings, item by item

| Round-8 finding | Status |
|---|---|
| **Codex B1.** A required reissue is refused while the family is over its payment. | **Closed.** U1b admits the reissue of 20 against a family reading 110 of 100. U1d and U1e refuse a cent out of R and out of the payment afterwards. U1f's agree() passes (executed). See "The skip" below. |
| **Opus B1 (J).** A refund's return stamped before a take-back moves the take-back's share off an escheated reissue. | **Closed.** CR27 refuses the return with 40001. The retry is admitted, and R ends escheated holding 0 of its own (executed). The void leg is also needed, and it works: probe V (executed). |
| **Opus B2 = Fable S1.** agree() does not pin each line's payable figure. | **Closed.** mA now fails at Y0d and mB at Y7j (executed; the runner anchors N232/N233 there too). A third mutation of mine also fails, at W2a: mC, the payment's cap ignoring the family's shares, so the cap is too low (executed). I checked the payment's cap formula in agree() against the cap's own arithmetic; they agree, including with a voided overpayment credit and with a payment that is not posted (predicted). |
| **Opus S1.** One statement that makes a reissue and draws on it is sized against the reissue's own draws. | **Closed.** In U2/U2a, one statement with a reissue of 20 and a refund of 5 is admitted; 15 plus 5 is refused (executed). |
| **Opus S2.** The pins do not make depth independent of the statistics. | **Closed.** `tests/ci.sh` vacuums the three tables right before each battery (read, line 127). R21 now states the measured figures and withdraws the claim (read). The extra pin was tried and dropped. That is fine: the vacuum is the fix that holds. |
| **Opus S3.** Comments. | **Closed.** `enforce_customer_credit_immutable`'s COMMENT names the escheat move's payment lock (r8, Opus S1). R17 is rewritten: "retried, not stamped back" (read). |
| **Fable S2 (P-G).** | **Closed.** U3–U3f: the reissue of 30 (the covered position) is refused, and 40 (R1's own) is admitted (executed). |
| **Codex S1 (Z6's label, a full-history control).** | **Closed.** Z6's preamble now says it plants its history. Z7 builds a 20-deep line through every guard, flushes the checks after each generation, and admits a refund of the 20th (executed: PASS). |
| **Codex S2 (the header's exact-cap sentence).** | **Closed.** It is marked as withdrawn by option A (read). |
| **Fable N1–N3, Codex N1–N5, Opus N1–N6.** | Unchanged and still fair. Nothing in r9 touches the lock order among single acts (see "Concurrency"). |

## Rulings

- **K-10.** Applied. What was paid out stands. With the family over its payment, nothing more leaves it (U1d, U1e; executed).
- **Kyle, 2026-10-30.** Applied within one payment, as in r8 (predicted, unchanged code).
- **Ryan, 2026-10-21 ("nothing comes back to an escheated credit").** Now holds on every path I tried:
  - J (CR27);
  - its donation-undo variant (D);
  - its two-reissue void variant (V).

  All executed, all refused for retry.
- **Option A (Ryan, 2026-11-01).** Applied: a position is an attribution, and agree() pins what each line pays.
- **Ryan, 2026-11-04 (option 1).** Applied as decided: the family cap is skipped for `reissue` and `overpayment_credit` only, and every other check on them stays (read). N227 and N228 guard both edges of the skip.

---

## What I probed

### The leaving order (brief: "is every move that changes the shares covered?")

`overpayment_shares` reads, at each take-back's instant, what each credit held (`cash_drawn_at`), whether each credit existed and when it was voided, and what the payment's own part held. So a share can move after the fact only through a row or move stamped before a take-back already recorded. I went through every one (predicted, from the code):

| What changes what a line held at an instant | Ordered by | Executed |
|---|---|---|
| A new draw (an application, a refund, a reissue, a donation, a remittance, an overpayment credit) | `check_cash_source` → `check_cash_order` with the payment's posting entry (since r4/r6) | — |
| An application's undo | the same (purpose `undo` still runs `check_cash_order`) | — |
| A donation's undo (a ledger row under the donation) | the same (`enforce_ledger_reversal` calls `check_cash_source` with `undo`) | **D: 40001** |
| A refund of the payment or a family credit leaving (voided, nsf, reversed) | **r9** `check_cash_leaving_order` | CR27: 40001 |
| A family credit's void | **r9** `check_cash_leaving_order` | **V: 40001** |
| An escheat move (the status) | changes no holding; reads the own side under the payment's lock | — |

- **D (executed, real sessions, tally_app, READ COMMITTED).** This is J with K's donation of 20 undone in place of a refund's return.
  - T begins. S takes back 10 (falling on R), then remits R's 5 and escheats R.
  - T's undo is refused: 40001, "recorded … before … was recorded under its arrival entry".
  - R ends escheated, with 0 of its own.
- **Is the check under the lock every take-back takes?** Yes (predicted).
  - A take-back takes the posting tree's lock, then the payment's lock (`enforce_ledger_reversal`).
  - Every leaving move takes the payment's lock before the check: a payment's refund through `refunds_payment_id`; a credit's refund through `overpayment_root`; an overpayment credit's void through `source_payment_id`; a reissue's void through its root.
  - The check is STABLE, but it is called from a volatile trigger at READ COMMITTED, so it reads a snapshot taken after the lock. Both status triggers refuse any other isolation level.
- **Can it make a legitimate act unrecordable?** No (predicted).
  - A tally_app move is stamped `now()`, so a refusal is 40001, and the retry is stamped after every committed row.
  - 23514 is only for a superuser's chosen stamp. That is the same history-load rule the draws already follow.
  - Rows of one transaction share one stamp, so a transaction that takes back and then records a return is not refused.
- **Only for a payment with a live overpayment credit.** Right (predicted).
  - With no live credit there are no shares to move, and the payment's cap reads the take-backs whole.
  - A credit made after the return's stamp is a draw on the payment, so it is itself ordered after the return.

### The skip (brief: "can money leave beyond what the family holds?")

- **No (executed for U1; predicted in general).** Money leaves a family only through a refund, an application, a donation or a remittance. All four still run the family cap. The skip changes only the two moves the family sum leaves out. Since neither adds to the sum, the cap could only refuse them for an over-state that already existed.
- **Is `overpayment_credit` needed in the skip?** No, but it does no harm (predicted).
  - In the overpayment credit's AFTER trigger, the new credit is the payment's live credit, so the family cap does run on it.
  - But the payment's own cap on that same row counts the credit's amount, which the family sum leaves out. So the payment's own cap always refuses first.
  - Only `reissue` was needed. Keeping both matches the sum's own exclusions.
- **What the skip leaves:** a reissue carrying money that nothing can pay out while the family stays over (U1c/U1d). R24 already covers that money, and -27 closes it.

### The reissue size (brief: "can its share at insert ever be non-zero?")

- **Only within one instant (predicted).**
  - A reissue is ordered after every row under the posting entry (its draw runs `check_cash_order` with that entry). A take-back recorded before it gives it nothing, because `v_at` is later than the take-back.
  - The one exception: a take-back and the reissue in the same transaction, stamped at the same `now()`. Then the reissue counts as holding at the take-back's instant and can take a share before its own size check fires.
  - The header's one-act-per-transaction rule covers this. Note N1.

### Concurrency and roles

- **Locks.** r9 adds no lock. It adds reads under locks the moves already take, so it adds no lock-order cycle (predicted).
- **Isolation.** Every new read is behind the READ COMMITTED guards of the two status triggers (read).
- **Roles.**
  - `check_cash_leaving_order` is granted to tally_app only.
  - tally_core has SELECT only on the five cash tables (executed, from the catalog), so no tally_core write reaches the function.
  - There are no role memberships under `tally%` (executed).

---

## Blocking

None.

## Should fix

### S1. Tests only: no test shows what the void leg protects (executed)

**What happens.**
- CR28 voids the only reissue, R, after a take-back has fallen on R. r7's share rule refuses that void anyway, at its early stamp. The brief says so: on r8 it was 23001.
- So N230 (the void leg removed) is caught only because the refusal's code changes from 40001 to 23001. The money comes out the same either way.
- Nothing in the suite shows a void the old rules would admit and the new leg must refuse.

**V (executed, real sessions, tally_app, READ COMMITTED).**
- Setup:
  - payment 100;
  - K 50, with the payment's own 50 refunded;
  - K's refund B1 of 15 came back and was carried to R1;
  - K's refund B2 of 10 came back and was carried to R2;
  - K refunds its last 25.
- Reads: payment 0, K 0, R1 15, R2 10.

| Step | Frozen r9 | The void leg off (N230) |
|---|---|---|
| A begins (its stamp t0), to void R2 | | |
| B takes back 10: K holds nothing, so it falls on R1 (share 10 on R1) | R1 5 | R1 5 |
| B remits R1's 5 and escheats it (own side 0) | admitted | admitted |
| A voids R2 at t0 and commits | **40001**, "credit …'s void is recorded … before … was recorded under the payment's posting entry" | **admitted** |
| End | R1 escheated, own 0; share on R1 | **R1 escheated, own 10**; the share moved to K |

- Under the mutation, R2's money goes back to K at t0. K therefore held 10 when the take-back was recorded, and the share moves off R1.
- R2 carried no share, so r7's rule admits its void.
- The escheated R1 ends holding 10 of the customer's money: J's end state, reached through a void.

**Fix.** Add V as CR28c (or replace CR28's shape with it), and anchor N230 there. Keep CR28 as written: it shows the retry comes before the share refusal.

## Notes

- **N1 (predicted). The reissue's share at its own insert.** It is 0, except when a take-back and the reissue are in one transaction. The two then share a stamp, and the reissue can take part of the take-back before its size check. That is a multi-act transaction, which the header's rule already rules out. No test is needed. One sentence in R17 or the size check's comment would make the limit explicit.
- **N2 (predicted). Retries on a busy family.** A long transaction carrying many returns (an ACH return file) is retried whenever a take-back on any of its payments commits meanwhile. Take-backs are rare, so this is fine. The app's retry loop should treat 40001 from `check_cash_leaving_order` like every other 40001 in -23.
- **N3 (executed). mC.** The payment's cap ignoring its family's shares is caught at W2a. Together with mA and mB, every leg of both per-side caps now has a mutation agree() or a W check sees.
- **N4. Residuals.**
  - R17 now says what is true, and J's three variants are refused (executed).
  - R21 is corrected.
  - R22, R23, R24 and option A are as in round 8: fair.
  - The skip's stranded money (U1c) is R24's.
  - R1–R16, R18–R20 are unchanged.
  - None is blocking.
- **N5. AC-44.** Unchanged since r8, and consistent with r9. The skip adds no new money state for the core: the core reads the money a reissue carries while the family is over exactly as R24's.

## Probe record (executed)

- **Battery** 409/409 in 63 s. **Races** 47 PASS in 100 s.
- **mA:** first failure Y0d ("a refund of 0.01 got admitted" where the payment can pay 0). **mB:** first failure Y7j (the same, for a credit). **mC:** first failure W2a (the payment's 40 refused: "would come to 70.00").
- **D:** setup 0/0/15. After S: share 10 on R, R escheated, own 0. T's undo: 40001 from `check_cash_order` ("under its arrival entry"). End: R escheated, own 0.
- **V on r9:** setup 0/0/15/10. After the take-back: share 10 on R1. After the escheat: R1 escheated, own 0. A's void: 40001 from `check_cash_leaving_order`. End: R1 own 0.
- **V with the void leg off:** the same until A, whose void is admitted. End: R1 escheated, own 10; shares "K 10".
