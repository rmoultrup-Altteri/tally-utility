# Review r8 — v5.4.2-15 rewrite — Fable (delta on round 7)

Date: 2026-10-13. Artefacts: `patch-15r-frozen-r8.sql` md5 `2dc8f61cda3bc6958ca42737d317a629` (matches; byte-identical to `sql/v5.4.2-15-deposits-law-to-core.sql`), `battery-15r-frozen-r8.sql` md5 `8a0c6c4548ab0560ffb0698c13b4da96` (matches; identical to `tests/v5.4.2-15/battery-15r.sql`).

How I probed: `diff r7 r8` of patch (one function, one trigger, ENABLE ALWAYS; nothing else) and battery (`rcte`, V28b–V28d) read whole; clone `fable18` (TEMPLATE `tally`, TEMP revoked), strict apply clean; battery 356 PASS, exit 0; M175/M176 through `mutations-15r.py`, both caught at V28b/V28d; 11 probes spliced before V28b on `rcte` under SAVEPOINTs (`fable-r8-probes.sql` beside this file), 363 PASS, exit 0. Clone dropped; `tally` and `postgres` untouched.

## Verdict: READY — my r7 S1 is closed

The AFTER ROW trigger is the right place: it runs once the whole statement has run, so no ordering of a writable WITH's parts can hide the refund from it; a refund citing the new row is exempted by `return_due_id IS DISTINCT FROM NEW.id` and M176 proves the exemption is pinned. The BEFORE status check stays for its message and is harmless.

## Trying to slip a due row beside a started return (all held)
- H1a: two due rows and a notice citing the first, one statement — refused "already has a live due row" (23505; the second row's BEFORE check sees the first).
- H1b: a due row, a notice citing it, and a second notice not citing it, one statement — refused "a refund is already pending" (the event guard reads events).
- H1c: a due row and a `refunded` (not a notice) that does not cite it, one statement — refused by the new trigger ("has a refunded dated 2026-11-02 that does not cite this due row").
- H1e: due row A, notice citing A, A withdrawn, then B superseding A — refused "already refund_pending" (and the new trigger would refuse it too: the notice cites A, not B).
- V28b/V28c (both orders) are in the battery and pass.

## Legitimate flows (all pass)
- H2a: due row, its evidence, the notice citing it and the refund citing it, all in ONE statement — accepted; status `refunded`.
- H2b: due row A, A withdrawn, B supersedes A, the refund cites B (no notice first), two statements — accepted.
- V27 (notice settles the row in a second statement) and V28d (notice citing the row in the same statement) remain in the battery.
- A partial due row settled by `principal_returned` is untouched: the trigger lists only `refund_initiated` / `refunded` / `released`.

## Observations (pre-existing, not against this round)
- H1d: the other order in two statements — a live due row, then a refund notice that does NOT cite it — is accepted; the row stays live (hidden from `deposits_return_owed` only by its status filter) and the refund may cite it afterwards (H1d-3). The new trigger's invariant is enforced on the due-row side only; whether a refund of a deposit with a live due row must cite it is a core convention, not a lag. I would not hold the mirror for it.
- H1e-3: a due row already cited by a refund notice may still be withdrawn (the notice then cites a withdrawn row). V21 refuses the reverse (citing an already-withdrawn row). Low; worth a line in the core's conventions.

## Decisions
As in r7; decision 1 remains Ryan's one line at mirror time.
