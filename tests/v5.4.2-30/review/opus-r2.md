# v5.4.2-30 r2 — Opus review

**Date:** 2026-11-06. **Reviewer:** Opus. **Verdict: not yet** (one blocking item).

Frozen md5s checked first; all six match the brief, and the live patch is byte-identical to the frozen r2 copy (**executed**). Strict apply on a fresh clone of `tally` (`rv30opus`, TEMP revoked from PUBLIC, `tally_app`, `tally_core`): clean, twice; and a third time after a percent `sales_tax_rate` fact and a levy existed (**executed**). I did not run the battery, `ci.sh`, the mutations or the preconditions (the brief's restrictions); I read them. Probes ran on `rv30opus`, some committed there (it is mine and is dropped). `rv30opus` is dropped.

PATCH-LESSONS sections read: depth-fence-needs-no-temp, trigger-depth-fence-inside-guard, seal-pattern-owner-roles, temporal-helper-no-live-fallback, date-from-snapshot-knowledge-from-now, count-guards-need-lock-handshake, lock-order-as-a-rule, checks-narrower-than-their-claim.

---

## 1. My round-1 findings, item by item

- **B1 (a state correction rewrote a past read): closed for the serial path** (**executed**). My round-1 repro, as `tally_app`: a TX premise with a city membership recorded two seconds earlier; void the membership, change the state to NM; the read at `now() - 1s` answers `{TX, TX-O30-CITY}`, the read at `now()` answers `{NM}`. Battery M6/M7 hold the same. **But the new history is ordered by a transaction-start stamp, and two overlapping writers leave it permanently wrong: B1 below.**
- **S1 (late-penalty guards on origin only): closed.** Both are `tgenabled = 'A'` (**executed**); P7 and N34 hold it.
- **S2 (a place closes under an open levy): closed, better than I proposed.** Real commits (**executed**): a close with no successor fails at COMMIT with the coverage message; `SET CONSTRAINTS ALL DEFERRED` plus `SET LOCAL session_replication_role = replica` does not skip it; a close and its successor row in one transaction commit. Both race orders hold (**executed**, two sessions): a close holding its lock makes a levy insert wait about two seconds and then refuse it ("its rows: {[2000-01-01,2026-12-01)}"); a levy insert in flight makes a close wait, and the close is refused at its commit.
- **S3 (re-apply refused once a fact exists): closed** (**executed**, third apply above).
- **S4 (exemption comments): closed.** The column comment now says required, each one a service, the full list for "every service". The table comment no longer makes the "any active exemption" claim (**executed**, catalogue read).
- **S5 (test gaps): closed.** L22/L23 cover successive rows and a gap (N37 catches the "first day" mutation). M11/M11b close a place after the instant (N44 catches dropping `end_as_known` on the place leg).
- **Notes N1–N11:** N1 and N2 became L7 and L6; the others needed no change.

---

## Blocking

### B1. Two overlapping state changes leave the history's latest row on the losing value, so every read "as known now" answers the wrong state, permanently

`record_service_location_state()` stamps `recorded_at = now()`, the writer's transaction start. `premise_places_as_of` takes the latest row by `recorded_at DESC, seq DESC`. Writers on one premise are serialised by the row lock on `service_locations`, but they are not stamped in that order. A transaction that **began first and writes last** gets the earlier stamp, so the row holding the premise's actual state sorts below the row it overwrote.

Repro (**executed**, two sessions, committed on `rv30opus`): the premise is recorded TX (seq 1).
- Session A: `BEGIN; SELECT now()` (18:00:41.8), sleeps.
- Session B: begins at 18:00:42.8, sets the state to NM, commits.
- Session A: sets the state to TX at 18:00:45.8, commits.

Result: `service_locations.state = 'TX'`. History: `TX @41.8 seq 3`, `NM @42.8 seq 2`. `premise_places_as_of(…, now())` and the three-argument form both answer **`{NM}`**, and keep answering it. Every later read sees New Mexico while the premise is in Texas, until someone changes the state again: the current bill, the time zone (`premise_time_zone_as_of` reads through the three-argument form), and every rebill. Nothing raises.

Why it blocks: this is the shape round 1's B1 was about (the read answers a state the premise is not in, dropping or adding a whole state's levies), now reached by two ordinary `tally_app` corrections that overlap. L7 says the template's `now()` stamps can only make a read **refuse** ("2 rows") for seconds. That is true of `tax_levy_as_of`, because it counts. It is not true of a "latest row wins" read: there the wrong answer is silent and lasts forever.

Fix options:
1. **Refuse the late writer (recommended).** In the recorder, before inserting, check for a row of this premise recorded after `now()`. If one exists, raise `serialization_failure`. The writer retries, gets a fresh `now()`, and its row then sorts last. The stamp stays the transaction start, as on every other row in the template. This is "refuse, never mis-answer", and it makes L7 true for the history. The check runs under the premise's row lock, which the UPDATE already holds, so it cannot itself race.
2. Stamp `greatest(now(), latest recorded_at of this premise)`. This orders the rows correctly without a retry. But the overwritten state (NM above) is then never readable at any instant, though bills computed in the few seconds before A committed did see it.
3. `clock_timestamp()` also orders correctly. But a premise inserted and read in one transaction (as M10c does, and as onboarding will) is then "not yet recorded" at that transaction's `now()`. Don't use this one.

Test: a two-session race in the project's race harness (as -27's SR tests): A begins first, B changes the state and commits, A's change must be refused 40001 (option 1). The battery alone cannot reach it. M8's `max(recorded_at) = now()` stays true under option 1.

---

## Should fix

### S1. The same stamps let a membership read at a past instant return two cities in one exclusivity group, silently; L7 says it refuses

`premise_places_as_of(…, p_recorded_at)` is new in -30 as a reader at a chosen instant. Memberships are stamped by the template: `created_at = now()` (transaction start); `voided_at` and `closed_at` are set when the write happens. Repro (**executed**, two sessions, committed on `rv30opus`):
- A premise is in city X.
- A long transaction starts at 18:03:44.53.
- The operator voids the X membership ("wrong city keyed") at 18:03:45.50 and commits.
- The long transaction then inserts a Y membership (allowed, since X is now voided). Its `created_at` is 18:03:44.53.

Read as known at 18:03:45.03: **`{TX, TX-O30-X, TX-O30-Y}`**. The premise is in two cities of one exclusivity group (`premise_place_memberships_exclusive`), and the read answers both without an error. A bill computed live at that instant saw only X (Y was uncommitted then). A rebill at the bill's own recorded instant would charge both cities' sales tax. The window is only seconds wide. But it breaks the header's promise ("a rebill reads the jurisdictions the original bill saw"), and L7 states the opposite ("refuses, never mis-answers").

Fix: have `premise_places_as_of` do what `tax_levy_as_of` does. If two `within` memberships returned share an `exclusivity_group` (non-NULL) on the axis, raise `cardinality_violation` naming them. Then restate L7 to cover memberships and the history as well as levies. The read stays loud in the window, and L7 is true. Test: plant two memberships of one group, one voided at an instant after the other's `created_at`, and read between them. One mutation (the check dropped) is caught by it.

### S2. The levy-versus-close lock handshake has no test; a mutation dropping it survives

The shared-lock loop in `tax_levy_insert_check` and the function's `VOLATILE` (each statement re-reads under READ COMMITTED) are what make my two race probes above come out right. Nothing in the battery or mutations exercises either one. Dropping the loop, or marking the function STABLE, survives all 50 mutations' checks (**predicted**: the battery is one session). Add the two races I ran (close first, then levy refused; levy first, then close refused at commit) to the race harness, each with a mutation.

---

## Notes

**N1. A successor row is not share-locked by a levy insert already waiting** (**predicted**, not reproduced: the window is microseconds). The loop locks the rows its snapshot sees. Suppose T2 closes row 1 and adds successor row 2, while T1's levy insert waits on row 1's lock. When T2 commits, T1 re-reads and sees row 2 open, but holds no lock on it. A T3 that closes row 2 in that instant, with no successor, takes row 2's lock unopposed. Its commit-time check cannot see T1's uncommitted levy, and T1's coverage read cannot see T3's uncommitted close. Both commit, and the levy outlives its place. A succession followed at once by a dissolution makes this practically unreachable. The clean fix, if wanted: take the lock on the code (kind, state, code) rather than on each row id, in both `enforce_place`'s close and the levy check. That is a -16 change, so a later patch.

**N2. The gaps report's second leg reads now; that is the right "now" for a report**, with two narrowings worth a sentence (**predicted**, read):
- Its `NOT EXISTS` ignores `service_type` and `system_kind`, so a gas levy suppresses the report for a water service of the same utility in that place.
- The state leg counts every premise of the tenant whatever its status, so a utility whose only premise there is long disconnected still gets the row.

Neither misleads a utility into billing wrong: the report only ever adds rows.

**N3. The history, against earlier patches** (**executed**, catalogue):
- `service_locations` is written only by `tally` and `tally_app`. No seal role (`tally_seal`, `tally_void`, `tally_close`) has any privilege on it, on memberships or on places, so no definer path newly fails on the history's SELECT or INSERT.
- Every caller of `premise_places_as_of` / `premise_time_zone_as_of` / `invoice_time_zone_as_of` is invoker-rights and owned by `tally`.
- The composite foreign key to `service_locations(id, tenant_id)` has four precedents (memberships among them), so a premise's tenant was already fixed.
- No BEFORE trigger on `service_locations` rewrites `state`, so `UPDATE OF state` sees every change.
- RLS: a platform administrator records and reads any tenant's rows, `tally_core` reads, and the recorder's insert passes the policy for the premise's own tenant.

**N4. The depth fence on the history holds** (M10, **read**): TEMP is revoked, the recorder is the only trigger that inserts there, and the superuser exemption is the backfill's. The backfill stamps today's state at `created_at`. That approximation is acceptable while nothing is live (-16 refused changes under other-state memberships, but not on a premise with none).

**N5. Same-transaction order by `seq` is right but untested.** A premise changed TX→NM→TX in one transaction reads TX (seq breaks the tie). No check covers it, so dropping `h.seq DESC` survives (**predicted**). One line in the battery would cover it.

**N6. The tests.** The L fragments now name the schema's own reasons; P4 fails for one reason; Q1b runs as `tally_app`. C1/C3 force the check with `SET CONSTRAINTS … IMMEDIATE`, and C0 pins it deferred and ALWAYS. N36 would also fail C2, because `SET CONSTRAINTS` on a non-deferrable trigger errors. I found no mutation caught for the wrong reason.

**N7. L1–L7.** L1–L6 do not block. L7 does not hold as written: the template's stamps silently mis-order the history (B1) and give two cities in one group (S1). With B1's and S1's fixes it holds as stated, and the template-wide `clock_timestamp()` question can stay on the board.
