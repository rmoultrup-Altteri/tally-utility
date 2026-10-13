Same job and rules as before (`review-brief-15r-r1.md` … `r6.md`). Round 7. Round 6 verdicts: Codex **READY** (read-only, no Docker), Fable **READY** (one test-only should-fix), **Opus NOT YET** (`opus-r6.md`: B1). Output files: `opus-r7.md` / `fable-r7.md` / `codex-r7.md`.

**Frozen artefacts (round 7)** — check the hashes:
- patch `tests/v5.4.2-15/review/patch-15r-frozen-r7.sql` — md5 `44a4d2b1a6cbe135c6744c40331bf1f9` (diff from r6: `diff patch-15r-frozen-r6.sql patch-15r-frozen-r7.sql`, 26 changed lines, all inside `enforce_deposit_event`)
- battery `tests/v5.4.2-15/review/battery-15r-frozen-r7.sql` — md5 `ebe98c8751838d53031ecf020eac8ba8` (352 checks; each block passes alone via `fail-first.py`)
- tests: `mutations-15r.py` (173 mutations, all caught), `migration-15r.py`, `races/due-mutex-15.sh`, `evidence-txn-15.sh` — all pass.

## The delta from round 6
- **Opus r6 B1 (measured first: I17, I21, I22 are accepted by frozen r6, red).** The status projection is an AFTER ROW trigger, so inside one multi-row INSERT every status check saw the status from before the statement. `enforce_deposit_event` now reads "closed" (a `refunded`/`released` event exists) and "notice date" (earliest `refund_initiated`) from `deposit_events`, which a BEFORE ROW query sees row by row, and uses them for: nothing after refunded/released; a refund is pending (instalment, application, return, a second notice). The projection itself is unchanged.
- **Opus/Fable N1.** A `refunded`/`released` is refused if dated before the refund notice (`precedes the refund notice`).
- **Fable r6 S1 (test-only).** I24 pins the refund-date rule against an application recorded after every receipt. M171 narrows the list back to receipts and is caught.
- Checks I17–I24 (I23b included): two refunds, or refund then return, in ONE statement; a refund before its notice; a notice then an instalment, or then a return, in one statement (on a second instalment deposit, I20); I24. Mutations M171–M174.

## Decisions (unchanged) and one new
1–4 as in r6. New, mine: "pending" is "a `refund_initiated` event exists" (there is no way to cancel a notice in this ledger). Not done, said so: Fable F5i (a zero refund can close a deposit with scheduled instalments unpaid) — left to the core.

## What to do
Opus and Fable: verify the delta; look for any other check that reads a projected column (`d.status`, `refunded_on`, `released_on`, anything an AFTER trigger writes) inside a BEFORE ROW trigger or constraint and so lags in a multi-row statement. Codex: the delta, and the same search; say plainly what you could only read. Verdict **ready** or **not yet**. Same output rules.
