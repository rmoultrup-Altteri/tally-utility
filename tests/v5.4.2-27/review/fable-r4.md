# Fable review — v5.4.2-27 r4 (a credit applied to a bounced payment's shortfall; the undo's date rule; the stamped carry)

**Verdict: ready.** No blocking item, no should-fix. My r3 B1 (an undo dated after today, recorded alone, makes a returned refund unrecordable) is closed by the date rule, executed. My r3 S1 (two equal stamps let a carry name an undo that gave nothing) is closed by the database's own record, `gave_to_escheated`, executed in every shape I could build: the app's write, the owner's write with a sent value, COPY with a sent value, a writable CTE in both orders, and the race where the escheat commits while the undo waits. Four notes, none on the rules.

Frozen hashes checked first (`md5 -q`): all five match the brief, the brief matches `review-brief-27-r4.md5`, and each frozen r4 file is byte-identical to its live copy (`sql/v5.4.2-27-shortfall-applications.sql`, `battery-27.sql`, `races/shortfall-27.sh`, `mutations-27.py`). Clone `rv27fable` (TEMPLATE tally; TEMP revoked from PUBLIC, tally_app, tally_core; `has_database_privilege` = f for both app roles); frozen r4 applied strictly (`search_path=''`, `check_function_bodies=on`) twice: the second run printed "already applied (shortfall_applications exists); nothing to do". Server zone Etc/UTC; at the run (2026-11-06 17:55 UTC), "today" was 2026-11-07 at UTC+14 and 2026-11-06 at UTC-12. Both clones dropped at the end.

## Reproduced

| What | Result |
|---|---|
| strict apply, twice | first applies, second skipped by its marker |
| `battery-27-frozen-r4.sql` | 142 PASS, 0 FAIL, rolled back |
| `shortfall-27-frozen-r4.sh rv27fable` | SR1–SR11, 21 PASS, exit 0 (SR10, SR10a, SR10b, SR11, SR11a all pass) |
| the `rep()` anchors of `mutations-27-frozen-r4.py` | each exactly one occurrence in the frozen patch (71 by regex; the 72nd mutation is not a `rep()`); each named check exists in the battery or the race script |
| -23's battery with -27 r4 then -30 applied strictly | 409 PASS, 0 FAIL, on a second fresh clone (`rv27fable2`); see N3 for why a fresh one |
| `assert_shortfall_guard_invariants()` | passes in the battery's tail and at the end of my probe transaction |

Mutations and `ci.sh` not run (restricted). Read: M56 removes the date rule (R0 admits); M57 reads today at UTC-12, which is never the UTC+14 date (26 hours apart), so R2's undo dated the UTC+14 date is refused; M57b adds a day (R0b admits); M58 drops `greatest` (R3b's undo on the ahead-dated row's date is refused); M60 drops the carry's stamp check (E15 admits); M60b/M60e force the stamp (the re-read under the lock refuses at the first undo of a credit's repayment, S3 or E3, with 40001 — before E15a reads the values); M60c drops the re-read (SR11's 40001 does not come); M60d drops the trigger (the invariant refuses at apply); M65 drops the repaid term (J1 reads 100, not 80).

## My r3 findings

| r3 | Status | Evidence |
|---|---|---|
| B1 — an undo dated after today, recorded alone, then the refund's return is refused until that date | **fixed** (executed) | Battery R0, R0b refuse the standalone undo at 2099-12-31 and at today+1 (23514, "dated no later than today"); R2 admits today's and settles the return. My P1: the same fixture as r3's P1; the 2099 undo refused alone (P1a); an undo dated today at UTC+14, alone with the refund still out, admitted (P1b); the return recorded afterwards in its own statement, admitted (P1c); P reads 0.00/0.00 and G 30.00; a further repayment of 30 is refused by the cap (P1d). Nothing is stranded. |
| S1 — equal stamps let a carry name an undo written while the credit was active | **fixed** (executed) | E15 refuses the carry for G's undo written before the escheat in one transaction; E15a reads the stamp both ways. My P3f: a carry naming the pre-escheat undo refused (23514, "written while credit … was not yet escheated"); P3g: the carry naming the post-escheat undo admitted and sized right; the commit check flushes; the return then records (P3i). |
| N1–N8 | notes; N1 (a repayment dated ahead) is now R3/R3b and my P4; N5 (UTC+14) agreed again; N8 is in the plan's money-stream notes | |

## Findings

No B. No S.

### N1 (executed) — the stamp holds in every shape I built; the re-read is the guard, the stamp the record

- The app sends `gave_to_escheated = true` on an active credit's undo: stamped false (P3a). The owner, by COPY from a file with `true` and a chosen `created_at`, on the active credit: stamped false (P3d). The owner sends `false` on an undo onto the escheated credit: stamped true (P3e). Neither role can update it afterwards (P3b 42501, P3c 23001 append-only).
- A writable CTE that escheats the credit and inserts its undo in one statement: with the INSERT as the main query and the UPDATE unreferenced, the INSERT runs first, and -23's own escheat guard refuses the statement (23001, "moves to escheated only when nothing of it is left: 20.00 remains"), since the undo's money is back on the credit before the escheat reads it — so -27's 40001 is never reached and no shape stamps false against an escheated credit (P2a). With the INSERT selecting from the UPDATE's RETURNING, the escheat runs first, the stamp reads it (the trigger's query sees the same command's earlier work), the row is stamped true, the carry is admitted and the return records cleanly (P2b–P2e: P 0.00/0.00, G 0.00, the carry 20.00).
- SR11 (the escheat committing while the undo waits) gave its 40001 on my clone, and the retry with its carry was admitted.

One thing the battery does not pin: that a caller-sent value is replaced (E15a reads only the app's unsent writes). The re-read makes a wrong value a 40001 rather than a hole (M60b/M60e), so this is a test-completeness note, not a gap: a one-line check sending `true` on an active credit's undo would pin the comment's "whatever the caller sent is replaced".

### N2 (executed) — R5's window, measured

With the undo dated today at UTC+14 (2026-11-07) and the refund's return recorded the same transaction, the ended payment on the UTC-12 date (2026-11-06) reads 30.00 remaining / 30.00 repaid, and on the UTC+14 date 0.00/0.00 (P5c; P1b likewise 0.00/30.00 before the return). That is R5 as the header now states it: the full repaid amount, for up to one local day in Texas and two in the far west, never on or after the UTC+14 date. Not blocking; agreed with r3's reasoning that the second reading is redundant once no undo is dated past that day (I found no sequence of partial undos, an ahead-dated repayment and leaving moves where the first reading admits money held on or after it: P4b–P4d, P5a–P5c).

### N3 (executed) — the race script's ids collide with -23's battery

`shortfall-27.sh` commits rows under `…28xx`; -23's battery inserts payment `…2861` and fails on `account_ledger_pkey` if run on the same clone afterwards (my first attempt). Run -23's battery on a clone the race script has not touched, as the author evidently did. Worth a line in the race script's header; nothing in the patch.

### N4 (predicted) — the 40001 after a lost race asks for more than a retry

SR11's retry succeeds only because the app also writes the carry; a bare retry of the undo would be refused at commit by `enforce_shortfall_undo_carried` ("carry it to a new credit"). That is the right order of messages (the first says the premise moved, the second says what to do now), and `serialization_failure` is the right class: the undo's reading of its credit was stale. No change asked.

## The brief's questions

1. **r3 findings fixed:** B1 and S1, yes (above), by the fix the plan names.
2. **The r4 plan:** implemented — the date rule in `enforce_shortfall_application` (greatest of the UTC+14 date and the undone row's date); `check_shortfall_repaid` back to r2's text plus the comment; the stamp, its CHECK, the re-read under the credit's lock, the carry keyed on it, both in the invariant's lists; R0/R0b/R2/R2b/R3/R3b; J1 with M65; E20/E20b through the bill writer; E18e's split (K3 5, OQ 35); E15/E15a; SR10/SR11; R5's wording (one day in Texas, two in the far west; `now()` the transaction's instant). Building option 2 rather than the recommended "strictly later" is the better build: it is exact in any order and refuses nothing legitimate; the DECISION-LOG says why. Nothing missed or half-done.
3. **Paths around a rule:** none found. Tried: the standalone future undo (P1a), today's at UTC+14 alone (P1b, admitted as designed), partial undos and two undos of one ahead-dated row (P4a–P4c: the undo of a row dated ahead must sit on that date, both partials admitted there, the return then records), the owner's sent stamp and COPY (P3), the writable CTE in both orders (P2), the escheat-while-waiting race (SR11), a mixed family with one credit undone today and another still applied (P5b refused, P5c admitted).
4. **-23's properties:** the date rule touches no cap or share; the stamp changes which record a carry names, not the sizes (P3g: the carry is `least(what the undo gave, what is left)`; P2d/P3h positions as expected; E16–E18e pass). J1 corrects the share reader's premise and E18e pins the split.
5. **Concurrency:** lock order unchanged (close head, target payment, the source's root payment, the source credit). The one read taken before its lock — the stamp's — is re-read under the lock and a difference is a 40001 (SR11; M60c). The escheat's own order (root payment, then credit) never takes the target, so no new cycle.
6. **Invariants:** the trigger definitions, ENABLE ALWAYS, and the CHECK text are held; the stamp's body cannot be, so "whatever the caller sent is replaced" rests on the body and the re-read (as r3's N7 for born-active). Claims match checks.
7. **Tests:** none weaker than its label. Each mutation's named check is a first failure by construction; M60b/M60e are caught earlier than their nominal target, as the file says. Missing: N1's sent-value check (optional).
8. **Residuals:** R1–R4 unchanged; R5 as reworded is accurate and not blocking (N2 gives its size). -23's `refund_reissue` mirror gap and r3 N8 (no commit check carries a returned refund of an escheated credit) are -23's tables, for the money stream; they do not block -27.

## Probe file

`/private/tmp/claude-501/-Users-ryanscomputer-code-tally-utility/1dff16d9-6dfb-40ad-a60b-fd9517b382c2/scratchpad/probe-r4-fable.sql` — P1–P5 above, one transaction rolled back, built on the battery's helpers (`/tmp/b27pre.sql` in the container is the battery's lines 26–125); ids under `00000000-0000-4000-8000-00000000d8xx`. Runs with `docker exec tally-pg psql -U tally -d <clone> -q -f`.
