# Fable review — v5.4.2-24 r9 (unmatched cash and agency pledges)

**Date:** 2026-11-22. **Reviewer:** Fable (claude-fable-5-1). **Brief:** `review-brief-24-r9.md` (md5 `a4f09bb6e7cad8e2c4817c8c3d06a6aa`, matched its `.md5`).

**Frozen hashes checked, all matched:** patch `9b00e46b…`, battery `e917ec27…`, races `55c63199…` (unchanged from r6), mutations `18f737f9…`, ci diff `c343828b…` (unchanged from r1), r8-to-r9 `b512ae0b…`. I reviewed the frozen copies only.

**Verdict: not yet.** Every round-8 finding is closed as written and every earlier one still holds (the whole battery, the races and the three new mutations re-ran here). No blocking item. One should-fix, executed, on the round's main addition: the new reader of money waiting on a misposting return reads the share at current knowledge, so at a backdated money date, or at a recorded instant inside a history load, it lists money the customer still holds, or that the receipt still holds, and the brief's own test ("does receipt money plus money due back ever count a dollar twice or drop one?") fails on the battery's own fixtures. The fix is the same shape as the one already applied to the return in round 6: read the tree at the coordinates. SQL, checks and mutations below, all executed against the clone.

**Scratch database:** `rv24fable` (TEMPLATE `tally`; TEMP revoked from PUBLIC, `tally_app`, `tally_core` right after creation; frozen r9 patch applied strictly twice; the battery; my probes spliced into a copy of the battery and rolled back with it; the races; the three new mutations applied by hand to the clone's reader and reverted; dropped at the end). I did not run `ci.sh` or `mutations-24.py`; created, dropped or altered no role; read no `opus-*` or `codex-*` file. Two `crystaldba/postgres-mcp` containers were running at my start; I did not touch them.

## Reproduced (executed)

- Strict apply (`search_path=''`, `check_function_bodies=on`): clean; the second run is skipped by its marker ("already applied (suspense_receipts exists)").
- `battery-24-frozen-r9.sql`: **282 PASS**, 0 FAIL (rolled back). The six re-aimed guard strings (P9b3b, P13, P14b, P14c, P14e, P14f) pass with the share in the message; S8–S8e pass.
- `suspense-24-frozen-r9.sh rv24fable`: **24 PASS**.
- `assert_suspense_pledge_guard_invariants()` on the clone: clean after the battery, after the races, and after the mutations were reverted. The two new bodies and the new `enforce_suspense_disposition` body hash to the pinned values (the invariant checks them; it passed).
- **M117, M118, M119 by hand** (the mutation's exact text applied to the clone's reader, battery run, body restored): first failure `FAIL S8b`, `FAIL S8c`, `FAIL S8d` respectively, each at the check the runner names. Caught for the right reason.
- Trigger order on `payments` unchanged from r8 (-23's `a_*` first, then `enforce_cash_draw`, `enforce_escheated_credit_settled`, `enforce_payment_effective_date`, `enforce_payment_immutable`, `enforce_payment_suspense_cap`, `enforce_payment_suspense_pledge`, `enforce_shortfall_source_moves`; all ENABLE ALWAYS but `set_updated_at`).
- The reader runs as `tally_app` and as `tally_core` (probe FA: both list R23's payment; grants are right), refuses an infinite or NULL coordinate (FC: 22004 from `cash_coordinates_required`), and lists none of T1's payments for T2 (FT).

## Round-8 findings — closed as written (executed)

- **Opus r8 S1 — money waiting on a return showed up nowhere.** `suspense_misposted_share` is the guard's walk moved verbatim (I diffed the two: the same CTE, the same nsf exclusion, the same `least/greatest` bound, the same three plan pins), and the guard calls it. `suspense_misposting_returns_due_as_of` lists R23's payment b3 (reversed 03-11, share 100, never returned) with 100 owed, 224 days past a 10-day level (S8), leaves out a returned payment (S8b), one with no share (S8c) and one read before its reversal's date (S8d). FR enumerated every reversed payment of T1 made from a receipt: of 14, one has a return code (not listed), ten were returned (not listed), two have share 0 (not listed), and b3 alone is listed. FL: R23 holds 0 and the reader owes 100, so the receipt's 100 is accounted for at 12-31; the tenant holds 1000 and is owed 100. Closed as the plan states it. The should-fix below is about what the same reader says at other coordinates.
- **Opus r8 S2 / my r8 N1 — the "at most" wording.** The table comment (patch line 449), the guard's inline comment (line 979) and design section 2.3 (line 202) now say exactly the share. Closed.
- **My r8 S1 — refusals pinned to the share.** The six guard strings are my SQL verbatim; all pass; with M115 the share in the message is now pinned too. Closed.

Rounds 1–7 (my r1 B1, B2, S1, S2; r2 B1, S1; r3 B1, S1; r4 B1; r5 S1, S2; r6 S1 = S4b; r7 and r8 as above; and the brief's list for Opus's and Codex's) are still closed by the same battery checks, which all ran again here.

## S — should fix

### S1 (executed). The returns-due reader counts a dollar twice at some coordinates and drops it at others, because it reads the share at current knowledge and lists by the status row's date alone.

**What it does to the figure.** The plan says a reconciliation adds `suspense_held_as_of` and this reader's owed. On the battery's own data that sum is wrong by a full payment at coordinates the battery itself builds:

- *A reversal, its undo, a second reversal* (R23/b3 from my r5 probe, and R24/7b from Codex's r5 probe). On 2026-03-12 the undo stands: the customer's ledger holds the 100 again (`payment_position_as_of` received = 100), the receipt holds 0, and the reader says 100 owed (its share is the tree's final net, 100, and the status row is dated 03-11). FD1: owed 100.00, on the customer 100.00, the receipt 0.00. One receipt, counted twice, for a whole day, at a read taken now.
- *A payment posted before it is dated* (R20/payment 20: posted 03-10, dated 03-15, reversed 03-11, returned 03-15; Opus r4 S1's fixture). On 03-11 to 03-14 the receipt still holds the 100 (the payment is not dated yet) and the reader also lists 100 owed. FX: listed, R20 held 100.00. Sixteen coordinate pairs.
- *A tree row recorded at a chosen later time* (R9a/9b, the P14i fixture: the reversal row stamped `clock_timestamp()`, the status at the transaction's start). At the status instant the reader lists 100 owed while the customer's ledger, read at that instant, still holds the 100 (FI1: `listed_at_status_instant = t`, `on_customer_then = 100.00`). Twenty-one pairs.

FD5, the S4b conservation sweep with the reader's owed added as a fourth term, finds four receipts exceeding their amount at some coordinate, each by 100.00 (R20 16 pairs, R23 4, R24 4, R9a 21). Today's S4b does not see it because it does not add owed.

The round-6 fix for the return (Codex r6 B1, "on a date before a later row of the tree the payment still held money the return would give back, so one receipt counted twice"; and the recorded-order rule) is exactly this rule; the reader was built without it. Not blocking: no write reads this function, -26's conditions read the aged receipts, and a read dated today of a single-reversal payment (the ordinary case) is right. But the function exists to give the figure at coordinates, and at the coordinates its own battery builds it is wrong by the whole share.

**What to do (rule: CI-053 and the -22 model, every reader as-of at both coordinates).** Read the share at the coordinates. Two shapes tried, both executed over the full S4b grid (105 to 150 coordinate pairs per receipt):

- *Tree-extent rule* (list only once every tree row is dated by `p_on` and recorded by `p_recorded_at`, like the return's guard): no double anywhere (FD5v2 empty, FD2v2 0 of 105 listings), but it **drops** money: on 03-11 b3's reversal stands, the customer holds nothing, the receipt holds nothing, and nothing lists it until 03-13 (FD4v2: seven payment-dates in the battery, b3, 7b, 1c, 1d, 1e on 03-11, d1 on 03-12, d7 on 03-14). Not recommended.
- *As-of share* (recommended): the same walk with every row held to `transaction_date <= p_on AND created_at <= p_recorded_at`; list while the as-of share is above 0, the payment is dated by `p_on`, exists and is reversed by `p_recorded_at`, and no return is counted at the coordinates. Over the grid: no receipt exceeds its amount (FD5v4 empty); for the four receipts whose payments all are reversed without a code or returned (R20, R23, R24, R9a), held + on the customer's ledger + left to a sender/bank/state + owed **equals** the receipt at every one of 88 coordinate pairs each (FD6v4); b3 is listed on 03-11 and 03-13 with 100 and not on 03-12; 9b is not listed at its status instant; payment 20 is not listed before its own date; d1 (P14e) owes 50 on 03-12, nothing on 03-13 (its undo typed nsf stands) and nothing on 03-14 (returned); S8, S8b, S8c, S8d still pass (FXv4, nine of nine).

The status row's own date no longer filters (d1's status names the *second* reversal, dated 03-14, while 50 was owed from 03-12); it is still reported as `reversed_on` and the age is counted from it. Whether the age should instead run from the first date the as-of share was above 0 is the author's call; CI-056 only needs it loud.

```sql
-- The share at the coordinates: the guard's walk, every row held to the money date and the recorded instant.
-- Same plan pins as suspense_misposted_share; a new overload, additive; pinned in the invariant's body,
-- settings and grant lists (the guard does not call it, so not in c_app_exec).
CREATE OR REPLACE FUNCTION public.suspense_misposted_share(p_payment_id uuid, p_on date, p_recorded_at timestamp with time zone) RETURNS numeric
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    SET enable_seqscan = off
    SET enable_hashjoin = off
    SET enable_mergejoin = off
    AS $$
DECLARE
    v_amount numeric;
    v_share  numeric;
BEGIN
    SELECT p.amount INTO v_amount FROM public.payments p WHERE p.id = p_payment_id;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;
    WITH RECURSIVE e AS (
        SELECT l.id FROM public.account_ledger l
         WHERE l.reference_type = 'payment' AND l.reference_id = p_payment_id AND l.reverses_ledger_entry_id IS NULL
           AND l.transaction_type IN ('payment', 'deposit') AND l.transaction_date <= p_on AND l.created_at <= p_recorded_at
    ), down(id, amount) AS (
        SELECT l.id, l.amount FROM e JOIN public.account_ledger l ON l.reverses_ledger_entry_id = e.id AND NOT (l.transaction_type = 'nsf' AND l.amount > 0)
         WHERE l.transaction_date <= p_on AND l.created_at <= p_recorded_at
        UNION ALL
        SELECT l.id, l.amount FROM down d JOIN public.account_ledger l ON l.reverses_ledger_entry_id = d.id AND NOT (l.transaction_type = 'nsf' AND l.amount > 0)
         WHERE l.transaction_date <= p_on AND l.created_at <= p_recorded_at
    )
    SELECT least(v_amount, greatest(0, coalesce(sum(d.amount), 0))) INTO v_share FROM down d;
    RETURN v_share;
END;
$$;

-- The reader: the as-of share decides; the status row dates the listing, not the filter.
CREATE OR REPLACE FUNCTION public.suspense_misposting_returns_due_as_of(p_tenant_id uuid, p_on date, p_recorded_at timestamp with time zone)
    RETURNS TABLE (payment_id uuid, receipt_id uuid, customer_id uuid, owed numeric, reversed_on date, age_days integer,
                   service_level_days integer, past_service_level boolean)
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_level integer;
BEGIN
    PERFORM public.cash_coordinates_required('suspense_misposting_returns_due_as_of', p_on, p_recorded_at);
    v_level := public.suspense_service_level_days_as_of(p_tenant_id, p_recorded_at);
    RETURN QUERY
    SELECT p.id, p.suspense_receipt_id, p.customer_id, s.owed::numeric(12,2), l.transaction_date, (p_on - l.transaction_date)::integer, v_level,
           CASE WHEN v_level IS NULL THEN NULL ELSE (p_on - l.transaction_date) > v_level END
      FROM public.payments p
      JOIN public.account_ledger l ON l.id = p.status_cause_id
      CROSS JOIN LATERAL (SELECT public.suspense_misposted_share(p.id, p_on, p_recorded_at) AS owed) s
     WHERE p.tenant_id = p_tenant_id AND p.suspense_receipt_id IS NOT NULL
       AND p.status = 'reversed' AND p.return_code IS NULL
       AND p.created_at <= p_recorded_at AND p.status_recorded_at <= p_recorded_at
       AND p.payment_date <= p_on
       AND s.owed > 0
       AND NOT EXISTS (SELECT 1 FROM public.suspense_receipt_dispositions d
                        WHERE d.returned_payment_id = p.id AND d.disposed_on <= p_on AND d.created_at <= p_recorded_at)
     ORDER BY l.transaction_date, p.id;
END;
$$;
```

Checks (all executed against this body, inside the battery's transaction, as `pg_temp` functions; they fail or are undefined against the frozen reader as noted):

```sql
-- S8f: fails today (the frozen reader lists b3 on 03-12 with 100 owed while the customer holds the 100).
SELECT pg_temp.ok('S8f a payment is not listed on a date its undo stands and the customer holds the money again (b3 on 03-12)',
  NOT EXISTS (SELECT 1 FROM public.suspense_misposting_returns_due_as_of(pg_temp.t1(), DATE '2026-03-12', clock_timestamp()) x WHERE x.payment_id = pg_temp.k('b3')));
SELECT pg_temp.ok('S8g and is listed with 100 on 03-11 (the first reversal) and 03-13 (the second)',
  (SELECT count(*) = 2 FROM (VALUES (DATE '2026-03-11'), (DATE '2026-03-13')) v(d)
     CROSS JOIN LATERAL public.suspense_misposting_returns_due_as_of(pg_temp.t1(), v.d, clock_timestamp()) x
    WHERE x.payment_id = pg_temp.k('b3') AND x.owed = 100));
-- S8h: fails today (listed at the status instant, before its reversal row was recorded; P14i's shape).
SELECT pg_temp.ok('S8h not listed at an instant before a row of its tree was recorded (9b at its status instant)',
  NOT EXISTS (SELECT 1 FROM public.suspense_misposting_returns_due_as_of(pg_temp.t1(), DATE '2026-12-31',
                 (SELECT status_recorded_at FROM public.payments WHERE id = pg_temp.k('9b'))) x WHERE x.payment_id = pg_temp.k('9b')));
-- S8i: fails today (listed on 03-14 while R20 still holds the 100: the payment is dated 03-15).
SELECT pg_temp.ok('S8i not listed before the payment''s own date (payment 20, posted 03-10, dated 03-15)',
  NOT EXISTS (SELECT 1 FROM public.suspense_misposting_returns_due_as_of(pg_temp.t1(), DATE '2026-03-14', clock_timestamp()) x WHERE x.payment_id = pg_temp.k('20')));
SELECT pg_temp.ok('S8j the as-of share: d1 (P14e) owes 50 on 03-12, nothing on 03-13 (its undo typed nsf stands), nothing on 03-14 (returned)',
  (SELECT owed = 50 FROM public.suspense_misposting_returns_due_as_of(pg_temp.t1(), DATE '2026-03-12', clock_timestamp()) x WHERE x.payment_id = pg_temp.k('d1'))
  AND NOT EXISTS (SELECT 1 FROM public.suspense_misposting_returns_due_as_of(pg_temp.t1(), DATE '2026-03-13', clock_timestamp()) x WHERE x.payment_id = pg_temp.k('d1'))
  AND NOT EXISTS (SELECT 1 FROM public.suspense_misposting_returns_due_as_of(pg_temp.t1(), DATE '2026-03-14', clock_timestamp()) x WHERE x.payment_id = pg_temp.k('d1')));
```

And S4b should add the reader's owed as a fourth term, so the conservation sweep covers it from now on (fails today on R20, R23, R24 and R9a; passes with the body above):

```sql
      CROSS JOIN LATERAL (SELECT coalesce(sum(z.owed), 0) AS owed
                            FROM public.suspense_misposting_returns_due_as_of(pg_temp.t1(), ds.d, ats.at) z
                           WHERE z.receipt_id = r.id) w
     WHERE r.tenant_id = pg_temp.t1() AND r.received_on <= ds.d AND r.created_at <= ats.at
       AND h.held + l.on_ledger + o.left_it + w.owed > r.amount));
```

Mutations: M119's anchor (`AND l.transaction_date <= p_on`) disappears; replace it with the as-of share's date bound (drop `AND l.transaction_date <= p_on` from the overload's `e` or `down` → S8f), and add the instant bound (drop `AND l.created_at <= p_recorded_at` → S8h) and the payment's date (drop `AND p.payment_date <= p_on` → S8i). M117 and M118 keep their anchors.

Not blocking, but I would not mirror with the reader as it is: it is the round's reason to exist, and the figure it gives is wrong at coordinates the battery already builds.

## N — notes

- **N1 (executed).** The guard's claim that the tree is fixed once the payment is reversed holds in forward time: after b3's status move, as the owner, a give-back under its second reversal is refused (23001 "gives money back to payment …, which has ended"), an nsf take-back under the reversal row is refused (23514 "a reversal has the opposite sign"), and one under the posting entry is refused (23514 "would come to 200.00, outside 0 to 100.00"). (My first attempt dated these in a closed period and was refused by the freeze instead; the dates above are 2026-05-01.) So S1 is about where the reader reads, not about the share changing.
- **N2 (read).** `suspense_misposted_share` is in `c_app_exec` because the guard calls it as the caller; the as-of overload would be called only by the reader, so it belongs in the body, settings and grant lists but not there.
- **N3 (read).** Same-day reverse and return (payment 14, both 03-05): not listed on 03-04, 03-05 or 03-06, and R4 holds 0 throughout (the receipt's money went on to another customer at P9b7/P9b8). Right.
- **N4 (read).** The reader's `ORDER BY l.transaction_date, p.id` and `age_days` from the status row's date are fine for CI-056's purpose; see S1 for the one open drafting call (which date the age runs from).
- **N5.** Known limits L1–L6: none blocking, as before. L4 (the tenant's held figure until the close carries it) now has the reader beside it; with S1 fixed, held plus owed is exact at every coordinate on the four fixtures where the money's whole path is in the two tables (FD6v4).

## Answers to the brief's questions

1. **Round 8 and earlier.** All three round-8 items are closed as the plan states them (executed); rounds 1–7 still closed. The patch implements the design and the rulings (CI-053, CI-056, Ryan's 11-07 refund rule within L5 and L6); the one gap is S1, where the new reader's figure is not as-of at its coordinates.
2. **Paths around a rule.** None found; the brief's list is held by the rounds 1–8 checks that re-ran here, by the races (24), and by N1 for the tree after the status move.
3. **-23 and -27.** -24 still reads -23's tree by type, sign and link alone and calls none of -23's helpers; r9 moved a walk into a function and added a reader; nothing -23 or -27 reads changes. The `payments` trigger order is unchanged.
4. **Concurrency.** Lock order unchanged (the reader takes none; it is a read); the races reproduce.
5. **Invariants.** Clean on the clone after battery, races and reverted mutations; the three moved or new pins match.
6. **Tests.** Battery 282, races 24, M117–M119 caught by hand at their named checks. What is missing: S4b does not add the reader's owed, and no check reads the reader at a date between a reversal and its undo, before a payment's own date, or at the status instant of P14i's fixture — S8f to S8j and the S4b term above.
7. **L1–L6.** None blocking.
