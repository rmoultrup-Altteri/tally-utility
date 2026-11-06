# Opus review: v5.4.2-27 r4 (shortfall applications)

**Verdict: ready.** Nothing blocks. My r3 blocking finding is fixed: an undo dated after today is now refused for every role, whether it is recorded alone or with the refund's return. A repayment dated ahead can still be undone on its own date, and every correction I tried can still be made. With the date rule in place, the second reading r3 added is redundant, so removing it is right. The database now records whether an undo gave money to an already-escheated credit (the stamp). The stamp is right for every role and statement shape I tried, a caller's value is always replaced, and the re-read under the credit's lock closes the race. I have one should-fix. A single statement that writes the undo, the remittance and the escheat together gets a "retry" error (40001), and a retry can never succeed. It fails closed and the shape is unusual. There are some notes. The battery, both race scripts and -23's battery all reproduce.

## Hashes and reproduction (executed)

- The five frozen md5s match the brief: patch a31850a0…, battery 50a38956…, races aa30b429…, mutations 56a61b30…, r3-to-r4.diff a8380a6b…. The brief's own md5 (881c0e07…) matches `review-brief-27-r4.md5`.
- Clone `rv27opus`: `CREATE DATABASE … TEMPLATE tally`, then TEMP revoked from PUBLIC, tally_app and tally_core. I applied the frozen r4 patch strictly (`search_path=`, `check_function_bodies=on`) twice. The first run gave rc=0. The second was skipped by its marker ("already applied"), rc=0.
- `battery-27-frozen-r4.sql`: 142 PASS, 0 FAIL, rc=0.
- `shortfall-27-frozen-r4.sh rv27opus`: 21 PASS (SR1–SR11), rc=0.
- -23's battery: without -30 it stops at -30's column (`rate_item_versions.in_late_penalty_base`), as the brief says it would. On a fresh clone with frozen -27 r4 and then frozen -30 r1 (md5 9076fced…, applied strictly) it gives **409 PASS**, 0 FAIL. `cash-23.sh rv27opus`: **51 PASS**, rc=0.
- I did not run the mutations or ci.sh, and I touched no role. The clone was made again before the -23 runs and dropped at the end.
- Probes: the battery's prelude and fixtures (lines 1–145), plus a `pg_temp.try` helper that prints ADMITTED, or REFUSED with the SQLSTATE and message. Each probe runs in one transaction ending in ROLLBACK. Fixture X: P pays 50 (03-10), is refunded 30 (03-11) and bounces (03-12), leaving 30 short. Goodwill credit G (50) repays 30, dated 03-13. The probe files are in my scratchpad, not the repo.

---

## 1. My r3 findings

| r3 | What it was | r4 |
|---|---|---|
| B1 | An undo dated after today, recorded alone before the refund came back, made the return unrecordable until that date | **Fixed** (executed). Battery R0 (2099, alone) and R0b (UTC+14 date + 1) are refused, and R2 (today) is admitted. My B5: the owner's undo dated 2099 is refused with the same message, so the rule binds every role. My C1/C2 below cover partial undos, two undos of one row, and a repayment dated ahead. |
| S1 | Tests: an undo in a later transaction than the escheat; B1's regressions | **Fixed.** SR10 runs the carry in a transaction after the escheat. R0/R0b/R2/R3/R3b, with M56/M57/M57b/M58. |
| N1 | R5 should name the zone difference from -23's R-02 | **Fixed.** R5 now says UTC+14 rather than CURRENT_DATE, up to one local day ahead in Texas and two in the far west, read at `now()`. |
| N2 | `status_recorded_at` over `escheated_at` | Superseded by the stamp (Fable S1). It was a better fix: one transaction's two times are equal, and the stamp records the fact itself. |
| N4 | E18d should read the shares | **Fixed.** E18e: K3 5, OQ 35, KQ and R 0, OQ reads -35, Q 0/0. |
| N5 | R1–R4 unchanged; R5 acceptable once B1 is fixed | It is, and none of them blocks (section 8). |

## 2. Does r4 implement the r4 plan?

Yes. Every item in the plan's "As built" list is in the patch, battery, races and mutations. Two small wording gaps (N1): the plan says "R1 and R1b stay; now refused at the undo's insert", but they were replaced by R0/R0b, the same two dates recorded alone. That is a stronger test, not a weaker one. The plan's R0c ("today, alone, admitted") is folded into R2. R2's undo is inserted, and admitted, before the return in the same check, so it does test today alone.

## 3. Paths around the rules

### The date rule (executed: C0–C2, B5)

C0: when I ran this, `now()` was 2026-11-06 17:54 UTC, the server date 11-06 and the UTC+14 date 11-07.

- **C1, two partial undos of one row, both dated within the rule:** the undo of 10 dated 11-07 (UTC+14 today) was ADMITTED. The undo of 20 dated 03-20, between the row and today, was ADMITTED. A third undo of 0.01 was REFUSED 23514 ("its undos would come to 30.01, more than its 30.00"). The refund's return was then ADMITTED.
- **C2, a repayment dated ahead (today + 5 = 11-12):**
  - An undo dated today, before the row, was REFUSED by "dated on or after it".
  - An undo of 10 on 11-12 was ADMITTED.
  - An undo of 20 on 11-13 was REFUSED by the new rule.
  - An undo of 20 on 11-12 was ADMITTED.
  - The refund's return was ADMITTED. On 11-12, P2 reads 0.00/0.00 and G2 30.00.
- **B5:** the owner's undo dated 2099 was REFUSED 23514 by the new rule. The rule sits in an AFTER trigger enabled for every role (ENABLE ALWAYS) and reads `now()`, which no caller can choose. The session time zone does not affect it, because the bound uses an explicit AT TIME ZONE.
- **No correction becomes impossible.** A repayment dated in the past is undone on any date from its own date to today, and the freeze still applies to that range. A repayment dated ahead is undone on its own date, and once that date has passed, on any date up to today. A repayment with a mistyped future date (2062 for 2026) is undone on that date, and the refund's return is then admitted. That is the case where r3 left the customer's credit stuck. Now it unlocks at once.

### Removing the second reading (read; executed by C1, C2)

It is redundant. The first reading counts an undo from the date of the row it undoes. The positions count it from its own date. The two differ only between those two dates. Under the rule, an undo of a row dated on or after today must carry the row's own date, so there is no gap. An undo of a row dated before today carries a date no later than today, so the gap ends at or before today. From today on, every undo of a row dated on or before a given day is itself dated on or before that day. So both readings count the same rows at every date from today on, and the second reading could never refuse what the first admits. "Today" only moves forward, and it is read at the undo's own transaction start, so a later return never meets an earlier bound. I could not build a sequence in which a move giving money back is admitted and the family then holds money on or after today. C1 shows R5's interval as stated: on the server's 11-06, P reads -20.00/10.00, because the undo of 10 dated 11-07 has not counted yet. On 11-07 it reads -30.00/0.00.

### The stamp (executed: A1–A4, B1–B4, SR11)

| Probe | Shape | Result |
|---|---|---|
| A4 | tally_app, two undos in one INSERT, caller sends `gave_to_escheated = true`, G active | stamps false,false. A carry naming one is refused ("its credit is active") |
| B1 | owner COPY (tally_app's COPY FROM is refused under row-level security), sends true, G active | stamp false |
| B2 | owner COPY, sends false, G escheated in an earlier statement | stamp true |
| A2 | one statement: writable CTEs, the escheat running before the undo | stamp t, then 23514 at the commit check: "carry it". Right: the escheat took only the other 20 |
| A1 | one statement, the undo running before the escheat (remittance 20) | the escheat is REFUSED 23001: "30.00 remains". Right |
| A3c | three statements in one transaction: undo, a remittance of 50, escheat | stamp f, status escheated, ADMITTED, no carry needed. Right: the remittance took the undo's 30 |
| A3b | the same three as **one** statement (CTEs ordered undo, then remittance 50, then escheat) | **REFUSED 40001** "was escheated while this undo waited … retry it" (S1) |
| B4 | owner, `session_replication_role = replica`, UPDATE of the stamp | REFUSED 23001 append-only (ENABLE ALWAYS) |
| SR11 | race: the escheat commits while the undo waits | 40001, then the retry with its carry is admitted |

- PostgreSQL runs modifying CTEs here in reverse order of listing (A1/A2). Each trigger's queries see the earlier sub-statements' rows, so the stamp matches the order the work actually ran in.
- **History load (read; B3 executed only part of the way).** If the owner gives an undo a chosen `created_at` before the escheat, `check_cash_order` refuses it with 23514 for a chosen time. That function lists `cash_source_draws('credit', …)`, which includes the `escheated_to_state` event. B3 hit the earlier target-move check first, because one transaction has a single `now()`, so this branch is predicted. In the other direction, an escheat with a chosen time before an undo is refused by `cash_lineage_recorded`, as I found in r3. So a history load has to put the rows in their real order, and the stamp then matches that order.
- **The 40001 is the right signal across transactions.** The re-read is only reached when the escheat was recorded at or before the undo's own time. An escheat recorded after it is refused earlier by `check_cash_order`. On retry, the BEFORE trigger sees the escheat and stamps true, and the commit check asks for the carry. Within one statement it is the wrong signal: see S1.
- I found no role, isolation level or statement shape in which the stored stamp is wrong. Any mismatch between the BEFORE read and the read under the lock is refused (A3b, SR11, and mutations M60b/M60e).

## 4. -23's properties

Caps, cover, shares and recorded order are unchanged. The date rule only refuses. The stamp is a read and takes no lock. The re-read happens under the lock `check_cash_source` already holds. J1 confirms Codex's case: at the bounce's instant `cash_drawn_at` is -20, and the overpayment credit KJ absorbs 80, not 100. -23's battery gives 409/409 and its races 51/51 with -27 r4 (and -30 r1) applied.

## 5. Concurrency

The lock order is unchanged: the freeze head, then the target payment, then (in `check_cash_source`) the payment whose money the credit holds, then the credit. The escheat takes the payment's lock and then the credit's (`enforce_customer_credit_immutable`, tu.sql:44998–45003). An undo and an escheat therefore always meet on the credit's lock, the escheat holds it to commit, and the undo's re-read after the wait sees it. There is one unlocked read, the stamp's BEFORE read. It is re-checked under the lock, and that is exactly what SR11 covers. The carry's read of the undo's stamp is a read of an immutable row. Its read of the credit's status sees a terminal state, because escheated never moves back. Neither needs a lock.

## 6. Invariants

`assert_shortfall_guard_invariants` lists the new trigger and the CHECK. As before, it checks definitions, not function bodies. If someone replaced the stamp function's body, the invariant would not notice. The re-read in `enforce_shortfall_application` would refuse the first undo it stamped wrongly, though (M60b, M60e), so the claim holds in practice (N3). The column and table comments match what the checks enforce.

## 7. Tests

- The mutations target the right thing. M56 switches the rule off and is caught at R0. M57 reads today at UTC-12, which is always one or two days behind UTC+14, so it is caught at R2 on every run. M57b reads a day late and is caught at R0b. M58 removes the exception for a row dated ahead and is caught at R3b. M60c (no re-read) is caught only by SR11, which is right, because only a race can show it. M65 is caught by J1.
- E15 does what it says. The undo and the escheat are in one transaction with equal times, the stamp says false, and the carry is refused by the stamp check (the message is matched).
- Missing, not needed: a battery check that a caller's `true` is replaced (my A4, B1). The re-read would refuse a stamp that kept the caller's value, so M60b covers it.
- Codex's "no M64" stands. I still cannot build an instant at which the source's own shortfall term in `cash_drawn_at` is not 0 (r3 P3/P4 reasoning; nothing in r4 changes it).

## 8. Residuals

R1–R4 are unchanged and none blocks. R5 is now exact: an undo is dated no later than today (UTC+14), so the interval in which positions differ is in the past, apart from the zone lag R5 states (C1 shows it). -23's `refund_reissue` gap does not block -27 (N4).

---

## S1 (executed: A3b). A single statement that writes the undo, the remittance and the escheat gets a 40001 it can never clear

A writable-CTE statement does three things in this order: the undo of G's repayment (G still active, so the stamp is false), a remittance of 50 that includes the undo's 30, and the move to escheated. The undo's AFTER trigger fires at the end of the statement, re-reads G as escheated, and raises 40001 "retry it". A retry runs the same statement, so it fails the same way every time. The same three writes as separate statements are admitted, with the correct stamp (A3c). It fails closed, so no money is wrong, and the shape is unusual for app code. But 40001 tells a retry loop to try again, and here a retry cannot succeed. **Fix:** when this transaction made the credit's move itself (`status_recorded_at = now()`, which two separate transactions practically never share), raise 23514 instead: "write the undo in a statement of its own, before or after the escheat". Keep 40001 for the case where another transaction committed the move. One battery check would cover it. Not blocking.

## Notes

- **N1.** The plan says R1 and R1b stay. They were replaced by R0 and R0b, the same dates recorded alone, which is stronger. The plan's R0c is inside R2. Worth one line in the plan or the CHANGELOG so the counts add up.
- **N2.** A caller's `gave_to_escheated` is always replaced: in a multi-row INSERT (A4) and in COPY, both true onto an active credit (B1) and false onto an escheated one (B2). A carry naming an undo stamped false is refused.
- **N3.** The invariant does not check the stamp function's body. That is consistent with -27's "definitions, not bodies", and the re-read makes a wrong body fail on first use.
- **N4.** -23's `refund_reissue` (a reissue naming a refund that came back before the escheat) is the same gap on -23's own tables. It does not block -27. If the money stream closes it, r4's pattern fits: the database records, when the refund leaves, whether its credit was already escheated.
- **N5.** Between the server's date and the UTC+14 date, positions read an undo dated "today" as not yet counted (C1: -20.00/10.00 on 11-06, -30.00/0.00 on 11-07). That is R5 as written, and nothing to change.
- **Housekeeping.** Two `crystaldba/postgres-mcp` containers were running when I started (the CLAUDE.md check). I left them alone. I dropped clone `rv27opus` when done.
