# Fable review: v5.4.2-23 r3 — cash (Kyle's K-10, refunded/donated derived)

**Date:** 2026-10-21. **Frozen hashes:** all six match the brief (executed, `md5 -r`).
**Clone:** `rv23fable` from `tally`, TEMP revoked from PUBLIC, tally_app, tally_core; frozen r3 strict-applied twice (`search_path=''`, `check_function_bodies=on`): first run clean, second skipped by the marker (executed). A second scratch clone `rv23fable2` was made the same way for one measurement (the candidate fix under the whole battery) and dropped at once. Both clones dropped at the end.
**Reproduced (executed):** `battery-23-frozen-r3.sql` 216 PASS, rolled back. `cash-23-frozen-r3.sh rv23fable` 26 PASS (CR1–CR17; it commits its fixtures, so the battery was run before it). Mutation runner not run (brief). Not read: `opus-r3.md`, `codex-r3.md`.

Every claim is marked **executed** (on the clone, as tally_app under `app.user_id` unless noted, in a transaction ended by ROLLBACK, on the battery's own fixture plus a customer CF of T1 with an empty ledger) or **predicted** (from the code). Probe files in my scratchpad: `probes1.sql`, `probes2.sql`, `fix.sql`, `battery-fix.sql`.

## Verdict: not yet

One blocking item. The bounce of a payment whose overpayment credit has already paid money out (a refund posted from the credit, or a donation) has no lawful record: the bounce row and the nsf/reversed move both refuse while the credit is not voided, and the credit cannot be voided while refunded or donated. This is Kyle's example routed through the standard overpayment path, and nothing in the battery, races or mutations reaches it (every overpayment-credit bounce test voids an unused credit first). Everything else r3 claims, it does: the round-2 findings are closed below, K-10 and the status decision are applied faithfully, and the new guards hold under every shape I tried.

## Round-2 findings

| r2 finding | Status | Evidence |
|---|---|---|
| Opus B1 / Codex B2 (root label): posting row under `reference_type = 'refund'` escapes the bounce guard | **closed** | arrival-row check requires `reference_type = 'payment'`, kind, amount, account (S6b–S6d2, N115–N118); executed P5d: a refund row under label `refund` refused. |
| Opus B2 / Codex B2 / Fable B1: the refund exemption keyed on `reference_id` | **closed** | the exemption is gone (K-10 A): no row under a posting entry is exempt; `cash_arrival_entry` has no subtree skip. Executed S4a: a +1 adjustment under the posting entry refused while a refund is pending. |
| Opus B3 / Codex B1 / Fable B3: K2 not implemented; -19 P5c relied on admission | **closed** | the bounce-row guard refuses while a refund of the payment is `pending` (S4, CR15/CR15b, N112); the move needs that row, and the cap refuses a refund inserted between the row and the move (predicted: S4-shaped, draws + tree > amount). -19 now cancels P-4 before P-2's nsf row (older-tests diff, hunk @@ -367). |
| Opus B4: a refunded payment's refund undone on the ledger while both statuses stand | **closed by the status decision** | `refunded` is gone; a refund's posting row undone counts until the refund moves (R12, stated); the move to nsf/reversed frees the money (executed P2e/P2f: refunded 30 → 0). |
| Opus B5 / Codex B4 / Fable B2: a credit's refund cannot post (or posts under another entry) | **closed** | a refund row names nothing (X1, S5b) and is its own arrival entry (S7, S7c for an overpayment credit; executed P9a–P9c for a credit refund that then bounces). |
| Opus S1 / Codex B3 / Fable S2: one arrival entry per source | **closed** | unique indexes, pinned (S6, S6e, N113/N114); the row checked at its write. |
| Opus S2 / Fable S8: refund posting untested | **closed** | S1, S7, S7c post refunds; S1b–S1e Kyle's example; R8f–R8h a refund's own bounce. |
| Opus N1: posted by an entry already undone | **closed** | `cardinality(ledger_tree_ids) = 0` (S13, N133). |
| Opus N2: R17's tally_app leg | **open by design** (two transactions); CR13b covers the ordering. |
| Opus N3, N4: reader comments; one act per transaction | **closed** | comments on both bill readers; header "Lock order". |
| Codex B5: a donation's undo | **closed** | draws and the position read the donation's tree (S9, S9b, N131/N132). |
| Codex B6: escheat remittance and the freeze | **closed** | `enforce_escheat_freeze`, head FOR SHARE before the credit's lock, by UTC day; pinned (S11, N124/N125). |
| Codex B7: voiding an overpayment credit returns money to an ended payment | **closed by the status decision, partly by lock** | `refunded` is gone, so the void returns money to a `posted` payment; the void takes the payment's lock (CR17, N129). See B1 for the opposite direction. |
| Codex S1: claims broader than tests; CR11 label | **closed** | CR11's emitted label corrected; the S section fills the refund gap. |
| Codex S2 / Fable S6: invariants narrower than claimed | **closed** | refund sign (ledger and payments), `original_amount > 0`, the escheat stamp and freeze, tally_app's EXECUTE, "one policy only" are pinned (N111, N135–N139). Executed: the frozen battery's I1 passes; the five pins are in `c_constraints` / the catalog checks. |
| Codex S3: design doc | **closed by statement** (r3 plan: "Corrections made in review"); not re-read here. |
| Fable S1: a refund posted by a row naming another payment's entry | **closed** | the posted cause requires `reference_id = NEW.id` and the row names nothing (K-10 A). |
| Fable S3: a refund that fails after its source is `refunded` has no exit | **closed** | no `refunded`; R8e–R8h, executed P2e–P2f and P9a–P9c. |
| Fable S4: a draw recorded before its source was posted | **closed** | `greatest(created_at, status_recorded_at)` and the arrival entry's `created_at` (S12, S12b, CR14, N126/N127). |
| Fable S5: a donation or escheat on another customer's account | **closed** | donation customer check, composite FK on `escheatment_events` (S10, S10b, N122/N123). |
| Fable S7: the position ignores the payment's own status | **closed** | `received` reads the arrival entry's tree (S1e, N130); executed P2a: an nsf payment reads received 0. Note N1 below on a pending payment. |
| Fable N2: a credit dead once anything is under its entry | **closed** | the cap is an amount (S8, S8b). |

## Blocking

### B1. A payment held as an overpayment credit that has already paid money out cannot bounce, and the credit cannot be voided: the bank's return has no lawful record (executed)

The bounce-row guard (patch line 653) and the nsf/reversed move (line 1582) refuse while any overpayment credit of the payment is not `voided`; the credit's void (line 1710) refuses while anything is drawn on it, and a posted refund, a donation or an escheat is a draw that no undo removes. So:

```
F-O 60 posted; approval 60; credit KO (overpayment) 60; refund of KO -60 pending
P10a  void KO while its refund is pending      -> refused 23001 (right: K2 through the credit)
P10b  nsf +60 on F-O while KO lives            -> refused 23001 (right)
      the refund of KO posts (+60 under its own row; the money went out)
P10d  nsf +60 on F-O                           -> REFUSED 23001 "held as a credit"
P10e  void KO                                  -> REFUSED 23001 "60.00 of it is drawn on (refunded)"
F-D 60 posted; credit KD 60; donation 60 of KD
B1-D1 nsf +60 on F-D                           -> REFUSED;  B1-D2 void KD -> REFUSED (donated)
F-E 60 posted; credit KE 60; 20 applied from KE then undone; 40 refunded (posted)
B1-E1 nsf +60 on F-E                           -> REFUSED;  B1-E2 void KE -> REFUSED (40 refunded)
```

Under K-10 the $60 bounce goes through and the customer owes what was paid out; here the only way to record the bank's return is to mark the real refund as bounced (false) or never record the return (the ledger shows 60 received that the bank took back). The `refund_automatically` tenants may refund the payment directly, but `hold_as_credit` then a refund from the credit is the standard path (-21: "an overpayment built from several payments is refunded from its credit"), and a partial refund (B1-E) is the common case. Nothing reaches it: R7–R7d void an unused credit; CR17 voids an unused credit; no mutation touches the credit leg of either guard with a refunded or donated credit (the "test every branch" rule).

**Fix, measured (executed on the clone, `fix.sql`):** the credit leg of both guards becomes "the bounce waits while an overpayment credit of the payment is applied, has a refund pending, or still holds money (its amount less its draws ≠ 0)"; what the credit already paid out (posted refunds, donations, escheat) stands, as a posted refund of the payment does. The guard takes each credit's lock before reading its draws (payment, then credit), and the credit's void takes the payment's lock before its own, so the order is one way (payment → credit) and CR17's protection is kept. With that: FIX-D1/D2 the donated case bounces and moves to nsf; FIX-E1 refused while KE has 20 left; FIX-E2 refused while the 20 is a pending refund of the credit; FIX-E3/E4 admitted once both refunds are posted; after it KE reads issued 60, refunded 60, remaining 0, F-E reads received 0, credited 60, remaining −60 (the customer owes 60, Kyle's shape), and an application from KE is refused by the cap (FIX-E7). The whole frozen battery passes 216/216 with the fix in place (fresh clone `rv23fable2`). Needed with it: an S check for each of the three shapes, the mutation of each leg, a race (a draw on the credit against the bounce, both orders), and the header's lock order (payment before its overpayment credit). An alternative is to let the bounce through with money left on the credit and make every draw on an overpayment credit require its payment `posted` under the payment's lock, with `issued` reading the payment's standing; it changes more and I did not measure it.

## Should fix

### S1. An arrival row is admitted for a source that has ended (executed)

`enforce_ledger_reversal`'s arrival-row check reads the payment's identity, not its status. P1a: payment F-P1 moved pending → voided (no ledger row, as the move requires), then a posting row for it: **admitted**. The customer's balance is credited 50 for a payment the record says never arrived; `payment_position_as_of` reads received 50, remaining 50 on a voided payment (P1b/P1c). No draw is possible (P1d, status), and an adjustment under the row can take it back, but nothing flags it. The same shape for credits is closed by the unique index (every ended credit has its entry) except the never-issued credit (S3). Refuse a posting row for a payment that is not pending or posted (posted: a superuser's history load born posted). The rows the readers do not tie to a source at all (P5a a `refund` row referencing a customer credit, P5b a `payment` row with no reference, P5c a `payment` row referencing a payment under `invoice`) are admitted and move the customer's balance with no position behind them; app discipline today (r2 N6), but a one-line rule — a `payment`, `deposit`, `refund` or `credit_issued` row names its source under its own label — would close them all; check the earlier batteries post no such rows first.

### S2. A row giving money back is refused while the source is drawn on or has a refund pending (executed)

The payment branch of the bounce-row guard refuses every row under the posting entry, whichever way the money goes. P4: posting −40, adjustment +5 (keyed 40, got 35), a refund of 10 pending, then an adjustment −5 under the +5 (the 5 was there after all): refused "cancel the refund first". P3: the same +5 while 20 is applied: refused "undo its applications first" (this one is R15's rule for payments and is right; the header's R15 names credits only). Key the guard on the act: a row that takes money away (`NEW.amount > 0` under a payment's entry, `> 0` under a credit's) waits; a row that gives it back does not.

### S3. A credit never issued on the ledger has no exit (executed)

P21: a goodwill credit keyed in error before its `credit_issued` row: void refused (the cause must reverse a `credit_issued` entry), escheat and refund refused (no entry). It stays `active` for good unless the operator issues it on the ledger and withdraws it in the same breath. A payment keyed in error is voided from pending with no cause; a credit has no pending. Either let a credit with no `credit_issued` entry void naming nothing (with S1's rule, so none arrives afterwards), or say in the header that the exit is issue-then-withdraw.

### S4. The tests do not reach the credit leg of the bounce guards (executed grep)

Every bounce of a payment with an overpayment credit voids an unused credit first (R7, R7d, CR17). Add B1's three shapes, positive and negative, and a mutation of each leg (both guards); today a mutation deleting the credit leg entirely is caught by R7d only through the void path.

## Notes

- **N1.** `payment_position_as_of` reads `received` from the posting row whether or not the payment has moved to posted: P7, a pending payment with its row in, reads received 40, remaining 40; the comment says "nothing while pending". True only when the row and the move are one transaction. Say so, or filter by the status at the instant (`status_recorded_at` allows it).
- **N2.** A re-reversal under an nsf row on an nsf payment is admitted (P2c: −50 under the +50; received 50 again, status nsf, no draw possible, P2d). The lawful record of a reinstated check is a replacement payment (`nsf_original_payment_id`); the header could say the terminal statuses are not re-opened by the ledger.
- **N3.** A refund payment has a position of its own (P2a2: amount −30, received −30, remaining −30); harmless, nothing reads it; a reader summing `remaining` across payments must exclude refunds.
- **N4.** By-date netting in the cap is right where I expected it to be over-strict: P26, a refund dated before a later undo of an application is refused at the earlier date because the application still stood then.
- **N5.** Lock order has no cycle I can construct in the frozen patch (predicted): draws take head → source; reversals head → tree → source; a leaving refund its own lock → its source; an overpayment credit's void credit → payment; nothing takes payment → credit. B1's fix adds payment → credit in the bounce, so the void must be reordered as measured, or the two deadlock (40P01, retried) under load.
- **N6.** K2 at the move is covered by the cap rather than by a check (a refund inserted after the nsf row is refused as draws + tree > amount), so the move's guard need not repeat it; worth one sentence in the comment at line 1580.
- **N7.** Residuals R12–R15: none blocking. R12 (an undone refund row counts until the move) is the right call under the status decision; executed P2e2 shows the window. R15 applies to payments as well (P3).
- **N8.** Status vocabularies: `grep` over `sql/tu.sql` and every `sql/v5.4.2-*.sql` finds `refunded`/`donated` only in deposits (-15, their own `refunded`), the escheat event type, and the -01/-21 bodies -23 replaces by CREATE OR REPLACE; no index, view or policy keys on either (executed grep).
- **N9.** `tally` is a superuser (executed), so a history load keeps its stamps and births as the comments say; tally_core holds EXECUTE on the readers and the draw set only, no lock key (predicted from the grants).

## Probe record

Fixture: the battery's own (lines 1–200: tenants …23a1/a2, C1/C2, bills I1–I3, tariff …23ab, P61–P65, K71) plus customer CF (…23cf) of T1 with bill IF (…f706). Probe ids f7xx. Every probe ran as tally_app under op1, in one transaction, rolled back; the race script committed its own fixtures into `rv23fable` (which is why the battery was run first and the fix measured on a fresh `rv23fable2`). Both clones dropped after this file was written.
