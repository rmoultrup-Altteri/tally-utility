# Fable review: v5.4.2-23 r2 — cash

**Date:** 2026-10-18. **Frozen hashes:** all six match the brief (executed, `md5 -r`).
**Clone:** `rv23fable` from `tally`, TEMP revoked from PUBLIC, tally_app, tally_core; frozen r2 strict-applied twice (`search_path=''`, `check_function_bodies=on`): first run clean, second skipped by the marker (executed). Dropped at the end.
**Reproduced (executed):** `battery-23-frozen-r2.sql` 168 PASS, rolled back. `cash-23-frozen-r2.sh rv23fable` 18 PASS. Mutation runner not run (brief).

Every claim below is marked **executed** (on the clone, as tally_app under `app.user_id` unless noted, in a transaction ended by ROLLBACK; the PR10 race committed into the clone) or **predicted**. Probe files: scratchpad `probes2.sql`, `probes3.sql`, `probes4.sql`, `race-f.sh`.

## Verdict: not yet

Three blocking items. Two of them live in one clause, the bounce-row guard's "except the payment's own refunds" exemption, which keys on a caller-chosen reference rather than on the act; the third is that the behaviour the header, the r2 plan and the brief describe for K2 "as it stands" is not what the patch does. None of the three is reached by any battery row, race or mutation: no test in -19, -21, -22 or -23 posts a refund on the ledger at all (executed: `grep` over every battery and race; zero `refund`-type ledger rows), so the refund-kind posting row, X1's `refund` entry, and both exemption clauses (`cash_arrival_stands`, `enforce_ledger_reversal`) have no coverage, and "110/110" says nothing about them.

## Round-1 findings

| r1 | Status | Evidence |
|---|---|---|
| B1 credit draws by label | **closed** | `customer_credits_payment_overpayment_check`; draw/trigger/approval key on `source_payment_id`; R6, N79 (executed R6). |
| B2 source read before its lock | **closed** | `check_cash_source` locks, then reads and judges; CR9/CR9b, N104. Residual: recorded order is measured against the source's `created_at`, not its posting (S4, executed race). |
| B3 refund outstanding at nsf | **not closed as stated** | Header/plan/brief say the bounce is "refused until the refund is voided (now)". Executed: admitted (B3 below); -19's own P5c fixture depends on the admission. |
| S1 voided overpayment credit still draws | **closed** | R7–R7d, N81. |
| S2 refund then bounce | **held for Kyle (K1)** | reviewed as it stands in K1-A below. |
| S3 births | **closed** | `enforce_cash_birth`, default pending; R1–R1d, N72/N73. |
| S4 `refunded` naming a voided refund | **closed** | R8e, N84. |
| S5 fail-open on unknown source | **closed** | `NOT FOUND` raises in `check_cash_source`. |
| S6 tests weaker than claimed | **partly** | credit refund leg (R10–R10d), rate item (LC3), restricted target (R14), reversed/voided/donated/escheated moves (R4b, R4c, R11c, R12f), multi-row and CTE (R15, R15b) are there. COPY is not, and cannot be: `COPY FROM` is refused for tally_app on an RLS table (executed, `COPY FROM not supported with row-level security`), so the plan's item 7 overstates; harmless. The refund posting row is untested anywhere (see verdict). |
| S7 any type names an entry | **closed** | `account_ledger_reversal_types_only_check`; R5, N77. |
| N2 refund status read live (R2) | **closed** | `status_recorded_at`; R17, N96; the fixed-coordinates caveat is in each reader's comment. |
| N3 lock order stated | **closed** | header "Lock order and isolation". |
| N5 tally_core lock-key grant | **closed** | revoked. |
| N9 invariants narrower than name | **partly** | default, policy and `check_cash_source` grants are pinned; three facts the new guards rest on are still pinned nowhere (S6). |
| N11 future-dated reversal | **closed** | R5b, N78. |

## Blocking

### B1. The bounce-row guard's exemption keys on the reference, not the act: any row referencing a refund of the payment undoes the payment's money while it is applied, and the payment keeps giving money (executed)

`enforce_ledger_reversal` exempts a row from the guard when `NEW.reference_type IN ('payment','refund')` and `NEW.reference_id` is a payment with `refunds_payment_id = v_src` — whatever the row's type or amount. `cash_arrival_stands` exempts the same rows and their subtrees. So:

```
PA posted 100; 99.99 applied (60 + 39.99); refund R of PA for -0.01 (pending)
PR1a control: adjustment +99.99 naming PA's entry, no reference      -> refused 23001 (the guard works)
PR1b the same row, reference_type 'payment', reference_id = R          -> ADMITTED
PR1c after it: cash_arrival_stands(PA) = true, ledger_entry_remaining(entry) = -0.01, position remaining = 0.00
```
and without even changing the type:
```
PB posted 100; 60 applied; refund R of PB for -0.01
PR1d refund row +100 (type refund, reference R) naming PB's entry       -> ADMITTED; ledger remaining 0.00; arrival stands = true
PR1f 39.99 more applied from PB                                        -> ADMITTED
```
PB has nothing on the ledger and 99.99 applied to bills. This is the exact hole Opus B2 O2/O6 was closed for, reopened by the exemption. Nothing in the mutation set touches the clause (grep: no mutation of `refunds_payment_id = v_src`).

**Fix (under K1 as it stands):** exempt exactly the refund's posting row — `NEW.transaction_type = 'refund'`, `NEW.amount = -R.amount`, R `refunds_payment_id = v_src`, and no other `refund` row already references R — and, for the refund's own later bounce, a row whose parent chain passes through such a row (the set `cash_arrival_stands` already computes). Apply the same definition in both places. **Under K1-A the exemption disappears and so does B1** (see K1-A).

### B2. A refund of an overpayment credit can never be posted on the ledger (executed)

An overpayment credit has no `credit_issued` entry (r2), so its refund's posting row (type `refund`, which must name an entry) names the payment's posting entry. That row is not exempt (the refund names the credit, not the payment), and the guard then requires no applications and **no live overpayment credit** — but the credit it refunds is one:

```
PC posted 100; approval 40; KC overpayment 40; 60 applied; refund of KC -40 (PR2a admitted: the draw is fine)
PR2b its posting row +40 naming PC's entry   -> refused 23001 (applied 60 / held as a credit)
PR2c KC moves to refunded                    -> admitted
PR2d the posting row again                   -> refused 23001 (c.status <> 'voided' still true)
PD posted 50, nothing applied; KD 50; refund -50
PR2e the posting row naming PD's entry       -> refused 23001
PR2f so the refund cannot move to posted     -> refused 23503 (no row of its kind)
```
A legitimate act with no lawful record. Under K1-B the exemption must also cover refunds of the payment's overpayment credits (`R.refunds_customer_credit_id = C AND C.source_payment_id = v_src`), with B1's tightening. Under K1-A it vanishes.

### B3. K2 "as it stands" is not implemented: the bounce is admitted with the refund pending (executed)

Header, r2 plan and brief: "A payment with a refund still pending moving to nsf or reversed: refused until the refund is voided (now)". The nsf/reversed/voided guard checks applications and overpayment credits only (patch lines 1441–1449).

```
PE posted 50; refund R -30 pending (no ledger row)
PR3a nsf +50 naming PE's entry   -> ADMITTED      PR3b PE -> nsf   -> ADMITTED      PR3c PE nsf, R pending
PR3d R's posting row (+30)       -> refused (X2 cap: 80 of 50)     PR3e R -> posted -> refused
```
The refund can never post, so money does not leave the ledger; but the record is the opposite of what the header says, R is stranded pending until someone voids it, and `payment_position_as_of(PE)` reads refunded 30, remaining 20 on a bounced payment. The -19 battery's P-2/P-4/P5c sequence (older-tests diff, hunk @@ -367) is exactly this: a pending refund, then the nsf row, then the move — admitted. Kyle is being asked to choose between "refused first" and "auto-void" on the premise that "refused" is current behaviour; it is not. Either add "no refund of this payment pending" to the nsf/reversed guard (then -19 P5c voids P-4 first), or correct the header, plan and Kyle brief before his answer is applied.

## Should fix

### S1. A refund is posted by a row naming another payment's entry (executed)
The `posted` cause for a refund kind checks type, reference and amount, not what the row names. PF and PG posted 10 each; PF's refund row (+10) names PG's entry: PR4a admitted, PR4b the refund of PF posted by it. After: `cash_arrival_stands(PF) = true` (its money is out), `cash_arrival_stands(PG) = false` (nothing drew on it), PF position remaining 0, PG 10. Under K1-B require `l.reverses_ledger_entry_id = <refunded payment>.status_cause_id`; under K1-A require it names nothing.

### S2. A credit with two `credit_issued` rows is voided by reversing the stray one (executed; the brief asks)
KE goodwill 100 with `credit_issued` −100 and −1: PR5a stands = true; reverse the −1 (+1); PR5b void naming that reversal admitted while −100 stays on the ledger. The void's cause should reverse an entry at −`original_amount` (or every `credit_issued` entry of the credit must be left with nothing), and `cash_arrival_stands` should require exactly one.

### S3. A refund that fails after its payment is marked refunded has no exit (executed)
PI 20 posted; refund R −20 posted (row naming PI's entry); PI → refunded. The refund check bounces: PR7a nsf −20 naming R's row admitted (exempt); PR7b R → nsf refused ("the payment it returns is refunded"); PR7c a replacement refund of PI refused (`refund` needs posted). End state: PI refunded, its posting entry has −20 left on the ledger, position remaining 0, R posted forever with a bounce under it. The r2 guard (Opus B3) is right not to end R under a refunded source; what is missing is the lawful sequence. Options: `refund` purpose admits a `refunded` source while a draw on it has ended (the cap still holds), with R's nsf allowed once the replacement draws; or `refunded` is derived, not a move. Interacts with K2.

### S4. A draw can be recorded before its source was posted (executed, two sessions)
A begins (now() = t0), B posts P (status_recorded_at t1 > t0) and holds the source lock, A applies and waits, B commits, A is admitted: `application.created_at < payments.status_recorded_at` (race-f.sh: `application before posting = true`). The recorded-order rule compares against the source's `created_at`; for a payment the floor should be the posting move's `status_recorded_at` (a credit is born active, so `created_at` suffices). A position at R in [t0, t1) shows money applied from a payment that was pending at R.

### S5. A donation or escheat on another customer's account is a draw on the credit (executed)
PR8a a `donation` row on C2's account referencing C1's credit KF: admitted; PR8b an `escheated_to_state` event with `customer_id` C2 for KF: admitted; KF's position remaining 0. `escheatment_events.customer_credit_id` is a plain FK (not tenant/customer); the donation branch never compares `NEW.customer_id` with the credit's. Make the escheat FK `(customer_credit_id, tenant_id, customer_id)` and check the donation row's customer.

### S6. Three facts the new guards rest on are pinned by no invariant (executed)
With each removed in turn, `assert_cash_guard_invariants()`, `assert_wave1_guard_invariants()` and `assert_periods_guard_invariants()` all pass (PR14a–g; the control, disabling `enforce_cash_draw`, is caught): `payments_refund_is_refund_check` (the draw set counts `-r.amount`; a positive "refund" would be a negative draw), `customer_credits_original_amount_check` (`v_amount > 0` for credits, the cap's ceiling), and `a_stamp_created_at` on `escheatment_events` (the escheat draw's recorded instant; the cash list pins the table's `append_only` but not its stamp). Add all three to the cash list.

### S7. A payment's own status is not part of its position (executed)
`payment_position_as_of` reads applications, credits and refunds at R but never the payment's status at R: PK (nsf) reads refunded 30, remaining 20 (PR13d, PR19). A reader summing `remaining` across payments counts bounced money. Either filter by the payment's status at R (`status_recorded_at` makes this possible now) or say in the comment that the caller must.

### S8. The refund posting path is untested (executed grep)
No battery, race or mutation anywhere posts a refund on the ledger (`post()` never names an entry for a refund kind, so it cannot be used for one). Add: a refund's posting row naming its payment's entry; the posted move by it; the exemption (B1's negative and positive cases, B2); a refund's own bounce under it.

## Notes

- **N1.** The lock order has no cycle I can construct: every writer takes head → (tree | tariff) → source → line; a status move takes its row, its own source, then (a refund ending) the refunded source; a reversal takes tree then source; nothing takes a source before a tree. Two-source and two-line statements in opposite orders deadlock and are retried, as stated (predicted).
- **N2.** `cash_arrival_stands` for a credit is false forever once any row is under its `credit_issued` entry, even after that row is itself reversed back (a +4 then −4); the credit is dead though the ledger nets to full (predicted). Edge; state it or net the tree.
- **N3.** Multi-row UPDATE moving P to refunded and its refund to voided in one statement is refused in either row order (executed, PR6a/PR6b) — the BEFORE-row reads see the earlier row's write.
- **N4.** `tally` is a superuser (executed), so the owner's history loads keep their own `created_at`, `status_recorded_at` and births as the comments say; tally_app cannot.
- **N5.** Residuals R1–R11: none blocking. R8's changes each follow a -23 rule; -19 P7d moving P-4c to P-1 is forced by the cap, P9e's flip is R-05; the P5c sequence is B3's premise.
- **N6.** The `escheat` and `credit_applied` ledger types are not draws and nothing ties them to a credit; an app writing them double-counts on the ledger without touching a position (app discipline; outside the guards).
- **N7.** The void never reaches `check_cash_source` or `cash_source_lock_key` (its root is a charge), so tally_void's missing EXECUTE on them is right (predicted from the guard's branch conditions).

## K1-A (not counted against the patch as it stands)

**As it stands (executed, PR13):** PK 50 posted; refund 30 posted under its entry; the bank returns 50: nsf +50 refused (80 of 50); nsf +20 admitted and PK moves to nsf. Record: −50 +30 +20 = 0 — the customer owes nothing while the utility is out 30; position says refunded 30, remaining 20. This is the brief's case, exactly.

**If Kyle answers A ("its own movement"):**
- Patch: drop `refund` from both X1 CHECKs (`_reversal_types_name_check`, `_reversal_types_only_check`); a refund's posting row names nothing and becomes a root. Drop the exemption from `cash_arrival_stands` and from the bounce-row guard: **B1 and B2 vanish with it**, S1 becomes "a refund-kind posting row names nothing", S3's PR7a bounce row then names the refund's own root (a `refund` type, so no source check) and is unaffected. The refund's draw cap is already in `cash_source_draws`; X2 stops applying to refunds. The `posted` cause for a refund kind is unchanged. PR13: nsf +50 admitted, record −50 +30 +50 = +30 owed.
- Tests: the two CHECK strings in `assert_cash_guard_invariants`; mutations N77 (and any that edit the type lists); no battery or race row changes, because none posts a refund on the ledger (S8) — which is also why that gap must be filled under either answer. -19 and -21 are unaffected (their refunds are never posted).
- Unchanged under either answer: a posted refund stands at the bounce; the refund's own nsf names the refund's posting row.

**K2:** under "cancel first", add "no pending refund of this payment" to the nsf/reversed/voided guard (B3) and have -19 P5c void P-4 first. Under "auto-void", the move must void the refund inside the trigger; that void then passes the r2 "source refunded" check (the source is moving to nsf, not refunded) — fine, but say in the header that a status move writes a second row.

## Probe record
Fixtures: the battery's own (tenants …23a1/a2, C1/C2, bills I1–I3 with lines 60/40/−10, `post()`), plus bill I5 and payments PA–PK as named above. PR10's race used its own tenant `…fa01` and committed into the clone only. The clone was dropped after this file was written.
