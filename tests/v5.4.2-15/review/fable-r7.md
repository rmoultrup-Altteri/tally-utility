# Review r7 — v5.4.2-15 rewrite — Fable (delta on round 6)

Date: 2026-10-13. Artefacts: `patch-15r-frozen-r7.sql` md5 `44a4d2b1a6cbe135c6744c40331bf1f9` (matches; byte-identical to `sql/v5.4.2-15-deposits-law-to-core.sql`), `battery-15r-frozen-r7.sql` md5 `ebe98c8751838d53031ecf020eac8ba8` (matches; identical to `tests/v5.4.2-15/battery-15r.sql`).

How I probed: `diff r6 r7` of patch and battery read whole (patch: `v_closed`/`v_notice` read from events, five status reads replaced, N1 fence; battery: `ev2_sql` and I17–I24); clone `fable17` (TEMPLATE `tally`, TEMP revoked), strict apply clean; battery 352 PASS, exit 0; M171–M174 through `mutations-15r.py`, all four caught at I24/I17/I21/I19; the hunt below with one probe set spliced before V28 (`fable-r7-probes.sql` beside this file). Clone dropped; `tally` and `postgres` untouched.

## Verdict: READY — with one should-fix (S1) of the same class as Opus's B1, lower consequence

The delta is right: `v_closed` and `v_notice` are read by SPI inside the BEFORE ROW trigger, which sees rows an earlier row of the same statement inserted (the battery's I17/I21/I22 prove it), while `d.status` was the pre-statement projection. Every status read in `enforce_deposit_event` is gone; N1 (`refunded`/`released` not before its notice) closes my r6 observation F3e; I24 pins the widened refund-date rule (my r6 S1), and M171 shows the battery now catches the narrowing. The projection itself is unchanged and still the only writer of `status` / `refunded_on` / `released_on`.

## The hunt: other BEFORE ROW reads of a projected column
I grepped the patch and the still-live -06 functions for `status`, `refunded_on`, `released_on`, `deposit_status`, `customers.deposit_*`:
- `enforce_deposit_event` — none left (`deposit_balance` reads `refunded_on`/`released_on` only for `days_held`, which no check uses).
- `project_deposit_status` — reads `d.status` in the AFTER trigger to carry it; that is the projection, correct.
- `deposits_return_owed` (view, 4880) — filters on `d.status`; a read at query time, consistent.
- `enforce_customer_lifecycle` (-06, line 313, BEFORE UPDATE on customers) — refuses a close while a deposit's status is open. Lags the same way, but **fail-closed**: a refund event and the close in one statement would be refused where a second statement would accept; nothing opens a deposit that the status says is closed. Not a hole.
- **`enforce_deposit_return_due_record` (patch 4674, BEFORE INSERT on `deposit_return_due`) — reads `d.status IN ('refund_pending','refunded','released')` for "no return has started". This one lags and is reachable → S1.**

## S1 (should fix): a refund notice and a due row in ONE statement bypass "no return has started"
On deposit `rtar` (T2, principal 60, two withdrawn due rows, none live), as `tally_app`/u2:
- G1a control, two statements: the notice (`refund_initiated` 60 on 2 Nov) is accepted, then the due row is refused "already refund_pending — its return has started". Right.
- G1b, one statement `WITH e AS (INSERT INTO deposit_events … refund_initiated …) INSERT INTO deposit_return_due … FROM e`: **ACCEPTED**. Afterwards status is `refund_pending`, the deposit's due rows went 2 → 3, and the new row is live.
- G1e, the same with the evidence row chained in a third CTE (constraints immediate): **ACCEPTED** as a complete record — a live due row on a refund-pending deposit, which `deposits_return_owed` hides only because its own filter reads the status later.
Consequence: a stray live due row beside a refund already noticed (no money moves; the `refunded` event may cite and settle it, or it sits live for a deposit that then closes). It is the same lag Opus's B1 named, in the sibling trigger that shares the deposit-row mutex, and the fix is the same shape: read "started" from `deposit_events` (a `refund_initiated` / `refunded` / `released` event exists) instead of `d.status`, add a check in `ev2_sql`'s shape (notice + due row in one statement, refused "return has started") and a mutation that puts the status read back. I rate it should-fix, not blocking, because no money or law outcome changes; if it is fixed in the patch that is a round-8 revision I would re-check from the diff in minutes.

## Notes
- The r7 brief's new decision ("pending" = a `refund_initiated` event exists; no cancel in this ledger) is consistent with everything the triggers now read; I have no objection.
- F5i (zero refund closes a deposit with instalments scheduled and unpaid) left to the core: fine by me.
- Decision 1: unchanged — Ryan's one line at mirror time.
