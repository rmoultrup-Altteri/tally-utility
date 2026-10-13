Same job and rules as before (`review-brief-15r-r1.md` … `r7.md`). Round 8, a small delta. Round 7 verdicts: Opus **READY** and Fable **READY**, each with the same should-fix S1; Codex **NOT YET** on that same item (the return-due BEFORE trigger reads the lagging `d.status`). Output files: `opus-r8.md` / `fable-r8.md` / `codex-r8.md`.

**Frozen artefacts (round 8)** — check the hashes:
- patch `tests/v5.4.2-15/review/patch-15r-frozen-r8.sql` — md5 `2dc8f61cda3bc6958ca42737d317a629` (diff from r7: `diff patch-15r-frozen-r7.sql patch-15r-frozen-r8.sql`; one new function and trigger, nothing else changed)
- battery `tests/v5.4.2-15/review/battery-15r-frozen-r8.sql` — md5 `8a0c6c4548ab0560ffb0698c13b4da96` (356 checks)
- tests: `mutations-15r.py` (175 mutations, all caught), `migration-15r.py`, `races/due-mutex-15.sh`, `evidence-txn-15.sh`, `fail-first.py` — all pass.

## The delta from round 7
- **S1 (all three).** Measured red first: V28b and V28c (a refund notice and a due row in one writable WITH, either order) are accepted by frozen r7. Opus showed that reading events in the BEFORE ROW trigger is not enough (which part runs first is not fixed), so the new check is `enforce_deposit_return_due_not_started`, an AFTER INSERT FOR EACH ROW trigger on `deposit_return_due` (`z_…`, ENABLE ALWAYS): once the statement has run, no `refund_initiated` / `refunded` / `released` event of the deposit may exist that does not cite this due row. A refund citing the new row is the legitimate path (V28d accepts it). The BEFORE check stays for its message.
- Checks V28b–V28d; mutations M175 (check off) and M176 (the citing refund is refused too).

## Decisions
As in r7. Not done, said so: Fable F5i (a zero refund can close a deposit with scheduled instalments unpaid) — the core's. Fable's lag in the -06 `enforce_customer_lifecycle` is fail-closed and left.

## What to do
Opus and Fable: verify the delta; try to get a due row beside a started return, or to stop a legitimate flow (the refund that settles a due row, in one statement or two; a partial return; a superseding row). Codex: the same, from the source. Say plainly what you could only read. Verdict **ready** or **not yet**. Same output rules.
