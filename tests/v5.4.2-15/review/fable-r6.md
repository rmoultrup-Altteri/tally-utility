# Review r6 — v5.4.2-15 rewrite — Fable (delta on round 5)

Date: 2026-10-13. Artefacts: `patch-15r-frozen-r6.sql` md5 `cb770fbafb02e17b6bfb049805439a6d` (matches; byte-identical to `sql/v5.4.2-15-deposits-law-to-core.sql`), `battery-15r-frozen-r6.sql` md5 `46e7c36e12436204a5a33b87580ff3df` (matches; identical to `tests/v5.4.2-15/battery-15r.sql`). Repo at `cdf41d7`.

How I probed: `diff patch-15r-frozen-r5.sql patch-15r-frozen-r6.sql` read whole (six hunks: four comment hunks, `v_least`, the guard); clone `fable16` (TEMPLATE `tally`, TEMP revoked), patch applied strictly (`search_path=''`, `check_function_bodies=on`) — clean; battery 343 PASS, exit 0; M168–M170 through `mutations-15r.py` — all three caught at I9/I13/I15; 43 probes spliced before I16 (same transaction; state-changing ones under SAVEPOINTs), 386 PASS, exit 0; one extra mutation of my own (below) on a second clone `fable16n`. Both clones dropped; `tally` and `postgres` untouched. Probes: `fable-r6-probes.sql` beside this file.

## Verdict: READY — the delta does not change my round-5 verdict

The guard is right by construction: held principal is a step function that changes only on event days, so checking `NEW.effective_on` and every later recorded day is exactly the set of days a debit can drive negative; the subquery always includes the event's own day, so `v_least` is never NULL; the deposit row is locked `FOR UPDATE` first, so concurrent events serialise; `tally_app` holds no UPDATE or DELETE on `deposit_events` (42501, not even the append-only trigger is reached), so no event can be re-dated around it. Inductively, once every debit is accepted by the guard, held is ≥ 0 on every recorded day — a receipt only raises later days.

## What I tried to break, and could not
- **Ties on one day** (F1): a return of 0.01 and an application of 87.49 dated 14 Feb, the day the 87.50 instalment arrives, are both accepted — same-day money counts, held ends at exactly 0; one cent more is refused (by the remainder check first, the guard sits last by design); a backdated 0.01 on 10 Feb refused; the zero refund notice closes it; held never negative.
- **Debit before posting** (F2): refused by the existing `precedes posted_on` fence before the guard runs.
- **Refund-type events vs later events** (F3, F4j/k, F5f, F7): a refund dated before a later return, a later receipt, or — the lead's widening — a later application with no receipt after it (F7b: 77.50 dated 20 Feb with an application of 10 on 1 Mar) is refused; dated on the last movement's day it is accepted. Once pending, a backdated instalment is stopped by status, not the guard.
- **Several receipts, out of order** (F4): a three-instalment deposit (35 at posting, 70 on 14 Feb, 70 on 16 Mar) with the 16 Mar instalment recorded first: 36 on 20 Jan refused (35 held; the later 70 does not reach back), 35 accepted, 14 Feb receipt recorded late, 71 on 1 Mar refused, 70 accepted, a backdated 0.01 on 20 Feb refused (it would unfund the 1 Mar return), refund of 70 on 1 Mar refused (16 Mar receipt later), on 16 Mar accepted; `exhausted_on` NULL; held never negative.
- **Status projection after a late receipt** (F4e, F5c/e): applying the 35 while 140 is still to come projects `applied` (remainder 0 today), and the late 14 Feb receipt turns it back to `partial_applied` — the documented behaviour; with a later receipt already recorded the application projects `partial_applied` straight away.

## Findings
- **S1 (should fix, tests only — the patch is right).** The battery pins the refund-date rule only against a later *receipt* (I15). I narrowed the guard's list back to Codex's wording (`'posted', 'instalment_received'` only, dropping `applied_to_balance` and `principal_returned`) and the frozen battery passed 343/343. The lead's widening — which F7b shows the patch does enforce — is therefore unpinned: add a check for a refund notice dated after every receipt but before an application or return already recorded (F7a–c is a ready shape), and a mutation (M171) that narrows the list. Not blocking; fine to land with the mirror or the next revision.

## Observations (outside the guard's scope; not findings against this round)
- F3e: `refunded` may be dated before its own `refund_initiated` (20 Feb refund, 1 Mar notice). Pre-existing; nothing about money leaving before it arrived.
- F5i: a zero `refunded` closes a deposit with two scheduled instalments (140) unpaid. Physically coherent (the instalments were never received), and the schedule rows remain; the core may want to say whether a deposit with instalments still due can be settled by a zero refund.

## Decision 1
Still Ryan's to confirm (a deposit's own closed law row stays citable after its close): it is a policy call, not a correctness one, and nothing in rounds 3–6 depends on it going either way. I do not need it before the mirror — one line from Ryan at mirror time is enough.
