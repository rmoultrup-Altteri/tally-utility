# Fable review — v5.4.2-27 r3 (a credit applied to a bounced payment's shortfall; the carry; the undo dated after today)

**Verdict: not yet.** One blocking finding, executed: the new second reading is right about the leaving move, but the undo it refuses can already have been recorded on its own, earlier, and then the returned refund can never be recorded (B1). One should-fix (the recorded-after-escheat check passes on equal stamps, so an undo and an escheat in one transaction still let a carry label a returned refund's money), the rest notes. My r2 S1 is fixed; both r2 blocking items (Opus B1, Codex B1) are fixed as the plan says, with B1 below being the sibling of Opus B1 that the plan's fix leaves open.

Frozen hashes checked first (`md5 -q`): all five match the brief, the brief matches `review-brief-27-r3.md5`, and the frozen patch is byte-identical to `sql/v5.4.2-27-shortfall-applications.sql`. Clone `rv27fable` (TEMPLATE tally; TEMP revoked from PUBLIC, tally_app, tally_core; `has_database_privilege` = f for both app roles); frozen r3 applied strictly (`search_path=''`, `check_function_bodies=on`) twice: the second run printed "already applied (shortfall_applications exists); nothing to do". Server zone Etc/UTC; at the run, "today" was 2026-11-06 UTC and 2026-11-07 at UTC+14. Clone dropped at the end.

## Reproduced

| What | Result |
|---|---|
| strict apply, twice | first applies, second skipped by its marker |
| `battery-27-frozen-r3.sql` | 135 PASS, 0 FAIL, rolled back (0 shortfall rows, 0 B27 customers left) |
| `shortfall-27-frozen-r3.sh rv27fable` | SR1–SR9, 16 PASS, exit 0 (it commits rows into the clone, under `…28xx` ids; my probe ids moved to `…d7xx`) |
| the 66 `rep()` anchors of `mutations-27-frozen-r3.py` | each is exactly one occurrence in the frozen patch (python check); each named check exists |

Mutations and `ci.sh` not run (restricted). Read: M56–M63 each remove the line that their named check pins (M56 one pass → R1 admits; M57 UTC-12 → R2's undo dated today at UTC+14 reads as tomorrow, refused; M57b today+1 → R1b admits; M58 no zero row → with nothing dated between today and 2099 the reading sees only 2099, R1 admits; M59–M63 as labelled). M60 would also be caught by the size check's different message (G's escheat took everything, so `v_left` = 0): still caught.

## My r2 findings

| r2 | Status | Evidence |
|---|---|---|
| S1 — the carry leg of `cash_source_draws` had nothing pinning it | **fixed** | E7d reads `cash_source_draws('credit', CE)` for KE at 30 (ran, PASS); M63 sets that leg's WHERE to false and names E7d |
| N1–N5 | notes, unchanged; N2's mixed lines are now the battery's E16–E18d | |
| N6 — `repaid` printed `0` | **fixed** (`0.00`); K0, F0, B1b now expect `/0.00` and pass | |

## Findings

### B1 (executed) — an undo dated after today, recorded on its own before the refund comes back, makes the return unrecordable

Probe P1, customer Y1, as tally_app: P pays 50 (03-10), is refunded 30 (03-11), bounces (03-12); G, a goodwill credit of 30, repays it dated 03-13. Then the operator records the undo of that repayment dated 2099-12-31, **alone** (the refund is still out): **admitted** (P1a). Nothing checks the target's cap at an undo's insert — `check_shortfall_repaid` runs for a repayment and for a leaving move, and after an undo only on the *source's* payment (G has none). Positions after it: P today 0.00 remaining / 30.00 repaid; P on 2099-12-31 −30.00 / 0.00; G today 0, G in 2099 30. Nothing wrong yet: the customer owes the 30 again from 2099.

Then the refund check comes back (ledger row 03-20; the refund's move to nsf): **refused** by the second reading (P1b: "on 2026-11-07 what was applied to its shortfall would leave it … holding 30.00 … dated no later than today"). Every way out is closed:

- a second undo of the repayment, dated today: refused, "its undos would come to 60.00, more than its 30.00" (P1c);
- a repayment from another credit H, 30, dated today, to free the family: refused by the same reading (P1d; P would be repaid past 0 until 2099);
- the refund's move dated 2099-12-31 (`nsf_date` in the future): refused (P1e; the reading is from today, every row at its own date);
- the owner, as a history load with a chosen `status_recorded_at`: refused (P1f).

An undo is never undone, the repayment cannot be edited, and G cannot be voided or escheated in a way that changes P's reading. So a returned check — a bank fact — cannot be entered until 2099-12-31. This is Opus B1's sibling: the same typo, one step earlier. r2 admitted the return and read the ended payment holding 30 until 2099; r3 refuses the return instead. Both are "nothing can repair it", which is the standard that made Opus B1 blocking. The source kind and the target's status do not matter (predicted: a payment source and a reversed target go through the same two calls).

The brief asked exactly this ("can the new reading refuse a correction the operator has no other way to make"), and the answer is yes, through this sequence.

**What closes it.** The undo's date is the only input the trap needs, so it is cheapest at the undo's insert, in `enforce_shortfall_application`'s undo branch: refuse an undo of a shortfall application dated after today (the same `v_today`, UTC+14) **when it is dated after the row it undoes**. An undo dated on its row's date nets to zero at every reading, so a future-dated pair (P2 below: repayment 2027-01-01, undo 2027-01-01) stays admitted, and no money date is limited to today for its own sake: what is limited is the interval during which the ended payment reads the money, which r3 already limits to the past at the leaving move. The second reading stays as the backstop for the undo recorded in the same transaction as the return. The plan's reason for not taking Opus's option 1 ("-23 never limits a money date to today") is then intact for the pair and half-crossed only where r3 already crossed it. A test: R0, the standalone undo dated 2099 refused; R0b, dated today admitted; a mutation on the new branch. If Ryan would rather keep the undo's date free, the alternative is to accept this as a residual with a named recovery — and I could not find one short of the undo's date arriving.

### S1 (executed) — the recorded-after-escheat check passes on equal stamps: an undo and the escheat in one transaction still let a carry name the undo for a returned refund's money

`v_undo.created_at < v_ended` with both stamped `now()` (the undo's default `created_at`; `status_recorded_at := now()` for every role but a superuser choosing one). In one transaction they are equal and the check passes. Probe P4, customer Y4, as tally_app, all in one transaction: G 40 repays 20 of P (03-13); the undo of 20 (03-14) while G is active (the 20 is simply back on G; the commit check flushed clean); G refunded 20 (03-15); G escheated 20 (03-16, nothing left, `created_at = status_recorded_at` printed true); the refund comes back (03-17), so the escheated G reads 20. A `shortfall_reissue` of 20 naming the old undo: **admitted** (P4a). The `refund_reissue` of the returned 20 is then refused, "0.00 before it" (P4b), and every deferred check flushes clean (P4c): the transaction commits with the returned refund's money carried under the undo's name, which is the mislabel Opus S1 described. Two transactions suffice: the undo and the escheat in one (an end-of-dormancy routine that undoes stray applications and then escheats is a plausible app flow), the return and the carry later. Money is not lost (it is in the carry, active), and the size check still refuses the carry whenever the escheat took everything and no refund came back (G then reads 0); the harm is the label and the missing `reissues_refund_id` lineage.

`<=` closes it: a carry then needs an undo recorded strictly after the escheat's stamp, which is any later transaction. Its cost: a flow that escheats the credit and records the return, the undo and the carry all in one transaction would be refused (tally_app cannot choose `created_at`); I do not think that flow is legitimate — the escheat is a remittance, the return a bank event — but it is Ryan's call. A one-transaction history load as the owner can choose the undo's `created_at` later than the escheat's `status_recorded_at`, as -23 already expects of it ("a history load records a move after every row it follows").

### N1 (executed) — a repayment dated in the future, with its undo

Probe P2, customer Y2: a repayment dated 2027-01-01 is admitted (P2a; P reads −30 today and 0 / 30 on 2027-01-01). The refund comes back: with the undo dated 2027-01-02, refused by the second reading on 2027-01-01 (P2b: the family would hold 30 that day); dated today, refused by -27's own rule that an undo is dated on or after its row (P2c); dated 2027-01-01, admitted (P2d), and P reads 0.00/0.00 today, on 2027-01-01 and on 2027-06-01, G 30 on 2027-06-01. So the operator always has a date for the undo: the repayment's own. With B1's fix as proposed, the pair stays admitted at the undo's insert too.

### N2 (executed) — mixed partial undos on both sides of today

Probe P3, customer Y3: undos of 10 dated yesterday and 20 dated 2099, with the return: refused, holding 20 on today (P3a). 10 yesterday and 20 today: admitted (P3b); P reads 20.00/20.00 yesterday (R5's interval, in the past) and 0.00/0.00 today, G 30 today.

### N3 (executed) — the born-active check under every statement shape and the owner's moves

Probe P5, customer Y5, as the owner: a carry born `escheated` by `COPY … FROM STDIN` is refused by the new message (P5b); the right carry by COPY is admitted and reads active (P5d); the owner's move of it to escheated with a chosen past time and no event is refused by -23 (status_cause: "its escheated_to_state escheatment event", P5e); the owner's void is refused by -27's `enforce_shortfall_reissue_rows` (P5f). A multi-row INSERT of one active and one voided carry on the same undo was refused by the one-per-undo index before the status check (P5c; my fixture, not a gap: the AFTER ROW trigger runs per row, as COPY shows). I found no path that moves a carry out of active except -23's checked moves: the escheat needs an `escheated_to_state` event, whose insert is a draw under the cap, and a credit the carry has drawn nothing from reads its full amount.

### N4 (predicted) — the two readings leave no holding outside R5's interval before today

The second reading, from today with every row at its own date and the zero row at today, means no date from today on reads the family holding money. The first reading reads the undo at its row's date; the positions read it at its own; the two agree everywhere except on [repayment's date, undo's date), which is R5, now bounded by today. Before the first repayment the family cannot hold money through a return (the return alone leaves the ended payment at 0; the holding comes only from a repayment). I built no sequence of partial undos, back-dated repayments and leaving moves that passed both readings and read money held at a date outside R5 before today (r2's N4 fixture reasoning, now with the second reading).

### N5 (predicted) — "today" at UTC+14, and `status_recorded_at`

`Etc/GMT-14` is UTC+14 (POSIX sign), the latest civil date anywhere; `tenants` has no zone column, so there is no tighter zone-free bound that never refuses an undo dated today locally; it mirrors -22's UTC-12 close, and a period closed under that rule can never contain `v_today` (the UTC-12 date is at least one day past a closed period's end, and the UTC+14 date is never behind it), so an undo dated today is never frozen out. `status_recorded_at` is the right stamp (the database's, for every role but a history load that chooses one, which -23 holds to a past time after the lineage); `escheated_at` is the app's. Agreed.

### N6 (predicted) — `cash_drawn_at`'s source-shortfall and repaid terms

Agreed that no instant observes them. Its one reader asks at a take-back's instant; R15 holds both a status move (`enforce_shortfall_source_moves`) and a ledger row taking money back under the entry (`enforce_ledger_shortfall_source`, AFTER INSERT, amount > 0) while the source or a family credit is applied net > 0; and a repaid payment has ended, so its posting entry has nothing left to take back. Keeping them for symmetry with `cash_source_draws` is fine; the comment says why there is no mutation.

### N7 (predicted) — the invariant does not state the born-active rule

`assert_shortfall_guard_invariants` renders the trigger definitions (unchanged in r3) and cannot see bodies; the plan said "the rule is added to the invariant", and it is in the trigger's comment and the header, which is all the invariant can carry. Nothing to fix; I note it so the claim is read as the comment, not a check.

### N8 (predicted, -23) — no commit check carries a returned refund of an escheated credit

P4c: with the `refund_reissue` refused and no carry, every deferred check flushes clean and G (escheated) would read 20. That is -23's residual, outside -27's tables; noted for the money stream alongside the plan's note.

## The brief's questions

1. **r2 findings fixed:** my S1 and N6, yes (above). Opus B1 (the future-dated undo) is fixed for the shape Opus ran — the undo in the return's transaction (R1, R1b refused; R2 admitted) — and B1 above is the shape it leaves open. Codex B1 (a carry born ended) fixed for every role and shape (E6c, E6d; P5b COPY).
2. **The r3 plan:** implemented as listed — the two readings with the zero row; UTC+14; born active for every role; the undo recorded at or after the escheat by `status_recorded_at` (I agree with the author over `escheated_at`); the tests E7d, S3c, K9e, E17, E16/E18–E18d, E19/E19b, C2b, E7c, R1–R2b, E6c/E6d, E15; M56–M63; the race deadlines; the R5 wording in header, comment and section 3; `0.00`. The two items not done are rightly not done (the bill-application undo at the caller is unreachable under R15; the two terms read 0 at every instant asked).
3. **Paths around a rule:** B1 (an undo dated after today, recorded alone) and S1 (equal stamps). Tried and held: a future-dated repayment with its undo (N1), mixed undos across today (N2), COPY and multi-row (N3), the owner's moves (N3), a history load's chosen status time on the return (P1f), the undo dated before its row (P2c).
4. **-23's properties with the deeper lines:** E16 (generation 2, root OQ, in the family, 10 held, KQ 0) and E18b (generation 3, root OQ, 5 held, R and P2 0) ran and pass; E18d's take-back reaches generation 3. The fixture does what probe 08 claimed. The second reading adds no new reader of caps or shares.
5. **Concurrency:** unchanged from r2. The born-active check reads NEW only; the escheat-stamp check reads the credit before the locks, as the status read already did (harmless: the carry is in the undo's transaction, which holds the payment-then-credit locks). The race script passed on my clone.
6. **Invariants:** N7; claims match checks.
7. **Tests:** none weaker than its label. Missing: B1's R0 (the standalone future-dated undo) and, if S1 is taken, E15b (undo and escheat in one transaction, then the carry). Each r3 mutation's named check is its first failure by construction, and M60 is caught either way.
8. **Residuals:** R1–R4 as before; R5 as amended is correctly stated and not blocking. B1 is not among them and should be either closed or written in as one with its (absent) recovery.

## Probe file

`/private/tmp/claude-501/-Users-ryanscomputer-code-tally-utility/1dff16d9-6dfb-40ad-a60b-fd9517b382c2/scratchpad/probe-r3-fable.sql` — P1–P5 above, one transaction rolled back, built on the battery's helpers (its first 122 lines are the battery's preamble); ids under `00000000-0000-4000-8000-00000000d7xx`. Runs with `docker exec tally-pg psql -U tally -d <clone> -q -f`.
