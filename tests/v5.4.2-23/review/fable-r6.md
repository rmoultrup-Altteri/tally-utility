# Fable review: v5.4.2-23 r6 — cash (round 5's findings: recorded order for take-backs, the shortfall placed at the reading, the reissue in its payment's lineage)

**Date:** 2026-10-29. **Frozen hashes:** all six match the brief (executed, `md5 -q`).
**Clone:** `rv23fable` from `tally`, TEMP revoked from PUBLIC, tally_app and tally_core (`has_database_privilege` false for both); frozen r6 strict-applied twice (`search_path=''`, `check_function_bodies=on`): first run clean, second skipped by the marker (executed). Dropped at the end.
**Reproduced (executed):** `battery-23-frozen-r6.sql` 344 PASS lines, rolled back (the brief says 343 checks, the plan 344). `cash-23-frozen-r6.sh rv23fable` 38 PASS, exit 0, no other line. Mutation runner not run (brief); N192–N211 read. Not read: `opus-r6.md`, `codex-r6*`.

Every claim is marked **executed** (on the clone: single-transaction probes appended to the frozen battery before its ROLLBACK, as the owner for history loads and as tally_app under `app.user_id` for draws; two-session probes committed into the clone under the race script's tenant …23f0) or **predicted** (from the code). Probe files in my scratchpad: `probe1.sql` (P1, P1c), `rr6.sh` (RR-E), `rrf.sh` (RR-F).

## Verdict: not yet

r6 closes every round-5 finding it claims, for all three reviews (table below), and applies K-10 and Ryan's rulings faithfully. The recorded-order legs, the tree-order split, the write-once status time, the lineage rule and the future-`created_at` refusals are right and tested. The cover at the reading does what the plan asked between the two sides, and agree() is the right invariant: it is what found the one blocking item. That item is the cover's reach: it settles a deficit between the payment and its credits, but not among the credits. A reissue whose refund comes back reads money it cannot give while the overpayment credit it descends from carries a shortfall (B1, executed): the exact shape round 5 blocked on, moved one level down by r6's own family. One should-fix: the as-built decision to take no payment lock on a reissue's void opened a lock cycle against the give-back (S1, executed deadlock).

## Round-5 findings

| r5 finding | Status | Evidence |
|---|---|---|
| Opus B1 / Codex B2: the shortfall fixed at the take-back; a deficit beside money | **closed between the sides; open within the family (B1 below)** | `overpayment_absorbed_as_of` (patch 1812–1875), read by both positions and the escheat check; Y1–Y3a executed (Opus P1 ends 30/0, P2 10/0, Codex B2 0/10). P1 below: the cover does not reach a reissue. |
| Opus B2 / Fable B1: a take-back not ordered against the draws | **closed** | `check_cash_order` (2750–2830) called for the payment and each credit of the family under the payment's lock (809–812); Y5/Y5a (my P7b and RR-B shapes, 23514) and CR23/CR23a–c (40001, clean retry, 30/0 after) executed. |
| Codex B3: one instant split by id | **closed** | `ORDER BY l.created_at, t.depth, l.id` (1778); Y4–Y4d executed, both id orders. |
| Codex B4: a status time moved with the status unchanged | **closed** | write-once for every role (2148–2156, 2318–2326); `cash_lineage_recorded` (2832–2888) under the locks (2263–2272, 2423–2430); Y6–Y6d executed. RR-F below for the app-side variant (a note). |
| Codex B1: a reissue made before the bounce | **closed** | `overpayment_root` / `overpayment_family`; the reissue's draws take the payment's lock (2922–2927) and sit in the pool cap by their own draws (3070–3075); the bounce and the move wait on it (857–861, 2231–2235); Y7–Y7m executed. Its position against its cap: B1 below. |
| Fable S1: the return-move-reissue deadlock | **closed as found** | the leaving refund takes the root's payment lock first (2254–2256); CR24 executed, no deadlock. r6 opened a different cycle: S1 below. |
| Opus S2 / Fable S2: a give-back that only cancels a deficit | **closed** | refused only as far as an escheated credit would read positive, after the row, under the family's locks (830–844); Y8–Y8b executed (Opus P5 admitted, my P11 admitted). |
| Opus S1: a superuser's future created_at | **closed** | `enforce_cash_birth` (2455–2460), applications (3118–3124), remittances (3325–3329); Y9–Y9d. |
| Fable S3 / Opus S3: agree() | **closed, and it works** | `pg_temp.agree` (battery 1954–1998) over every W pair and r6 shape; extended to my P1 shape it fails (B1). |
| Fable N1 (R17), N3, N4; Codex S1 | **closed** | R17 corrected (311–319); R18, R19 (320–326); the comments read. |
| Opus N6 (timing) | **closed** | R21 (332–338); not re-measured. |

## Rulings

- **K-10:** the pool cap holds the payment and its whole family together (3062–3091) and refused every draw past what was paid out in every shape tried, including P1 (predicted from the code, executed in P1/P1c where it is the only thing standing between the reissue and 20 it cannot have). Faithful.
- **Ryan, 2026-10-21 (statuses, the reissue, escheat):** the reissue still carries exactly the refund as far as the credit had it (W6–W8, Y7d), and nothing comes back onto an escheated credit except the cancelling of a debt (Y8b). Faithful. R20's attribution (the overpayment credit first, then reissues in recorded order; a give-back the latest first) is sound as a bookkeeping rule and the pool cap keeps the money whole whatever it says, but see B1: the attribution and the pool disagree about the reissue once money returns to it.

## Blocking

### B1. The cover settles a deficit between the payment and its credits, not among the credits: a reissue whose refund comes back reads money the pool refuses, while the overpayment credit carries a shortfall (executed, P1 and P1c; `probe1.sql`)

`overpayment_absorbed_as_of` (1836–1850) sums the family's own positions into one figure `v_f` and covers only when `v_f` and the payment's `v_p` have opposite signs. Nothing moves a deficit between two credits of the family. A shortfall falls on the overpayment credit (1733: `v_short` on credit 1); a reissue can later regain money (its refund comes back while it is active, which puts the money on it, not into a new credit: that rule is for escheated credits only). The two then sit side by side.

**P1 (owner history load, each act at its own instant; then tally_app).** Payment 100 posted, overpayment credit K 100. K refunds 20, posted, the check comes back (K active). Reissue R 20 from that refund (K carried 20, holds 80). K refunds 30, posted (K holds 50). R refunds 20, posted (R holds 0). The payment bounces in full (admitted: no pending refunds). Shares: R held 0, K 50, the payment's own part 0; the shortfall 50 falls on K: K's share 100, R's 0.

```
after the bounce:            payment 0, K −50, R 0         (sum −50 = 30 + 20 paid out; right)
R's 20 refund comes back:    payment 0, K −50, R 20        (sum −30: 30 paid out and standing; right)
agree():                     FAIL (credit …22): it reads 20.00, and a refund of 20.00 got 23514
a refund of 0.01 from R:     refused by the pool ("payment … and its overpayment credit: … 130.01, more than the payment's 100.00")
```

R reads 20 it can never give; K reads a 50 debt of which 20 is not owed. The record is permanent: nothing moves it (K cannot be voided or escheated with a deficit; R's refund of anything is refused). The cover sees `v_f = −30`, `v_p = 0` and does nothing. **P1c:** the same with the payment holding 40 of its own (K 60; 70 taken back): the cover takes the payment's 40 for K, and R's 20 still sits beside K's remaining −30 (`payment 0, K −30, R 20`; agree() fails the same way). The money is safe throughout (the pool), as in round 5's Opus B1 and Codex B2; the positions disagree with the caps, which is what round 5 blocked on.

**Fix:** net within the family before, or together with, the sides. In `overpayment_absorbed_as_of`, after `v_own` is built: a credit in deficit is covered first by the other credits holding money (the latest first, R20's give-back order, or the overpayment credit first; an attribution either way), then by the payment; a payment in deficit from the credits as now. In P1 that reads K −30, R 0, payment 0, and each equals what its cap admits. The caps need no change: R's own cap (its amount less its share less its draws) would still admit 20, and the pool refuses it, so agree() then holds (predicted). Tests: P1 and P1c as battery checks through agree(); a mutation dropping the within-family leg.

## Should fix

### S1. A reissue's void and a give-back under its payment take the family's locks in opposite orders (executed, `rr6.sh` RR-E: 40P01, the give-back the victim)

The as-built note 4 removed the payment lock from a reissue's void because "a void takes no lock after it". It does: the void of a reissue takes the credit its refund came from (2356), then its own row's (2363): K, then R. The give-back under the payment takes the payment, then the family `ORDER BY f.id` (830–833): with R's id below K's (half of all families), R then K. The header's rule (a source before what draws on it; payment before credit) does not order K against R, and the two writers disagree.

```
P 100 posted; K 100 (id …22); K's refund 20 out and back; reissue R 20 (id …21); take-back 10 under P  (committed)
C: holds K's lock alone (as K's escheat move does: 2363 takes only the credit's)
A: void R                               -> waits on K behind C
B: give-back −10 under the take-back    -> tree, P, R; waits on K behind A
C commits: A takes K, then wants R (B's); B wants K (A's)
B: ERROR: 40P01 deadlock detected (in enforce_ledger_reversal's family lock); A commits, R voided
```

Not unsafe (B retries), but it is the same class as my r5 S1, and the fix that removed it is the one the as-built took out. **Fix:** a reissue's void takes the payment's lock first when `overpayment_root` is not null (P, K, R: the order every other writer on the family keeps), and the header says so; or the give-back takes the family in family order. The first is the stated rule. Test: RR-E's shape as a race (B waits, no deadlock), a mutation dropping the lock (N211's style).

### S2. Tests for B1 and S1 as above

Y7j is the only agree() shape with a reissue holding money, and nothing returns money to a reissue after a take-back. One check where a reissue's refund comes back after the payment's bounce would have caught B1.

## Notes

- **N1 (executed, `rrf.sh` RR-F; R2, R17).** A refund's return whose transaction began before a take-back was recorded, and committed after it, is stamped at its start, so the split reads the take-back with the refund already back: payment 60, K 20, K's 20 refunded; A begins, B takes back 10 (K held 0: the payment's, 30/0 as Y5c), A returns the refund stamped before B's row: the split now has K absorbing 10 (payment 40, K 10, read at any instant including the take-back's own). Both readings add up to the ledger and each side equals what its cap admits, so this is an attribution shift, not a disagreement; and -22's model (R2) says a reading is fixed only once the instant is older than every open transaction, which A's was not. It does mean "each share is fixed once recorded" (1796) holds in that sense only: the move takes the payment's lock after the take-back committed but has no recorded-order leg of its own. If a leg is wanted, it is `check_cash_order`'s first one on the status move; I would leave it and say it under R17.
- **N2 (predicted).** `cash_lineage_recorded` is complete for what the split reads (credits' and refunds' instants, the tree, the draws, the leaving moves); it does not include a credit's escheat move time or the payment's posted time, which the split does not read. It refuses no history load loaded in order (Y6b, Y6d). A payment's lineage reaches the family only through the one live credit (`status <> 'voided'`, 2851): right, since a voided credit's family holds nothing.
- **N3 (predicted).** The recorded-order legs on a take-back refuse nothing legitimate: a draw on the credit or a reissue committed after the take-back's transaction began is exactly what the split would misread, and 40001 is a retry. A history load must write the credit after an earlier take-back (W4's order), which Y5a states.
- **N4 (predicted).** Lock order besides S1: every draw on the family, the leaving refund, the reissue and its void of the overpayment credit take payment first; the escheat move of any credit takes only its own row; the bounce takes the payment only. No other pair reverses K against R.
- **N5 (predicted).** The pool cap within one instant (R17) still holds the total for any reading: the per-credit cap reads its share as recorded and the pool reads the draws; a same-instant draw moving a share cannot free money past the pool. The sizing of a reissue counts its own share (3308–3310): right, and at insert its share is 0 unless the take-back is in the same transaction.
- **N6 (predicted).** Roles and superuser: the write-once status time and the future-`created_at` refusals bind the owner; `check_cash_order` and `cash_lineage_recorded` are granted to tally_app only, as `check_cash_source` is, and run inside ENABLE ALWAYS triggers. No new path.
- **N7.** Mutations N192–N211 read, not run: each new leg has one at its check; N194/N195 drop the two cover directions, so a third direction (B1's fix) needs its own.
- **N8.** Residuals R1–R21: none blocking. R20 is honest about the attribution; after B1's fix it should say the cover also runs among the credits.
- **N9.** `tests/v5.4.2-23/red-r6-against-r5.txt` not reproduced.

## Probe record

Order on one clone: strict apply ×2, the battery (344 PASS, rolled back), P1/P1c appended to the battery (rolled back), the race script (38 PASS, committed), RR-E and RR-F under tenant …23f0 with ids …26xx and …27xx (committed). Clone dropped after this file was written.
