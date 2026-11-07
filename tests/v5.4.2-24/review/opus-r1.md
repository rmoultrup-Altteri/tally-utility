# Opus review — v5.4.2-24 r1 (unmatched cash and agency pledges)

**Date:** 2026-11-07. **Reviewer:** Opus. **Brief:** `review-brief-24-r1.md` (md5 `1b3598dba62efb34e0be331cb32e6a0f`, matches its `.md5`).

**Verdict: not yet.** Three blocking items. Two are about the receipt's cap and how it treats a reversed payment. The third is a duplicate provider transaction under REPEATABLE READ. All three were executed. Each has a small fix, and none changes the design's shape.

## Hashes and reproduction (executed)

All five frozen md5s match the brief: patch `eae62ab0…`, battery `e2c82852…`, races `bb428ea6…`, mutations `2e5cd766…`, ci diff `c343828b…`.

On clone `rv24opus` (`TEMPLATE tally`, TEMP revoked from PUBLIC, `tally_app` and `tally_core`):
- Strict apply (`search_path=`, `check_function_bodies=on`): rc 0. Second run: `NOTICE: v5.4.2-24: already applied (suspense_receipts exists); nothing to do`, rc 0.
- `battery-24-frozen-r1.sql`: 188 PASS, no FAIL.
- I did not run `ci.sh`, the races script or the mutation runner, as the brief says. My own two-session race (B3) ran only on my clone. The clone is dropped and `/tmp/rv24opus-*` is removed from the container.

The probes were run with the battery's helpers and fixtures (battery lines 1–171) as a prefix, in one transaction, then rolled back. The probe scripts were scratch files and are not in the repo.

---

## B — blocking

### B1. A payment reversed because the bank took the money back frees the receipt's money again, so the receipt can be spent twice (executed)

The cap and the reader give a `reversed` payment's share back to the receipt. The design's reason is that "reversed" means the payment was posted to the wrong customer. -23 does not enforce that meaning. A move to `reversed` needs only a ledger row that is not `nsf` and that undoes the posting entry. `payments_return_code_check` allows an ACH return code on `reversed` too (`status = ANY (ARRAY['nsf','reversed'])`). So an ACH return (R10, "not authorized") or a card chargeback can be recorded as `reversed`, and the money is gone from the bank. The receipt then reads as holding it again, and the operator can apply it to another customer or return it to the sender. The money goes out twice. This guards the label, not the act (lesson `guard-the-act-not-the-label`).

Probe: receipt R1 for 100; payment P11 of 100 from it to C1, posted; then the posting reversed by an `adjustment` row with `return_code = 'R10'`:

```
 held after payment               | 0.00
 payment status/return_code       | reversed | R10
 held after the bank took it back | 100.00
NOTICE:  O1a the same 100 applied again, to C2 => ACCEPTED
 held after second application    | 0.00
NOTICE:  O1b or the same 100 returned to sender => ACCEPTED
--- contrast: the same return recorded as nsf
 held after nsf                   | 0.00
```

So the fate of 100 dollars depends on which of two labels the operator picks for the same bank event. Mutation M15 ("the cap counts a reversed payment") pins the current behaviour, so it would still be caught after a fix only if it is re-pointed.

**Fix (author's call; measure it):** the money should come back to the receipt only by an act that says it came back. Two options:
- (a) Cheapest: a reversed payment gives its share back only when `return_code IS NULL` and its method is not a card. This still keys on a label.
- (b) Better: a reversed payment stays counted, as an NSF one does. The operator releases its share with an explicit disposition-like row that names the reversed payment and says why ("posted to the wrong customer"), with the user who did it. The cap and the reader count that row. It is add-only and needs no new status.

Either way, add a battery case for a return-coded reversal, and a mutation for it.

### B2. The cap drops a reversed payment from every date, not just from its reversal date, so money can be spent twice on the dates in between (executed)

`check_suspense_receipt_cap` and `suspense_receipt_position_as_of` exclude a payment by its current status (or by its status as recorded at the instant). They never look at the money date the reversal falls on. -23 reads the same payment by money date. In `payment_position_as_of` the payment received its money until the reversal's ledger date. So for every date between the payment and its reversal, the two readers disagree. The cap also admits a disposition back-dated into that gap.

Probe (continues B1's fixture: P11 posted on 03-02, reversed by a ledger row dated 03-20):

```
 payment received on 03-10, known now          | 100.00
 c1 ledger balance on 03-10 (payment entries)  | -100.00
NOTICE:  O8 returned_to_sender 100 dated 03-05 (before the reversal) => ACCEPTED
 receipt on 03-10 known now | amount 100.00 | to_payments 0.00 | disposed 100.00 | held 0.00
```

On 03-10 the same 100 dollars sits on C1's ledger (-23 says it was received) and has also gone back to the sender (03-05). Even without the disposition, `suspense_held_as_of(03-10, now)` reports 100 held while C1's ledger also holds it. Yet known limit L4 says this is the figure that reconciles the subledger to the bank. This answers the brief's question "is every date a row falls on enough?": no. A reversal brings money back on a date of its own, and the cap has to treat that as one of its dates too.

**Fix:** in both the cap and the reader, count a reversed payment on dates before its reversal's money date: the `transaction_date` of the ledger row in `status_cause_id`. Add that date to the cap's set of dates. With B1's option (b), the release row's own date does this job. Add a battery case for a back-dated disposition between a payment and its reversal.

### B3. One provider transaction can be recorded as both a receipt and a payment under REPEATABLE READ (executed; two sessions)

`check_provider_transaction_once` takes the advisory lock and then reads EXISTS. But neither the receipt trigger nor the payment trigger pins READ COMMITTED for that check. Under REPEATABLE READ, the snapshot was taken before the lock was granted, so it hides the row the other side committed (lesson `count-guards-need-lock-handshake`). The two unique indexes each cover one table, so nothing else catches it. Race SU5 and SU5b test this only at READ COMMITTED. SU7 pins only the payment from a receipt.

Session A (`tally_app`, `BEGIN ISOLATION LEVEL REPEATABLE READ`, snapshot taken, sleeps 4 s). Session B commits a `stripe_webhook` payment `pi_o7_once` for 40. Then A inserts a receipt for `pi_o7_once` and commits:

```
--- A:  INSERT 0 1 / COMMIT
  kind   |  num  | provider_transaction_id
 receipt | O7-R1 | pi_o7_once
 payment | O7-P1 | pi_o7_once
```

Control: the same race at READ COMMITTED is refused: `ERROR: provider transaction pi_o7_rc from stripe_webhook is already recorded as a receipt or a payment`. The opposite order (a committed receipt, then a payment at REPEATABLE READ) has the same shape (predicted).

**Fix:** call `suspense_require_read_committed('a provider transaction')` inside `check_provider_transaction_once`, after its early return for a missing id or a refund. Add a two-session race at REPEATABLE READ (SU5c) and a mutation that removes the pin.

---

## S — should fix

### S1. The invariant checks no constraint, so the new CHECKs and unique indexes can be dropped unseen (executed)

`assert_suspense_pledge_guard_invariants` checks trigger definitions, policies, grants, the tenant keys between tables and two function grants. It checks no constraint or index. -27's `assert_shortfall_guard_invariants` set the precedent here: it lists its constraints exactly (`c_constraints`, matched with `pg_get_constraintdef`). Several of -24's rules are only CHECKs or unique indexes. Probe, as the owner: I dropped `payments_agency_check`, `payments_suspense_resolution_check`, `payments_agency_pledge_check`, `tenants_suspense_days_check`, `agency_pledge_events_one_per_pledge` (the "ended once" rule), `suspense_receipt_dispositions_undo_check`, `agency_pledges_pay_by_check`, and the unique indexes `suspense_receipts_provider_transaction_once` and `assistance_agency_agreements_one_per_date`:

```
NOTICE:  O2 assert_suspense_pledge_guard_invariants after dropping 7 CHECKs/uniques and 2 unique indexes => ACCEPTED
NOTICE:  O2b every earlier invariant too => ACCEPTED
NOTICE:  O2c invariant after the cap body is replaced by RETURN => ACCEPTED
```

The comment claims "every v5.4.2-24 guard exists exactly as defined". That claim is wider than the check (lesson `checks-narrower-than-their-claim`). **Fix:** add a `c_constraints` list in -27's form: every CHECK, key and unique constraint on the seven tables, the three new CHECKs on `payments`, and `tenants_suspense_days_check`. Check the two partial unique indexes by `pg_get_indexdef`. Add APPLY mutations that drop one of each. Function bodies are not checked either, as in -27; note it, but it does not have to be fixed here.

### S2. The settings readers trust values the app writes straight into the history table (executed)

The readers take the setting from `tenant_configuration_history`, but the value CHECK is on `tenants` only. `tally_app` holds INSERT on the history table and may write `change_source = 'manual'` rows itself. The reader takes whatever number the latest row holds:

```
NOTICE:  O3a tally_app writes a manual history row: level -5 => ACCEPTED
 level now             | -5
 tenants.settings says | 10
NOTICE:  O3b tally_app writes level 1000000 (silences every aged receipt) => ACCEPTED
 aged on 2026-12-31 with level 1000000 | 0
NOTICE:  O3c tally_app writes a backdated row (effective a year ago) => ACCEPTED
NOTICE:  O3d level 10.5 => ACCEPTED
NOTICE:  O3e reader after 10.5 => REFUSED 22P02 (invalid input syntax for type integer: "10.5")
```

A level of 1,000,000 hides every aged receipt with no error. That is the opposite of CI-056's "fail loud", and it gets around the 1–99999 rule that `tenants` enforces. -22 set the precedent for its own key with a CHECK on the history table (`tenant_configuration_history_aging_days_check` calls `aging_bucket_days_json_valid(new_value)`). **Fix (cheapest):** in `suspense_setting_days_as_of`, raise unless `suspense_days_setting_valid(v_val)` holds and the value is not null. Alternatively, add a history CHECK in -22's form, if the invariants that list the history table's constraints allow one more. The back-dated `effective_from` (O3c) applies to every setting, -22's included. Note it, but it is not -24's to fix.

### S3. Ryan's 11-07 rule ("for every agency") has gaps the patch does not name (executed and predicted)

`cash_money_agency` follows three kinds of credit: overpayment, refund reissue and shortfall reissue. Money reaches the customer by two other routes the database cannot trace:
- **An agency pays a deposit** (executed): `O5 an agency pays a deposit => ACCEPTED` (`payer_class = 'agency'`, `is_deposit = true`). Its return goes back by -15's events, to the customer. That is known limit L5.
- **A transfer, adjustment or "other" credit** (predicted). Nothing on such a credit can name its source: the columns are `source_payment_id` (overpayment only), `source_adhoc_charge_id`, `source_invoice_id`, `reissues_refund_id`, `reissues_shortfall_application_id` and `source_reference`. Probe: a `transfer` credit traces to `the customer (NULL)`. If an agency's overpayment credit moves to a new account when a customer moves, the trace is lost, and a refund of it goes to the customer without complaint.

The rule's own words are "for every agency", so it does not admit an unstated gap. **Fix:** either (i) state both routes as known limits next to L5, with a contract on what the app must do (refund a deposit from agency money by a refund payment that names the agency; never move agency money by a transfer credit), or (ii) close them: refuse `is_deposit` on an agency's payment until L5 is routed, and require a transfer credit to name the credit it came from. Option (ii) touches -23's table. The choice decides where the money ends up, so ask Ryan only if (i) is not acceptable.

### S4. Missing tests (executed: grep and the mutation list)

- No battery case or mutation follows the shortfall reissue trace (`grep -i shortfall battery-24` finds nothing). M58 and M59 cover only the overpayment and refund reissue routes.
- No test reaches `cash_money_agency`'s 1,000-step bound (`program_limit_exceeded`).
- B1, B2 and B3 each need their own test. M15 pins B1's behaviour as correct.
- S1: no APPLY mutation drops a constraint.

---

## N — notes

- **N1 (executed).** A retired agency's name cannot be used again. `O4 record a new one with the same name => REFUSED 23505 assistance_agencies_tenant_name_key`, yet the retirement message says "record a new one". Either make the unique index partial (`WHERE status = 'active'`) or change the message.
- **N2 (executed).** A superuser load with `session_replication_role = replica` turns off foreign keys. `enforce_agency_pledge` checks the agency's tenant but not the customer's, so `O11 a pledge of T1 for a T2 customer => ACCEPTED`. The payment trigger checks both the receipt's tenant and the pledge's. Adding `AND EXISTS customer in NEW.tenant_id` costs one line. Otherwise state that a history load runs with foreign keys on.
- **N3 (executed).** COPY and writable CTEs are safe. COPY as `tally_app` fails, because RLS forbids COPY FROM. COPY as the owner of two 60s from a receipt of 100 is refused at the cap ("on 2026-03-02 … 120.00, more than the 100.00"). A CTE that inserts a disposition of 60 and a payment of 60 is refused at the cap ("on 2026-03-03 … 120.00"). The AFTER triggers see both parts.
- **N4 (predicted).** A multi-row insert over two receipts or pledges takes their advisory locks in row order. Two such statements in opposite orders deadlock (40P01). The header's lock-order rule should say "every writer retries 40P01", as -22 and -23 do (lesson `lock-order-as-a-rule`), rather than list shapes.
- **N5 (read).** The new payment triggers sit beside -23's without changing them. `enforce_payment_suspense_pledge` never assigns to NEW; it only refuses, so the order it fires in among -23's BEFORE triggers changes which error message appears, not the outcome. The cap's AFTER trigger only reads. One effect on -23 remains: B2's disagreement with -23's money-date reading.
- **N6 (read).** The pledges are sound as far as I could check. The state order (void, paid, event from its date, no agreement, overdue, open) matches the design. The pledge lock is taken before every read on both the payment side and the event side, and both are pinned to READ COMMITTED. A lapse waits until pay_by has passed in the latest time zone (UTC-12). `STABLE` callees inherit the snapshot of the VOLATILE caller's statement, which is taken after the lock, so the reads under the lock are fresh.
- **N7 (read).** `suspense_resolved_by` is any user of the tenant. Nothing ties it to `app.user_id`. This is the same as `recorded_by` elsewhere.
- **N8 (judgement).** The known limits: L1 and L3 are fine. L2 fails toward protection: -26 cannot evaluate the condition, so it blocks. L4 is fine once B2 is fixed (as it stands, the figure is wrong between a payment and its reversal). L5 is part of S3.
