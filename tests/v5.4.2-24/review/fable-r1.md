# Fable review — v5.4.2-24 r1 (unmatched cash and agency pledges)

**Date:** 2026-11-07. **Reviewer:** Fable (claude-fable-5-1). **Brief:** `review-brief-24-r1.md` (md5 `1b3598dba62efb34e0be331cb32e6a0f`, matched).

**Frozen hashes checked, all matched:** patch `eae62ab0…`, battery `e2c82852…`, races `bb428ea6…`, mutations `2e5cd766…`, ci diff `c343828b…`.

**Verdict: not yet.** One rule the patch claims — a provider's transaction id is money recorded once, across receipts and payments — has two ways around it (B1, B2). Both are small to close. Everything else I probed held, including the receipt's cap under multi-row inserts, writable CTEs and COPY, the pledge rules, the refund routing through -23's and -27's lineage, tenancy, and the races.

**Scratch database:** `rv24fable` (TEMPLATE `tally`, TEMP revoked from PUBLIC, `tally_app`, `tally_core`; frozen patch applied strictly twice; dropped at the end). I did not run `ci.sh` or `mutations-24.py`, and created, dropped or altered no role. I did not read `opus-*.md` or `codex-*.md`.

## Reproduced (executed)

- Strict apply (`search_path=''`, `check_function_bodies=on`): clean; second run skipped by the marker (`v5.4.2-24: already applied (suspense_receipts exists)`).
- `battery-24-frozen-r1.sql` on the clone with `COMMIT` in place of the final `ROLLBACK` (to leave a committed state to probe): **188 PASS**, no FAIL.
- `suspense-24-frozen-r1.sh rv24fable`: **12 PASS** (SU1–SU7), every B leg seen blocked by A.

## B — blocking

### B1. The "one provider transaction across receipts and payments" check is defeated under REPEATABLE READ, in both directions — **executed**

What it does: the same provider transaction (say a Stripe charge) can be held twice as money — once as an unmatched receipt and once as a customer's payment — whenever the writer's transaction is REPEATABLE READ. `check_provider_transaction_once` takes an advisory lock on the id and then counts the other table, but neither caller pins READ COMMITTED: `enforce_suspense_receipt` (receipt insert) never calls `suspense_require_read_committed`, and the payment INSERT path of `enforce_payment_suspense_pledge` calls it only when the payment names a receipt or a pledge. A REPEATABLE READ snapshot taken before the other row committed never sees it, lock or no lock (lesson `count-guards-need-lock-handshake`; the design's own rule in section 8: "every writer that reads under a lock is pinned to READ COMMITTED"). The receipt–receipt and payment–payment duplicates are safe regardless: those are unique indexes.

Evidence (session A is the file; session B is a second `psql` inside the container, committing between A's statements):

```
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT count(*) FROM public.suspense_receipts;                      -- A's snapshot
\! psql ... -c "INSERT INTO public.payments (... source_system, provider_transaction_id ...) VALUES (... 'stripe_webhook', 'FXA' ...)"
INSERT INTO public.suspense_receipts (... 'stripe_webhook', 'FXA' ...);
COMMIT;
-- E1 A: receipt of FXA ACCEPTED under REPEATABLE READ beside the committed payment (hole)
-- E1 after commit: rows holding FXA = receipts 1, payments 1
```

The other direction (B commits a receipt of `FXB`, A under REPEATABLE READ inserts a payment of `FXB`): `E2 A: payment of FXB ACCEPTED … rows holding FXB = receipts 1, payments 1`. As `tally_app` with `app.user_id` set (E1b, receipt side): `ACCEPTED`. Control under READ COMMITTED (E2c, payment side): `ERROR: provider transaction FXC from stripe_webhook is already recorded as a receipt or a payment: money is recorded once (CI-055, v5.4.2-24)`.

Fix: call `suspense_require_read_committed` inside `check_provider_transaction_once` after the early return (so it binds only when there is a transaction id and money in), from both callers. That extends the isolation contract to any payment insert carrying a provider id; the design already pins the receipt's payment and the pledge's payment, so the contract line in the header and in AC should say "a payment or receipt carrying a provider transaction id is written at READ COMMITTED". Add a race (SU5c/SU5d: the same as SU5/SU5b with session B under REPEATABLE READ, expecting 25000) and a mutation that drops the pin.

### B2. A payment's provider transaction id written later by UPDATE is not checked against receipts — **executed**

What it does: -23 lists `provider_transaction_id` among the write-once-later columns of `payments` (`enforce_payment_immutable`, `c_once`: "a reference that arrives later … is written once"). -24 checks a payment's id against receipts only in the INSERT path of `enforce_payment_suspense_pledge`; the UPDATE path checks the five new columns and `effective_date` only. So a payment recorded without its settlement id, then given one that a receipt already holds, is accepted under READ COMMITTED by `tally_app` — the same money held twice. (-19's unique index still refuses a payment–payment duplicate; `payments_suspense_resolution_check` still refuses the id on a payment that itself came from a receipt.)

Evidence (as `tally_app`, READ COMMITTED; receipt `R24-FXC` holds `FXC`):

```
INSERT INTO public.payments (... source_system ...) VALUES (... 'stripe_webhook' ...);   -- no provider id
UPDATE public.payments SET provider_transaction_id = 'FXC' WHERE id = '…fab40';
-- E40 UPDATE later writes a receipt's transaction id onto a payment: ACCEPTED (hole)
-- E40 rows holding FXC now: receipts 1, payments 1
```

Fix: in the UPDATE branch, when `NEW.provider_transaction_id IS DISTINCT FROM OLD.provider_transaction_id`, run `check_provider_transaction_once(NEW.tenant_id, NEW.source_system, NEW.provider_transaction_id, NEW.amount, NEW.id, false)` (with B1's pin inside it). Battery: a U8f that records a payment without an id and then writes a receipt's id onto it, expecting the CI-055 refusal; a mutation that removes the UPDATE-path call.

## S — should fix

### S1. The invariant does not guard the three payments CHECKs, the receipts' provider index, or the tenants settings CHECK — **executed**

What it does: `assert_suspense_pledge_guard_invariants()` pins the triggers, policies, grants and keys, but not the constraints that carry three of the patch's rules: `payments_agency_check` (an agency's payment names its agency — which `cash_money_agency` and so the whole refund-routing rule stand on), `payments_agency_pledge_check`, `payments_suspense_resolution_check` (a receipt's payment carries no provider id of its own and is not a refund), the unique index `suspense_receipts_provider_transaction_once`, and `tenants_suspense_days_check`. -23's `assert_cash_guard_invariants()` does not see them either. A superuser dropping any of them leaves CI clean. The invariant's comment does not claim them, so this is a gap rather than a narrower-than-claim check — but the refund rule silently degrades to "refund to the customer" once `payments_agency_check` is gone.

Evidence:

```
ALTER TABLE public.payments DROP CONSTRAINT payments_agency_check;
ALTER TABLE public.payments DROP CONSTRAINT payments_suspense_resolution_check;
ALTER TABLE public.payments DROP CONSTRAINT payments_agency_pledge_check;
DROP INDEX public.suspense_receipts_provider_transaction_once;
ALTER TABLE public.tenants DROP CONSTRAINT tenants_suspense_days_check;
SELECT public.assert_suspense_pledge_guard_invariants();   -- E6: PASSES
SELECT public.assert_cash_guard_invariants();              -- E6b: PASSES too
-- then as tally_app:
INSERT INTO public.payments (... payer_class, agency_id) VALUES (... 'agency', NULL);
-- E6c: agency payment naming no agency: ACCEPTED once the CHECK is gone
```

Fix: add the five definitions (as `pg_get_constraintdef` / `pg_get_indexdef` print them) to the invariant, the way -23 pins its constraint text; battery I8 drops one and expects the raise.

### S2. Credits of an origin the trace cannot follow are refunded as the customer's own; the limit is not stated — **executed**

What it does: `cash_money_agency` follows `overpayment`, `refund_reissue` and `shortfall_reissue`. A credit of origin `transfer`, `deposit_refund`, `adjustment`, `dispute_resolution`, `regulatory_rebate` or `other` has no source link, so the trace answers NULL (the customer's) and the refund is paid to the customer with no agency named. A transfer credit carrying what an agency paid on a closed account, or a deposit-refund credit of an agency-paid deposit, is exactly 10 TAC §6.312(f)'s case. The database cannot know; the point is that the design's known limits (section 6) name only the deposit's own return (L5), and the function's comment reads as if the trace were complete.

Evidence:

```
INSERT INTO public.customer_credits (... origin_type ...) VALUES (... 'transfer', 5 ...);  -- plus its credit_issued entry
SELECT public.cash_money_agency(NULL, '…fab14');                 -- NULL (customer)
INSERT INTO public.payments (... -5, 'refund', refunds_customer_credit_id => '…fab14', agency_id => NULL);
-- E14: refund of a transfer credit to the customer: ACCEPTED
```

Fix: a known limit L6 in the design and the patch header ("a credit with no recorded source — transfer, deposit_refund, adjustment, other — is refunded as the customer's; the core routes an agency's money in those by its own record"), and the same sentence in `cash_money_agency`'s comment. If a transfer credit later gains a source link (the credit it was transferred from), the trace should follow it.

## N — notes

- **N1 (executed).** The receipt's cap holds in every statement shape I tried: a two-row INSERT of 60+60 on a 100 receipt (E3), a writable CTE with a 60 payment and a 60 return in one statement (E4), and `COPY … FROM STDIN` of two 60 payments (E31) are each refused at `23514` with the cap's message. The AFTER INSERT placement does what the lesson asks.
- **N2 (predicted, from -23's code).** A status move cannot push a receipt over its cap: `enforce_payment_immutable` is forward-only (pending → posted or voided; posted → nsf or reversed; nsf, reversed and voided terminal), and `amount` and `payment_date` are in its fixed list. So the only move that changes the cap (posted → reversed) lowers it. "Reversed gives back, NSF does not" holds for the one way a payment reaches `reversed`; a return code on a reversed row does not change that.
- **N3 (executed).** Lock order as built matches the header: on `payments` the BEFORE triggers sort `a_enforce_accounting_freeze`, `a_enforce_cash_birth`, `a_enforce_payment_lineage` (-23's locks) before `enforce_payment_suspense_pledge` (the transaction-id and pledge locks), and the AFTER triggers `enforce_cash_draw` (-23) before `enforce_payment_suspense_cap` (the receipt). No -24 writer takes a -23 lock after a -24 one, so no cycle through -23. Two multi-row inserts naming two receipts in opposite order can still deadlock on the receipt locks (40P01); -23's cash contract already says every cash writer retries, and the header could say in one line that -24's three lock kinds fall under that rule (lesson `lock-order-as-a-rule`).
- **N4 (executed).** Tenancy: a superuser's payment of tenant T2 from a T1 receipt is refused by the trigger's tenant-scoped read (`23503 … not visible in this tenant`, E33); T2's `tally_app` lapsing a T1 pledge is refused (E34), though the message prints a blank pledge id and the wrong reason ("has no agreement") because the row is invisible — a cosmetic `IF NOT FOUND` after the `SELECT * INTO l` would make it say so.
- **N5 (executed).** A receipt resolved as a deposit payment (`is_deposit = true`) is accepted (E19). That is right, and it is L5's case one step earlier: an agency's unmatched money that becomes a deposit is returned by -15's deposit events, not by a refund the database routes. Worth a clause in L5.
- **N6 (executed).** A refund of a refund is stopped by -23 (`check_cash_source`: money is drawn from a posted payment, and a refund is pending here, E5b); with the wrong agency it was -24's rule that fired first (E5). Nothing to do.
- **N7 (predicted).** `assistance_agencies` is unique on `(tenant_id, name)` with no status filter, so a retired agency's name cannot be used for its successor ("record a new one" needs a new name). Either intend that (the name is the key) or filter the index on `status = 'active'`.
- **N8 (predicted).** A pledge recorded with no agreement on file can never gain one (the row is add-only, and the agreement is chosen at insert): it stays `no_agreement`, cannot lapse, and can only be withdrawn, or recorded in error while nothing names it. The message on a lapse ("record its agreement, or withdraw it") suggests the first is possible for that pledge; it is possible only for a new pledge.
- **N9 (executed).** `tenant_configuration_history_key_known_check` admits any `settings.%` key, and `record_tenant_configuration_change` writes one row per settings key, so the two new keys reach the history without touching the known-key list, as section 8 says. Executed through battery S2/S2b.
- **N10 (read).** The battery's boundary checks are pinned to concrete dates on both sides (L1b/L1d pay_by 04-24/04-25, S3 10/11 days, S3c 09-16/09-17, L13b, L11b/L11e), and the cap's worst-day check (X7/X7b) measures the netted undo, not the formula. Mutation names match the first-failing check for the ones I traced (M13–M16, M31–M33, M56–M59). Missing after B1/B2: a race for the provider check under REPEATABLE READ, a battery check for the UPDATE-path provider check, and an invariant check for the constraints in S1.
- **N11.** Known limits L1–L5: none blocking. L4 (no suspense line in the close snapshot) is right to defer; `suspense_held_as_of` gives the reconciling figure.

## Answers to the brief's questions

1. **Design and rulings.** Implemented: receipts held, candidates as evidence only, payments naming receipts with reason and user, the cap on every date, dispositions with undo, settings with fail-loud readers, agencies and dated agreements, pledges with database-chosen agreement and pay-by, events ending a pledge once, the 11-07 refund rule through -23/-27 lineage, the retired program type. Not fully delivered: "a provider transaction id is held once across receipts and payments" (B1, B2).
2. **Paths around a rule.** Found: the provider id twice (B1 under REPEATABLE READ, B2 by a later UPDATE). Not found: a receipt spent twice (N1), out-of-bounds or cross-tenant receipt payments (N4, battery P4/P11), a database-made guessed application, a pledge paid by another agency or customer or ended twice, an early lapse, a payment naming an error pledge, a refund of agency money to the customer through the traced origins (S2 for the untraced ones), an agency brought back, an agreement edited.
3. **-23 and -27.** -24 changes nothing -23's positions, caps or recorded-order rules read: the new columns are nullable and write-once, the new triggers sort after -23's on both BEFORE and AFTER (N3), and `enforce_payment_suspense_cap` reads under its own lock after `enforce_cash_draw`.
4. **Concurrency.** Lock order followed (N3). Every cap read is under its lock. The provider check is under its lock but not under a READ COMMITTED pin (B1).
5. **Invariants.** Catches what it claims (triggers, plumbing, policies, grants, R-12 keys, the two functions' grants; battery I2–I7 make it raise). Does not claim and does not cover the constraints (S1).
6. **Tests.** Battery 188 and races 12 reproduced; no check weaker than its label among those traced; mutations not run (restricted). Missing tests listed in N10.
7. **L1–L5.** None blocking (N11); L5 slightly wider than stated (N5); an L6 is missing (S2).
