# Fable review — v5.4.2-24 r11 (unmatched cash and agency pledges)

**Date:** 2026-11-24. **Reviewer:** Fable (claude-fable-5-2). **Brief:** `review-brief-24-r11.md` (md5 `4040b5b267aa9775c6aaaaa6074df157`, matched its `.md5`).

**Frozen hashes checked, all matched:** patch `5518d763…`, battery `83283377…`, races `360dea4d…`, mutations `46f7ef48…`, ci diff `ec30f743…`, r10-to-r11 `f428a197…`. I reviewed the frozen copies only.

**Verdict: not yet.** One blocking item, executed as `tally_app`: the new rule "a payment ended `reversed` takes a bank return code only where the row it names takes back the whole payment" measures the named row's whole subtree, not the row. So round 10's blocking shape (60 misposted and 40 the bank's, both plain reversals, ended with the bank's code, the 60 then on no list) is still admitted when the two take-backs hang under the named row's undo instead of under the posting entry. The same money filed under the posting entry is refused. The fix is one condition; with it applied by hand the battery's 315 checks before the body pins all still pass. Everything else from round 10 is closed as the plan states. Two should-fix items: a superuser's load can still bear a receipt's payment `posted` (the receipt is spent and the money is nowhere, for good), and the deposit entry type has no fixture.

**Scratch database:** `rv24fable` (TEMPLATE `tally`; TEMP revoked from PUBLIC, `tally_app`, `tally_core` right after creation; frozen r11 patch applied strictly twice; the battery; my probes appended to a copy of the battery's first 1408 lines and rolled back with it; the two proposed fixes applied by hand to `enforce_payment_suspense_pledge` and reverted, the invariants clean after the restore; the races; dropped at the end). I did not run `ci.sh` or `mutations-24.py`; created, dropped or altered no role; read no `opus-*` or `codex-*` file. Two `crystaldba/postgres-mcp` containers were running at my start; I did not touch them.

## Reproduced (executed)

- Strict apply (`search_path=''`, `check_function_bodies=on`): clean; the second run is skipped by its marker ("already applied (suspense_receipts exists)").
- `battery-24-frozen-r11.sql`: **335 PASS**, 0 FAIL (rolled back).
- `suspense-24-frozen-r11.sh rv24fable`: **29 PASS**, exit 0. `assert_suspense_pledge_guard_invariants()` clean afterwards.
- Trigger order (by name, all ENABLE ALWAYS): on `payments`, -23's `enforce_payment_immutable` runs before `enforce_payment_suspense_pledge`; on `account_ledger`, -23's `enforce_ledger_reversal` runs before the new `enforce_ledger_suspense_posted`. Both orders are the ones the new rules need (see questions 3 and 4 below).

## Round-10 findings

| Finding | State |
|---|---|
| What the bank took was ambiguous at the end (Codex B1; Opus S1, S3) | **Not closed for one shape: B1 below.** The other three rules hold (executed: P17–P19 re-ran; my E1–E7 below). |
| A code hid the payment at instants before the move (Opus S2) | Closed (S8y passes; the gate reads `status_recorded_at`). |
| A pending receipt payment's posting entry undone (Opus S4) | Closed, for every role and statement shape I tried (question 3). |
| A receipt's payment born ended (my S2) | Closed for `reversed` and `nsf`, also under `session_replication_role = replica` and by COPY. **Born `posted` is the same hole and is open: S1 below.** |
| Conservation over every receipt (my S1, Codex S2, Opus N4) | Closed as written; one shape the formula over-counts (N1). |
| Tests, races | Present and passing here. |

Rounds 1–9: the battery checks that hold them all re-ran (335).

## B — blocking

### B1 (executed, as `tally_app`). A coded `reversed` is admitted over two plain take-backs when they hang under the named row's undo: the misposted part is then on no list and can never come back.

The rule added in r11 is `ledger_entry_remaining(NEW.status_cause_id) < NEW.amount` → refuse. `ledger_entry_remaining` is the row's amount plus the net of everything beneath it, so a named row that was undone and then taken back again by other rows beneath the undo still "remains" 100. -23 needs the named row to sit directly under the posting entry, so the clerk names the first reversal; what actually stands is the rows beneath it.

Probe F1 (receipt 100, payment 100 to C1, all as `tally_app`):

```sql
SELECT pg_temp.rev(z('03'), pay, entry,  'adjustment',  100, '2026-03-11');  -- whole reversal
SELECT pg_temp.rev(z('04'), pay, z('03'), 'adjustment', -100, '2026-03-11');  -- undone
SELECT pg_temp.rev(z('05'), pay, z('04'), 'adjustment',   60, '2026-03-12');  -- misposted 60, under the undo
SELECT pg_temp.rev(z('06'), pay, z('04'), 'adjustment',   40, '2026-03-13');  -- the bank's 40, plain, under the undo
-- share 100.00 / untyped 0 / remaining(z('03')) 100.00 / reader: 100.00 since 2026-03-12
UPDATE payments SET status='reversed', …, return_code='R01', status_cause_id=z('03') WHERE id=pay;   -- => OK
-- status reversed R01 / reader: none / receipt holds 0.00
-- misposting return of 60:  23514 "is reversed with return code R01 … a bank's take-back keeps it spent"
```

Probe F2, the more natural order (100 reversed, 40 of it undone because only 60 was misposted, then the bank takes the 40, filed under that undo): the coded end naming the first reversal is **admitted**; reader none, receipt holds 0, return of 60 refused. Probe F3, the same money with the 40 filed under the posting entry: **refused** (23514, "only where the row it names takes back the whole"). So the outcome depends on which row the take-back hangs from, not on what was taken.

This is the plan's blocking item 1, first bullet (round 10 probe 01), one level down. The battery's S4c cannot see it: its last term counts a coded payment's whole share as the bank's, which is exactly what the code asserts.

**Fix (executed on the clone):** the named row is itself the whole and has nothing beneath it.

```sql
-- in enforce_payment_suspense_pledge, replacing
--   public.ledger_entry_remaining(NEW.status_cause_id) < NEW.amount
NOT EXISTS (SELECT 1 FROM public.account_ledger x
             WHERE x.id = NEW.status_cause_id AND x.amount >= NEW.amount
               AND cardinality(public.ledger_tree_ids(x.id)) = 0)
```

(The alias must not be `l`: the function declares `l` as the pledge row, and `l.id` is then ambiguous — my first attempt failed that way at battery line 390.) `tally_app` already has EXECUTE on `ledger_tree_ids`. With this applied: F1, F2 and F3 are all refused with the existing message; the battery passes **315 checks and first fails at I1**, the body pin, as any body change does — so P12a, P18b (a bounce undone, then one plain 100 with the code), P21 and P22 are all still admitted. What becomes stricter: a whole reversal that was undone and re-reversed by one row beneath the undo no longer takes a code; it ends without one, comes back to the receipt, and the bank's part is recorded there as `bank_returned`, which is the route the message already gives.

Tests to add: F1 and F2 as refusals beside P17; a mutation putting `ledger_entry_remaining(…) < NEW.amount` back, caught at the F2 check. M-entries at mutations lines 412–414 and 454 anchor on the replaced text and need re-anchoring.

## S — should fix

### S1 (executed, owner). A superuser's load can bear a receipt's payment `posted`: the receipt is spent, the payment holds nothing, and no row or move can ever follow.

r11 refuses born `reversed` and `nsf` because "-23 refuses its rows afterwards, so its money would be nowhere". Born `posted` has the same property. Probe O1, as the owner:

```
INSERT … status 'posted', status_recorded_at now(), suspense_receipt_id = Rc1 (100)      => OK
its posting entry afterwards   => 23514 "a posting row is written for a payment still pending" (-23)
held / received / reader       => 0.00 / 0 / none
posted -> reversed             => 23503 (no posting entry to name)        posted -> voided => 23001
misposting return              => 23514 "is posted"
another payment of the receipt => 23514 (the cap: 200 of 100)
assert_suspense_pledge_guard_invariants() => clean
S4c's sum for Rc1, every day 03-10 to 03-20: 0.00 of 100.00
```

The application cannot do it (-23's `enforce_cash_birth` bears a non-superuser's payment `pending` only). It is the more likely loader mistake of the three statuses. **Fix (executed with B1's):** `NEW.status NOT IN ('pending', 'voided')` in place of `NEW.status IN ('reversed', 'nsf')`; the message already reads right ("is born posted from receipt …: load it pending and move it through its rows"). Battery still 315 before the pins: the load fixtures (R25, Rb7, O4's born voided) are untouched. Add O7c (born posted refused, 23514) and a mutation restoring the two-status list.

### S2 (executed for behaviour; predicted for the mutation). A receipt's payment that is a deposit behaves the same under every rule, but nothing in the tests would notice if it stopped.

The brief's question 1. I built four on the clone as `tally_app` (`is_deposit = true`, posting entry typed `deposit`, -100):

| Probe | Result |
|---|---|
| D1 posted; receipt holds 0; position received 100 | as a plain payment |
| D2 60 reversed while posted: share 60; reader "60.00 since 2026-03-11", none on 03-10; return refused "is posted" | same |
| D3 bank takes 40 as nsf: coded `reversed` naming the 60 row refused (23514); ends `nsf`; return of 100 refused ("60.00 of its 100.00"); return of 60 admitted; receipt holds 60, reader none | same |
| D4 whole reversal ended `reversed` R10: admitted; return refused; reader none; the code afterwards refused (-19's write-once) | same |
| D5 pending, entry undone (100 plain, and 1.00 nsf): both refused by the new ledger trigger; then posted | same |
| D6 a plain row under a bounce's undo: untyped 100; ending `nsf` refused ("is not typed nsf") | same |
| D7 whole misposting, no code: listed 100, returned, receipt holds 100 | same |
| S4c's formula over all T1 receipts with these added | holds |

So no rule differs, and it is **not blocking**. But `'deposit'` appears in five walks (`suspense_misposted_share`, `…_as_of`, `suspense_untyped_take_back`, `enforce_ledger_suspense_posted`, the return's date walk) and no fixture has one (`is_deposit` occurs in the battery only in the pledge CHECK's refusal, line 851), so a version with `'deposit'` dropped from any of the five passes all 335 checks and all 29 races (predicted: I did not run it). Dropped from the share walk, a misposted deposit's money would never come back. A fixture of D2–D3's shape (six lines) and one mutation per walk closes it now, cheaply.

For the deposit patch, not this one (read, not executed): `deposits.source_payment_id` is checked once, at the deposit's insert (same customer, flagged `is_deposit`). Nothing ties the deposit row to the payment's end, so a deposit payment reversed as misposted and returned to its receipt leaves a `held` deposit with no money behind it while the receipt holds the money again. That is true of any reversed deposit payment since -23; the receipt only makes the second holder visible.

## N — notes

- **N1 (executed).** S4c's bank term roots a tree at every nsf row that takes money, so a bounce re-recorded beneath another bounce's undo is counted twice. Probe E5 (bounce 100, undone by an nsf-typed -100, 60 bounced again beneath that undo, 40 reversed plain; ended `nsf`; 40 returned): the patch is right (share 40, receipt holds 40, the bank's 60), and S4c's formula reads 160 of 100 from 03-12. No battery fixture has the shape, so the check passes. Rooting only at nsf rows with no nsf ancestor fixes the formula.
- **N2 (executed).** After the end the tree and the status are fixed, by -23: an undo of the named row (plain or nsf-typed) 23001 "which has ended"; another take-back under the entry 23514 (the cap); `reversed`→`nsf`, `nsf`→`reversed`, `reversed`→`posted` 23001; an undo and a take-back in one statement 23001 (E1a–E1f, E2a, E2b). A bounce's code may arrive later once (E2c) and then not change (E2d, -19).
- **N3 (executed).** One-statement shapes. Where the UPDATE reads the CTE's inserted row (`UPDATE … FROM a`), the guards see the row: the last 40 inserted and the coded end naming it, refused (E6); an nsf 40 inserted and a coded end naming the plain 60, refused (E6a); the payment stayed posted. An undo of a pending payment's entry in an unreferenced CTE with the move to `posted` as the main statement is admitted (E7a): the move runs first, the row's trigger at the statement's end sees `posted`, and the result is an ordinary posted payment wholly reversed, which then ends (E7c). Not stranded.
- **N4 (executed).** -23 admits a `reversed` move naming a row that was itself undone, as long as the posting entry is wholly taken back (E3b); -24 refuses the code on it (E3a) and lists the share (E3c: 100 since 03-12). Fine without a code.
- **N5 (read).** The receipt lock and the READ COMMITTED check that r2 put on a return-code write are gone with the rule they served. Nothing needs them now: a code on `reversed` is refused after the move without reading the receipt, and a bounce's code beside its return is admitted either way (SU15).
- **N6 (read).** Known limits L1–L6: none blocking.

## The three questions put to me

1. **A deposit.** S2: same behaviour under the ending rules, the misposting return, the reader and the ledger trigger (executed); not blocking; add the fixture because the entry type is otherwise unguarded by any test.
2. **Getting round the four ending rules.** One way: B1 (the named row's subtree). The rest held: rows added or undone after the end (N2); `reversed`↔`nsf` (N2); a cause row itself undone (N4, E3a); several rows in one statement and writable CTEs (N3); COPY of a payment born `reversed` as the owner, refused by the trigger; the same born `nsf` under `session_replication_role = replica`, refused (O2a). A history load as owner: S1 (born `posted`).
3. **The new trigger on `account_ledger`.**
   - Writers, from the catalog: `tally_app` (INSERT, SELECT), `tally_void` (INSERT, SELECT; the only SECURITY DEFINER writer is `void_invoice`, owned by it), the owner. `tally_core` and `tally_close` have SELECT only.
   - `tally_app`: reads the parent entry and, only for a payment's posting entry, `payments`; it has SELECT on both and both rows are its tenant's. Refuses only the write it is for (D5, E7).
   - `tally_void`: has no privilege on `payments`. For a charge's reversal the function returns before touching it (read; the author's ci.sh run is the execution). If `tally_void` ever wrote a row under a payment's posting entry it would fail 42501 — but in -23's `enforce_ledger_reversal`, line 259, which runs first by name (executed, L1). So -24 adds no new failure.
   - Owner, and replica mode: ENABLE ALWAYS means it fires under `session_replication_role = replica` (O2b: the undo under a pending receipt payment refused there too). A parent that does not exist with foreign keys off: the function returns NULL without error, and -23's guard refuses the row anyway (O2c, 23503). A legitimate load never undoes a posting entry while its payment is pending, so nothing legitimate is refused.
   - Multi-row insert: AFTER ROW triggers run at the statement's end, each row seeing the whole statement. The posting entry and its undo in one INSERT for a pending payment: refused (E7). The read of the payment's status happens after -23's trigger for the same row has taken the payment's lock, so a concurrent move to `posted` is either waited for or refuses first.

## The brief's questions

1. **Closed?** Round 10: all but B1's shape, and S1 beside my own r10 S2. Earlier rounds: still closed. The patch implements the design and the rulings with those two exceptions to CI-053's "never dropped".
2. **Paths around a rule.** B1 (application role). S1 (superuser load). Nothing else found; the brief's list is held by checks that re-ran.
3. **-23 and -27.** -24 still calls none of -23's writers and changes nothing they read; r11 adds reads of `ledger_entry_remaining` and one AFTER trigger that only refuses. The orders on both tables are by name and are right.
4. **Concurrency.** The ending rules read the tree under the payment's lock (-23's trigger takes it first); every row under a posting entry takes the same lock. The ledger trigger reads the status under it. No cap is read without its lock. Races reproduce (29).
5. **Invariants.** Clean after the battery, the races and the restore; the new trigger, the two new functions and their pins are in the lists. They are structural: they do not (and need not) see S1's row.
6. **Tests.** No check weaker than its label found among the r11 additions. Missing: B1's shapes, S1's O7c, a deposit fixture (S2); S4c's nested-bounce count (N1).
7. **L1–L6.** None blocking.
