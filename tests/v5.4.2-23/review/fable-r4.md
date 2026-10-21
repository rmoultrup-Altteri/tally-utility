# Fable review: v5.4.2-23 r4 — cash (round 3's findings, the overpayment credit's bounce, refund_reissue)

**Date:** 2026-10-21. **Frozen hashes:** all six match the brief (executed, `md5 -r`); `older-tests-23-frozen-r4.diff` is byte-identical to r3's (executed, `cmp`).
**Clone:** `rv23fable` from `tally`, TEMP revoked from PUBLIC, tally_app, tally_core (checked: `has_database_privilege` false for both); frozen r4 strict-applied twice (`search_path=''`, `check_function_bodies=on`): first run clean, second skipped by the marker (executed). Dropped at the end.
**Reproduced (executed):** `battery-23-frozen-r4.sql` 252 PASS, rolled back. `cash-23-frozen-r4.sh rv23fable` 29 PASS (CR1–CR19; it commits its fixtures, so the battery and probes A–H ran before it). Mutation runner not run (brief). Not read: `opus-r4.md`, `codex-r4.md`.

Every claim is marked **executed** (on the clone, as tally_app under `app.user_id` unless noted, on the battery's fixture plus a customer CF of T1 with an empty ledger and a bill IF; one transaction ended by ROLLBACK, except the two-session probe, which commits into the clone) or **predicted** (from the code). Probe files in my scratchpad: `probes1.sql` (the frozen battery minus its ROLLBACK, then probes A–H), `rr.sh` (two sessions).

## Verdict: not yet

r4 closes every round-3 finding it claims (table below), applies K-10, the status decision and the reissue decision faithfully, and the new guards hold under the shapes the brief lists. Three things it opened or left open are blocking, each a concrete, executed path: (B1) the "take-backs come first out of the credit" reading counts a take-back that predates the credit, so a credit sized correctly at its creation reads and gives less than it holds and the difference can never be used; (B2) a give-back under the payment's posting entry puts money back on an escheated overpayment credit, the one thing Ryan's ruling says never happens; (B3) a posting or credit_issued row written at REPEATABLE READ reads its source's status from a snapshot older than the lock it just took, so a voided payment or credit gets its arrival row anyway (round 3's Opus B2 O4, under another isolation level).

## Round-3 findings

| r3 finding | Status | Evidence |
|---|---|---|
| Fable B1 / Opus B3: a payment held as a credit that paid money out can never bounce | **closed** | bounce guard and move wait only while the credit is applied or has a refund pending (patch 715–726, 1705–1717); V1–V3b executed; my partial case (V2, 40 of 60 refunded): ledger +40 owed, payment 0/0/0/0, credit issued 0, refunded 40, remaining −40 — the readers agree (probe H, executed). Not my measured fix ("wait until the credit holds nothing"); the author's reason (the partial case) is right. See B1 for what the new reading gets wrong. |
| Opus B1 / Codex B2: an escheated credit gets money back (donation undo, pending refund cancelled, posted refund returned) | **closed for the three named paths; a fourth is open** | V5 (undo refused), V6 (escheat waits on a pending refund), V7–V7i (reissue) executed. B2 below: a give-back under the payment's posting entry. |
| Opus B2 / Fable S1: an arrival row for an ended source | **closed at READ COMMITTED, open at REPEATABLE READ** | V9/V9b, CR19 executed; B3 below. |
| Codex B1: a donation's correction skips the cap | **closed** | patch 752–755; V8 executed. |
| Codex B3: a draw dated before the arrival entry | **closed** | the `-infinity` row (patch 2342–2345); V10/V10a/V10b executed. The author's reason for not dating the entry the payment's date (ACH) is right. |
| Opus S1: recorded order under the arrival entry | **closed** | patch 2308–2321; V14 executed. |
| Codex S1 / Fable N4: an old permitted deficit vetoes a later draw | **closed** | `x.on_date >= p_on` (patch 2349); V11 executed. |
| Fable S2: a give-back row held up | **closed** (and the give-back is now the subject of B2) | patch 702–707, 735–740; V12 executed; R15 names payments. |
| Fable S3: a credit never issued has no exit | **closed** | patch 1818; V13/V13b executed. |
| Fable S4: the credit leg of the bounce guards untested | **closed** | V1–V3b, V16, CR18/CR18b, N141–N148. |
| Fable N1 (received while pending), N2 (re-reversal under an nsf row), N3, N5–N9 | **N1 stated in the reader's comment; N2 not taken — it is now B3-adjacent (S1 below); the rest noted** | |
| Opus N2 (two-transaction R17) | **open by design**, as before. |

## Rulings

- **K-10 through the credit (1 = A, 2):** a posted refund from the credit stands at the bounce; a pending one blocks it; the cap refuses a draw after the bounce (V2b). Faithful.
- **Ryan, statuses:** unchanged from r3. Faithful.
- **Ryan, reissue (option 1):** a refund of an escheated credit that comes back is carried, in the same transaction, into a `refund_reissue` credit naming it, for exactly its amount, posting no ledger row, drawing on the credit, not voided back (V7a–V7f). The commit-time check is reachable only by never moving the refund (R12, stated; the money then sits undone on the ledger and counted as refunded — see N3). A superuser can disable the trigger; by design. Faithful. Two things the ruling did not decide, both admitted (probe F, executed): a reissue while the credit is still **active** (the money moves from one credit to another, net unchanged), and its void back onto that active credit. Harmless; say so in the header or refuse the first.

## Blocking

### B1. A take-back dated before the credit is taken from the credit again: the money it was sized for cannot be used (executed, probe A)

`customer_credit_position_as_of`, the escheat check and `check_cash_source` read an overpayment credit's standing as its amount less **everything** taken back under its payment's posting entry (patch 1403–1407, 1855–1857, 2242 with 2338–2339). But the credit's creation was already capped by the payment's take-backs (`check_cash_source('payment', …, 'overpayment_credit')` nets the tree), so a take-back recorded before the credit was already netted out when the credit was sized, and is now subtracted twice.

```
F-A 100 posted; +30 under its posting entry (keyed 100, got 70): admitted (A1)
approval 70; credit KA (overpayment) 70: admitted (A2; the cap: 70 + 30 = 100)
KA position: issued 40, remaining 40            (A3)   customer's ledger balance −70 (A5)
F-A position: received 70, credited 40, remaining 30 (A4)
apply 41 of KA: refused (R-06 cap)              (A6)   apply 40: admitted (A7)
apply 1 of F-A itself: refused (R-06 cap)       (A8)   (its "remaining 30" is KA's 70 + the 30 again)
refund 30 from KA: refused; remit 30: refused   (A9, A10); KA then reads 40/40/0
```

The customer holds 70 by the ledger; 40 can be applied, refunded or remitted, and 30 can never be touched from either side. A keyed-amount correction before holding the rest as a credit is ordinary. The same reading makes the escheat check wrong for such a credit (predicted: KA could be escheated after remitting 40, with 30 still the customer's).

**Fix:** only take-backs that come after the credit come out of it. The recorded instant is the right key, not the date: the credit's own recorded-order leg (patch 2308–2321, the arrival tree) guarantees every tree row at its creation is recorded before it, and a later take-back takes the credit's lock after the payment's (patch 715–716), so `l.created_at > c.created_at` separates the two sets exactly (a take-back whose transaction began before the credit's and wrote after it is refused by the tree leg when it carries a chosen time, and retried at 40001 otherwise — check that the bounce row's `created_at = now()` is indeed later than the credit's in the CR18b order, or key on `created_at >= c.created_at` and accept the tie). Apply the same predicate in the three readers and in the cap's tree set for `v_origin = 'overpayment'`. Tests: this shape, positive (40 applied, then 30 refunded, then nothing) and the position reading 70; a mutation dropping the predicate (caught by the refund of 30).

### B2. A give-back under the payment's posting entry puts money back on an escheated overpayment credit (executed, probe B)

"Nothing is given back to a source that has ended" checks the **payment's** status (patch 703): pending or posted. The money of an overpayment credit is the payment's, so a give-back under the payment's entry is a give-back to the credit, and the credit's status is not read.

```
F-B 60 posted; credit KB 60; +20 under the posting entry (partial return): admitted (B1; KB issued 40)
remit 40 to the state (B2), KB escheated (B3): admitted (nothing left)
−20 under the +20 ("not returned after all"), F-B still posted: ADMITTED (B4)
KB: escheated, issued 60, given_up 40, remaining 20      (B5)
F-B: received 60, credited 60, remaining 0               (B6)
apply 20 of KB: refused (escheated); apply 20 of F-B: refused (cap)   (B7, B8)
```

20 is back on an escheated credit, which the ruling says never happens, and stuck. The same shape with a partial bounce in place of the adjustment is the same path.

**Fix:** in the payment's give-back branch, also refuse while the payment's live overpayment credit is not active (`EXISTS (… c.source_payment_id = v_src AND c.status = 'escheated')`), with the credit's lock after the payment's as the take-back branch takes it; the message: void nothing, issue a new credit. Test: this shape; a mutation dropping the leg.

### B3. A posting or credit_issued row written at REPEATABLE READ is admitted for a source voided meanwhile (executed, `rr.sh`)

The arrival-row branch of `enforce_ledger_reversal` (patch 481–531) takes the source's lock and then reads its status — the r4 handshake — but the READ COMMITTED pin (patch 594) is reached only by a reversal. Under REPEATABLE READ the status read after the lock comes from the transaction's snapshot, taken before the void committed.

```
session A: BEGIN ISOLATION LEVEL REPEATABLE READ; reads payment F-RR pending, credit KX active
session B: voids F-RR and KX (autocommit; both take the source locks and commit)
session A: posting row −40 for F-RR, credit_issued −15 for KX: both ADMITTED, COMMIT
after:     payment voided, received 40, remaining 40; credit voided, issued 15, remaining 15;
           the customer's ledger credited 55 for money that never arrived
```

Session A's statements ran after B had committed (no blocking: B's locks were released), so this is not the CR19 race but a plain stale read. Every other guard that reads under a lock pins READ COMMITTED (the status moves, `check_cash_source`, the reversal path); this branch is the one that does not, and the header's "every draw, application, reversal and status move runs at READ COMMITTED" does not cover it. **Fix:** move the isolation check above the arrival-row branch (every row that reads a source under its lock); test: a race leg at RR (refused 25000), and the mutation runner's `APPLY` check on the moved line.

## Should fix

### S1. A refund's returned posting row re-reversed: the refund paid out twice on the ledger, once of it reissued (executed, probe C)

A refund root (`transaction_type = 'refund'`) is outside both source branches (patch 697, 730): no row under a refund's posting entry is checked against the refund's status. KC (100) refunded 30 (posted), 70 remitted, escheated; the refund's check returns (−30 under the +30; refund → nsf); reissue 30: the commit check passes (C1). Then +30 under the −30 ("honoured after all"): **admitted** (C2). The ledger has paid the refund out again (+30 net) while the reissue credit still holds 30 and the refund stays nsf (C3): 30 counted twice. r3 N2 (a re-reversal under an nsf row on an nsf payment) is the same gap; the reissue turns it from an odd record into a double count. Fix: a row taking money out again under a refund's posting entry (`NEW.amount > 0` under a `refund` root) is refused while the refund is not pending or posted (an honoured check after an nsf is a new refund), with the refund's lock.

### S2. R15's text no longer matches the guard

R15 says a payment's posting entry "is still not taken back, even in part, while anything draws on it"; r4's bounce proceeds while the overpayment credit (a draw on the payment, in `cash_source_draws`) holds money. Say "while it is applied, or its credit is applied or has a refund pending".

### S3. The reissue's "either order" comment

Patch 2582–2583 says the move and the new credit "can be written in either order"; `enforce_cash_draw` requires the refund already nsf or reversed when the reissue is inserted (patch 2536), so the move comes first. Correct the comment (or read the refund's status at commit).

## Notes

- **N1 (executed, probe E).** A superuser's history load may be born `posted` (`enforce_cash_birth`), but its posting row is then refused ("which is posted"). The load must insert pending, write the row, then move with a chosen `status_recorded_at`, as V14 does. Say so where the birth rule says a superuser keeps its own status.
- **N2 (predicted).** Lock order: no cycle for one act per transaction. Every path is head → tree → payment → credit (bounce, move to nsf, the credit's void), refund → its source (a leaving refund), from-credit → reissue (its void), tree → credit (donation undo, withdrawal), credit only (a draw on the credit, the arrival row, an escheat after the head). Nothing takes credit → payment. A row that is both a donation and a reversal (admitted by X2 under a negative entry) takes credit → tree and can deadlock with a withdrawal (tree → credit); 40P01, retried, and the row double-counts itself (a draw and a take-back) — over-strict, not unsafe; nobody should write it.
- **N3 (predicted).** Around the reissue: a refund of an escheated credit whose posting row is undone but which is never moved stays counted as refunded (R12) with the money sitting on the ledger: the commit-time check never fires. Stated residual; the app writes both together.
- **N4 (executed, probe D).** `ledger_tree_ids(NULL)` is `{}`, so a reissue credit (no arrival entry) reads an empty tree in the cap and the recorded-order leg, as intended.
- **N5 (predicted).** One live overpayment credit per payment: a second hold from the same payment after the first was partly applied has no path but a direct application or refund of the payment; acceptable under R16, worth a sentence for the app.
- **N6 (predicted).** `credited` in `payment_position_as_of` subtracts the whole take-back from each credit visible at the instant; with one live credit per payment the sum is right, but B1's predicate belongs here too.
- **N7.** Mutations N141–N170 (read, not run): each new leg has one, named at its check; N145/N161 at the races. None reaches B1–B3 or S1 (every V shape has the take-back after the credit, the give-back onto a live source, and runs at READ COMMITTED).
- **N8.** Residuals R1–R16: none blocking. R15 (S2) and R16 are accurate otherwise.

## Probe record

Fixture: the battery's own, plus customer CF (…23cf), location (…23df), bill IF (…2f06) of T1. Probe ids f0xx. Probes A–H as tally_app under op1 in the battery's transaction, rolled back; the RR probe committed its own tenant (…23fe) into the clone. Clone dropped after this file was written.
