# Fable review — v5.4.2-24 r2 (unmatched cash and agency pledges)

**Date:** 2026-11-07. **Reviewer:** Fable (claude-fable-5-1). **Brief:** `review-brief-24-r2.md` (md5 `de4fcfe90ac651ae07079d50e7ed974e`, matched).

**Frozen hashes checked, all matched:** patch `9b440cd1…`, battery `46d5e076…`, races `f0cd45f0…`, mutations `e366080d…`, ci diff `c343828b…`, r1-to-r2 `259bc084…`.

**Verdict: not yet.** Every round-1 finding is closed (mine and, as far as the brief names them, Opus's and Codex's). One new item is blocking: the misposting return is a release that the recorded-order rule does not order, and in a live two-session run it is recorded before the reversal it depends on, so a reader at that recorded instant finds the same 100 both in suspense and on the customer's ledger (B1). It is the mirror of Codex's round-1 B4 and takes the same one-branch fix. One should-fix: the invariant pins nineteen bodies but not the helpers those bodies stand on (the READ COMMITTED pin, the "today" dates, the agreement-in-force lookup, the aged and open readers), so a superuser can switch the pin off with the invariant clean (S1).

**Scratch database:** `rv24fable` (TEMPLATE `tally`; TEMP revoked from PUBLIC, `tally_app`, `tally_core`; frozen r2 patch applied strictly twice, then the battery, then the races, then a committed copy of the battery for fixtures; dropped at the end). I did not run `ci.sh` or `mutations-24.py`; created, dropped or altered no role; read no `opus-*` or `codex-*` file.

## Reproduced (executed)

- Strict apply (`search_path=''`, `check_function_bodies=on`): clean; second run skipped by the marker.
- `battery-24-frozen-r2.sql`: **234 PASS**, no FAIL (rolled back; a second run with COMMIT in place of ROLLBACK, also 234, left the fixtures for the probes).
- `suspense-24-frozen-r2.sh rv24fable`: **21 PASS** (SU1–SU10c), every B leg seen blocked by A.

## Round-1 findings — closed (executed through the battery and races)

Fable B1 (pin inside `check_provider_transaction_once`: SU8, M81), B2 (provider id on UPDATE: U8h, M79), S1 (constraints, indexes, grants and bodies in the invariant: I8–I8g, M89–M93), S2 (L6 in the header and the comment), N3 (the retry rule in the header), N4 (L19), N5 (L5 widened), N7 (L17e), N8 (the lapse message). The brief's list for Codex and Opus (reversal gives nothing back, recorded order, self-exclusion within a table, instrument drift, clocks, settings) is covered by P9b–P12d, O1–O3, U8f/U8g, P5e, S5b/S5c and I ran each.

## B — blocking

### B1. A misposting return is recorded before the reversal it depends on; at that recorded instant the money is in two places — **executed, live, no chosen times**

What it does: the r2 rule is that a reversed payment keeps its share spent until a `misposting_returned` row gives it back. `check_suspense_recorded_order` orders every *draw* (a receipt's payment, a positive disposition) after every row already on the receipt, but the return is negative and is not ordered at all — not after the payment it returns, and not after that payment's reversal (`status_recorded_at`). `enforce_suspense_disposition` sees the reversal under READ COMMITTED, so the return is admitted whenever the reversal has committed, even if the return's transaction began first and so carries an earlier `created_at`. A reader at any instant between the two stamps then finds the receipt holding the 100 (the return is known, the reversal is not, and the payment is not voided so it counts — and is netted by the return) *and* the payment received 100 on the customer's ledger. The close snapshot, `suspense_held_as_of` and `payment_position_as_of` disagree with the bank by 100 at that instant, permanently. Lesson `history-stamped-at-xact-start`: refuse the writer begun earlier (40001), don't move the stamp.

Evidence (two sessions; A is the file, B a second `psql`; R `RF-f201` 100, its payment `PF-f211` 100 to C1 posted and committed first):

```
-- A: BEGIN; SELECT now();                               -- A's stamp pinned
-- B: ledger reversal of the posting entry + UPDATE payments SET status='reversed' …; commit
-- A: INSERT misposting_returned (-100, 2026-04-03, returned_payment_id = PF-f211);  -- ACCEPTED
-- A: COMMIT
 return_recorded               | reversal_recorded             | return_before_reversal
 2026-11-07 21:34:04.084988+00 | 2026-11-07 21:34:04.310877+00 | t
 receipt_held_at_mid | payment_received_at_mid
 100.00              | 100.00
```

(`mid` is halfway between the two stamps: `suspense_receipt_position_as_of(R, 2026-12-31, mid).held` and `payment_position_as_of(P, 2026-12-31, mid).received`.) The same with a superuser's chosen `created_at` 12 hours before the reversal (X9b): accepted, receipt holds 100 as read 6 hours before the reversal.

Fix: in `enforce_suspense_disposition`, for `misposting_returned`, after the status and return-code checks: `v_later := greatest(v_pay.created_at, v_pay.status_recorded_at)`; if `v_later > NEW.created_at` then 40001 when `NEW.created_at = now()` ("retry"), else 23514 — the two branches `check_suspense_recorded_order` already has, so it could take an optional extra timestamp instead. Battery: a chosen-time return before the reversal's stamp refused (23514) and one after admitted; a race SU11 (A begins, B reverses and commits, A's return refused 40001; the retry admitted). Mutation: drop the branch, named at the new battery check. The same branch could cheaply order a receipt's payment after `r.created_at` (N2).

## S — should fix

### S1. The invariant pins the guards' bodies but not the helpers they stand on, or their `search_path` — **executed**

What it does: `c_bodies` has nineteen functions, but not `suspense_require_read_committed` (every READ COMMITTED pin runs through it), `suspense_today_latest` / `suspense_today_earliest` (every "no later than today" and "pay_by has passed everywhere" test), `assistance_agreement_in_force` (what pay_by is), `suspense_receipts_aged_as_of` and `agency_pledges_open_as_of` (what -26 reads), `suspense_held_as_of`, or the two `*_days_as_of` wrappers. Nor does it check `proconfig`, so a pinned body under a changed `search_path` passes. A superuser (or a later patch by mistake) can replace any of these and CI stays clean, and the pinned guards then enforce nothing:

```
CREATE OR REPLACE FUNCTION public.suspense_require_read_committed(text) … BEGIN RETURN; END
SELECT public.assert_suspense_pledge_guard_invariants();   -- X4a: PASSES; -23's assert_cash_guard_invariants too
CREATE OR REPLACE FUNCTION public.suspense_today_latest() … SELECT DATE '9999-12-31'
SELECT public.assert_suspense_pledge_guard_invariants();   -- X4c: PASSES
INSERT INTO public.suspense_receipts (… received_on = 2031-01-01 …);  -- X4c2: ACCEPTED
… assistance_agreement_in_force → NULL                       -- X4d: PASSES (every new pledge gets no pay_by)
ALTER FUNCTION public.check_suspense_receipt_cap(uuid) SET search_path = pg_temp, public;  -- X4e: PASSES
… suspense_receipts_aged_as_of → empty                      -- X4f: PASSES (-26's aged_suspense sees nothing)
```

Control with the pin intact (X4b): a receipt's payment under REPEATABLE READ is refused 25000. Fix: add the eight bodies to `c_bodies` (the mutation runner's `refill` already recomputes them), and require `proconfig @> '{search_path=public, pg_temp}'` for each listed function, the way `assert_seal_role_invariants` does at `tu.sql:46787`. Battery I8h: a helper's body replaced, expecting the raise.

## N — notes

- **N1 (executed).** Re-reversing the reversal after a misposting return — the other way to have the money twice — is refused by -23 (`23001 … gives money back to payment …, which has ended`, X1). Nothing to do.
- **N2 (executed, chosen time).** A receipt's payment recorded (superuser `created_at`) an hour before its receipt is accepted (X3). At the instant between, the receipt reader returns no row, so no holding figure is wrong; the payment just names a receipt not yet known. One `greatest(…, r.created_at)` in B1's fix closes it.
- **N3 (executed).** The r2 rule leans on the return code as the mark of a bank take-back. -19 freezes `return_code` once set (`23001 … write-once once recorded`, X5a as `tally_app`), so it cannot be erased to make a take-back look like a misposting. Closed by -19.
- **N4 (read).** `suspense_setting_days_as_of`'s raise ("not a whole number of days") is unreachable while the history CHECK stands and has no battery check; belt-and-braces, fine as is, but say so in its comment.
- **N5 (read).** Stale text: the table comment on `suspense_receipt_dispositions` and the comment on `suspense_receipt_position_as_of` still say payments "not voided or reversed" — r2 counts a reversed payment. The invariant's last message names two functions while checking three.
- **N6 (executed).** Lock order as built matches the header: on `payments` the BEFORE triggers sort -23's `a_*` locks before `enforce_payment_suspense_pledge` (the transaction-id lock, then the pledge's; on UPDATE the receipt's for a return code), and AFTER `enforce_cash_draw` before `enforce_payment_suspense_cap` (the receipt). A disposition takes the receipt's lock only and reads payments without a -23 lock, so no cycle through -23. SU1–SU10 all saw B blocked by A.
- **N7 (read).** Tests: the new checks are pinned to concrete dates on both sides (P9b2 03-04/03-05, P9c2/P9c, O1/O1c, S6d) and each mutation I traced names the first-failing check (M15/M16 at P9c2, M71–M77, M79–M86, M89–M94; `refill` keeps the body check from catching a mutation first). Missing: B1's return-order check and race; S1's helper-body check.
- **N8.** Known limits L1–L6: none blocking. L5 and L6 state the trace's gaps as Ryan settled them.
- **N9.** Two `crystaldba/postgres-mcp` containers were running at my start (`docker ps` count 2); I did not touch them.

## Answers to the brief's questions

1. **Round 1 and the design.** Every round-1 finding is closed. The patch implements the design and the rulings: receipts held and never applied by guess, the cap on every date with a reversal giving nothing back until the misposting return, the recorded-order rule for draws, one provider transaction across receipts and payments under the pin, settings with fail-loud readers and a CHECK on the history, agencies and dated agreements, pledges with database-chosen agreement and pay-by, events ending a pledge once, the 11-07 refund rule within L5 and L6. Not yet: the return is a release the recorded-order rule leaves out (B1).
2. **Paths around a rule.** Found: B1 (a recorded instant with the money in two places). Not found: a receipt spent twice (cap under multi-row, CTE and COPY held in r1 and the misposting checks P9b–P12d, SU9, SU10 hold now), out-of-bounds or cross-tenant receipt payments, a database-made guess, a provider id twice (U8f–U8h, SU5, SU8), a pledge paid by another agency or customer or ended twice, an early lapse, a payment naming an error pledge, a refund misrouted through the traced origins (G1–G6b), an agency brought back, an agreement edited, a return code erased (N3).
3. **-23 and -27.** -24 changes nothing -23's positions, caps or recorded-order rules read; the new triggers sort after -23's on both sides (N6). B1 is -24's own reader disagreeing with -23's, not a change to -23.
4. **Concurrency.** Lock order followed; every cap and count read is under its lock and the pin. The misposting return is under the lock and the pin but its stamp is not ordered (B1).
5. **Invariants.** Catches what it claims (I8–I8g executed). Narrower than the design's intent: the helpers and `search_path` (S1).
6. **Tests.** Battery 234 and races 21 reproduced; no check weaker than its label among those traced; mutations not run (restricted). Missing tests in N7.
7. **L1–L5.** None blocking (N8).
