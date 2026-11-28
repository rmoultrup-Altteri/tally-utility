# Fable review: v5.4.2-26 r2 (collections decisions and field verification)

**Date:** 2026-11-27. **Verdict: not yet.**

Thirteen of round 1's fifteen findings are fixed, and I could not get round them. Two are only partly fixed, both shown by running them:

- **The late-fee line gate (item 7).** One gated late-fee charge lets any number of late-fee or penalty lines, of any amount, onto the customer's bills. I issued a bill carrying a $500 penalty line that names a $5 charge. That is B1.
- **The execution's date (item 9).** "Not before its order was recorded" compares against a timestamp the application can write. One UPDATE of the order removes the bound. That is S1.

r2 also introduced one new problem (S2): a block left on a meter that has since been removed stops every location-wide act at that address, and can only be lifted by a decision dated in the past.

## What I checked and how

- **Hashes:** the seven frozen files and the brief match their md5s.
- **Clone:** `rv26fable` from `tally`; TEMP revoked from PUBLIC, `tally_app`, `tally_core`; frozen r2 applied strictly, twice (second run: "already applied"). Dropped at the end; my files removed from the container. No repo file touched but this one. I did not read `opus-r2.md`, `codex-r2.md` or Codex's round-2 probes.
- **Reproduced:** `battery-26` 249 PASS, 0 FAIL. `collections-26.sh` 13 PASS (CR1 to CR8d). `battery-21` (frozen copy) 143 PASS, 0 FAIL, with -26 applied.
- **Not re-run** (forbidden or out of scope): `migration-26.py`, `mutations-26.py`, `fill-manifest.py`, `ci.sh`. I read all three scripts.
- **Probes:** the battery's fixtures followed by my statements as `tally_app`, rolled back; and, where two sessions or separate commits were needed, committed runs on the clone. Each item says **executed** or **predicted**.

---

## Round 1's findings, one by one

| Plan item | What it was | State | How I tried to get round it |
|---|---|---|---|
| 1 | An execution under another customer's decision | **Fixed** | Read; battery R1c. The visit guard compares the decision's customer with the order's. |
| 2 | A location-wide block ignored by a meter-level eligible decision | **Fixed**, with a side effect (S2) | Executed for the leg the battery lacks, the execution: a blocked location-wide execute decision stops an execution under the meter's eligible one; a blocked meter stops an execution of an order naming no meter; a blocked meter e9 does not stop meter e8 (as designed). Executed as a race: session A holds an uncommitted location-wide block for 4 s, session B creates an order under the meter's eligible decision; B was seen waiting on the lock, then refused [A10]. |
| 3 | An executed order cancelled under REPEATABLE READ (my B1) | **Fixed** | CR8c and CR8d pass. The status update of a disconnect order is refused outside READ COMMITTED. |
| 4 | Multi-row dunning inserts freeze a wrong previous stage | **Fixed** | Executed, including under REPEATABLE READ for the ungated steps, which take no subject lock (see N1). A caller's `record_seq` is overwritten. |
| 5 | Actor links not tied to the utility; a platform administrator approving as themselves | **Fixed** | Executed: a deactivated tenant_admin is refused (new: `is_active`); battery R5a to R5d. |
| 6 | A repeat late fee or reminder moves the stage back | **Fixed** as ruled; one detour (N2) | Executed. |
| 7 | A late fee gated by one label only | **Partly fixed: B1** | Executed. |
| 8 | Surplus approval links (my S6) | **Fixed** | Read; R8a, R8b. |
| 9 | A backdated execution | **Partly fixed: S1** | Executed across separate transactions. |
| 10 | Replica-mode load leaves the flag false (my S5) | **Fixed**; load order matters (N4) | Executed. |
| 11 | No invariant function | **Fixed**; one gap worth closing (S3) | Executed 17 kinds of drift. |
| 12 | A void bill counts as issued | **Fixed** | Read; R12a to R12c. |
| 13 | Blank captured values (my S3) | **Fixed** | Read. A blank aborted visit can still be approved, but the execution must then capture what that visit saw [F3c] and something alphanumeric [F2e], so the two cannot both hold. |
| 14 | One disconnection on one bill only (my S2) | **Fixed** | Read; R14a, R14b. A log line can land on a draft bill (N6). |
| 15 | Race verdicts indistinguishable from timeouts | **Fixed** | Read the runner: a leg that failed for want of a lock wait, or because session A failed, is not counted as a catch. |

My round-1 S7 (the UTC day) is now stated in residual R1, as asked. My round-1 notes N3 (a late fee logged after its charge was voided) is fixed (R15).

---

## B — blocking

### B1. One gated charge unlocks any number of late-fee lines, of any amount (executed)

**What it does.** The new guard on bill lines asks only that a `late_fee` or `penalty` line names a charge of the bill's customer that cites a decision. It does not ask whether that charge is standing, whether it is already billed, or what its amount is. So once a customer has ever had one gated late fee, any late-fee or penalty line can be put on any of their bills by naming that charge again.

**Run (as `tally_app`, rolled back):**

```
late-fee decision for bill 01, its charge CB of $5.00                      admitted
draft bill 0a: a late_fee line of $5.00 naming CB                          admitted
               a penalty line of $500.00 naming CB again                   admitted
bill 0a moved draft -> pending (issued)                                    admitted
bill 0a: pending; lines base_charge 60.00, late_fee 5.00, penalty 500.00
```

Separately: after CB was voided, a new late-fee line naming the void charge was admitted too.

**Why it blocks.** The patch header now says a late fee "reaches a bill only as the line of its gated charge", and the invariant the patch serves is that a collections act (here, billing a late penalty) happens only on a recorded eligible decision. The $500 line has no decision behind it; it borrows one. Round 1's finding was that a late fee could be billed with no decision; that is still so for every customer after their first late fee. It is about where money ends up, so I rate it above the other partly fixed item.

**Options.**
- (a) Tighten the line guard: the named charge is standing (not void, waived or awaiting rebill); the line's amount is the charge's; no other late-fee or penalty line on a bill that is not void names the same charge (a void-and-rebill puts it on the replacement bill, so a plain unique index would be wrong). Two lines racing for one charge need the charge's row locked. I would do this.
- (b) Say plainly that the database does not tie any bill line to its charge's amount or to one billing (true today for every ad hoc charge type, not only late fees), reword the header and the trigger comment, and carry it as a residual. That needs Ryan's word, since it leaves a late penalty billable without its own decision.

Either way add the test: a second line on one charge, a line of a different amount, a line on a void charge. The mutations for this guard (M142, M143) test only "no charge" and "an ungated charge".

---

## S — should fix

### S1. The execution's "not before its order" bound reads a timestamp the application writes (executed)

**What it does.** [F2f] refuses an execution whose arrival is before `service_orders.created_at`. That column has no stamping trigger and `tally_app` holds INSERT and UPDATE on it; the order guard freezes type, customer, location, meter and decision, not `created_at`. The decision's `created_at` is stamped by the database, so that half of the bound holds.

**Run (separate committed transactions on the clone):**

```
01:31:56  execute decision XE recorded (eligible, today)
01:31:59  order decision and order SOE recorded
          execution of SOE, arrived 01:31:57 (before the order existed)        refused [F2f]
          UPDATE service_orders SET created_at = '2020-01-01' WHERE id = SOE   admitted (tally_app)
          the same execution, arrived 01:31:57                                 admitted, matched = true
```

Also executed: an order born with `created_at = 2020-01-01` is admitted and keeps it; a decision born with `created_at = 2020-01-01` is admitted but stamped `now()`.

This is round 1's finding (an execution dated before its order existed, under an older execute decision that is still live) with one extra statement. **Suggested:** compare the arrival with the order's own decision's `created_at` instead (stamped, add-only, already loaded by key), or stamp and freeze `created_at` for a disconnect order in `enforce_disconnect_order`. The first touches no mirrored column.

**The test is weaker than its label.** Battery R9a ("a second before its order and decision were recorded") cannot tell the two bounds apart, because one transaction stamps both at the same instant; mutation M147 removes both together. A mutation that drops only the order bound, or only the decision bound, would survive. The migration or race harness, which commits, can test them separately.

### S2. A block left on a removed meter stops every location-wide act there, and can only be lifted by a back-dated decision (executed) — new in r2

**What it does.** The new rule [A10] treats the live decision of every meter that ever had one at the location as binding on an act that names no meter. A decision for a meter must be dated a day the meter was deployed there [C3e]. So when a meter with a blocked decision is swapped out (routine), its block stays live, and no decision dated after the swap can supersede it.

**Run (location L5: meter e5 until 2026-04-01, e7 since):**

```
March: blocked order decision for (L5, e5), payment pending                      admitted
today: eligible location-wide order decision at L5                               admitted
       an order at L5 naming no meter under it                                   refused [A10], citing e5's decision
       an eligible decision for (L5, e5) dated today, superseding the block      refused [C3e]: e5 not deployed there today
       the same dated 2026-03-31 (e5's last day), valid a week                   admitted
       the order at L5 naming no meter                                           admitted
```

The same happens for an execution: an old blocked execute decision on e5 stops today's execution of an order naming no meter, until an "eligible" execute decision for e5 dated 2026-03-31 is written.

It fails toward protection, and naming the current meter on the order avoids it. But the only way to clear the block is for the core to record that it evaluated a removed meter as eligible on a past date, which did not happen; the decision record is then untrue. **Suggested:** [A10] counts a meter's decision only if that meter is deployed at the location on the act's date (the function already has the date); the location-wide decision always counts. Add the swapped-meter case to the battery.

### S3. The stage now rests on the dunning events staying unedited, and no invariant pins that (executed)

**What it does.** Since r2 the stage a step moves from is read from the events, not from the fenced column on the bill. That is sound today: `tally_app` holds only SELECT and INSERT on `dunning_events`, and its add-only trigger (from an earlier patch) refuses edits (executed: the application's UPDATE is refused). But neither is in -26's invariant, nor in any earlier one:

```
GRANT UPDATE ON dunning_events TO tally_app            not caught by any assert_* function
DROP TRIGGER append_only ON dunning_events             not caught
ALTER TABLE dunning_events ENABLE TRIGGER append_only  (origin only)  not caught
```

**Suggested:** add `dunning_events`' add-only trigger and its table grants to `fill-manifest.py`'s lists. Two lines; the manifest refills itself.

Other drift, for the record (all executed). Caught by -26's function: a guard disabled or switched to origin-only; a guard made SECURITY DEFINER; EXECUTE granted to PUBLIC; a check constraint or unique index dropped; forced row security lifted. Caught by the tenant-isolation function: the policy dropped; a permissive policy added. Not caught, and harmless or unavoidable: a column-level grant on a new table (the add-only trigger still refuses the write); a function's strictness or volatility changed with the same body; the dropped invoice columns re-added; the invariant function itself replaced. None of these needs action; say in the function's comment that it reads table-level grants only.

**The mutation runner dropping the invariant's call** hides nothing I could find: the call would otherwise refuse every mutated body at apply, and the battery still runs the invariant last (R11a), after the named checks. A stale manifest fails the unmutated apply, which every run starts from.

### S4. Comments that will be mirrored still describe round 1 (read)

These go into `tu.sql` as catalogue comments and stay there:

- The comment on table `service_order_field_approvals` still says the session "must be a supervisor (session_is_supervisor: a tenant_admin or a platform admin)". r2 does the opposite: a platform administrator as themselves is refused. A reader of the schema will be told the wrong rule about who may approve a disconnection.
- The comment on `adhoc_charges.collections_decision_id` says "Required for a late fee, absent otherwise"; it is now required for a `penalty` charge too. The comment on `enforce_adhoc_charge_decision` lists the trigger's columns without `charge_type`.
- Nothing tells a reader that charge type `penalty` now means a late penalty only: any other penalty a utility charges (tampering, say) must use another type, because a `penalty` charge needs a late-fee decision naming a bill.
- The header's test line says "CR1-CR8c" and "P0-P7"; the scripts run to CR8d and P7b. The header's "Builds on" still lists `session_is_supervisor`.

---

## N — notes

- **N1. The stage's order under concurrency is sound (executed).** Two sessions, one bill, READ COMMITTED: CR6 and CR6b. For the ungated steps, which have no isolation pin, I ran session A at REPEATABLE READ with an old snapshot while B recorded a step: A failed with a serialization error both when B moved the stage and when B's repeat step left it where it was. That second case works only because the move rewrites the bill's row even when the stage is unchanged. Worth one comment line on `dunning_move_stage`, so nobody later "optimizes" the no-op update away. When B's step moves no stage (`reconnected`), A is admitted and the chain is still right.
- **N2. Forward-only holds against one step, not two (executed).** A bill at `late_fee_assessed`, then `resolved`, then a reminder: stage `reminder_sent`. Both steps are ungated. From `written_off` a reminder likewise reopens the bill. I think the built rule is the right one: after a payment bounces or a plan breaks (the plan-broken step itself moves nothing), the first new step is a reminder and the bill should follow it. It is residual R6's point, not a new hole. Answering the brief: I would keep "an escalation step from payment plan, resolved or written off moves to its own stage".
- **N3. The approver (read, executed).** No function in the mirrored schema writes approvals, and no earlier battery relied on a platform administrator approving (the author's `ci.sh` run covers them). What is now refused that was not: a superuser history load of approvals, in origin or replica mode, unless the loader sets `app.user_id` to an approver who is still an active tenant_admin of that utility (executed: refused with no user set). An approval by a supervisor who has since left cannot be loaded. Acceptable while nothing is live; say so in DEPLOY-VERIFICATION.
- **N4. Replica-mode load order (executed).** With foreign keys off, an active protective enrollment loaded before its customer row recomputes nothing; the customer row carrying `do_not_disconnect = true` is then refused by the fence, and loaded with `false` it stays false under an active protective enrollment. The load must go program types, customers (flag false), then enrollments. One sentence in DEPLOY-VERIFICATION. No other load path misbehaves that I found: `recompute_do_not_disconnect` reads two tables and writes one, and the other enrollment guards were already ALWAYS.
- **N5. The late-fee line trigger's writers (catalogue).** Only `tally_app` holds INSERT or UPDATE on `invoice_line_items`; no function in the schema writes it; `tally_app` can read both tables the guard reads. So no other role is refused by a permission it lacks. The guard fires on UPDATE of the three columns it reads (executed: a base-charge line turned into a late fee, and a late-fee line re-pointed to no charge, are refused). A line typed `adhoc` or a charge typed `miscellaneous` described as a late penalty is admitted (executed); that is the limit of any type-based gate, and belongs in the application contract.
- **N6. A log line can land on a draft bill (executed).** The disconnection's log line, and a plain reminder, were admitted on draft bill 04, which then showed `draft / disconnected`. "Each bill of its customer" has no test of the bill's state. Low; the core chooses the bills.
- **N7. `battery-21` now needs -26.** It passes with -26 applied; on `tally` as it stands (no `collections_decisions` table) it cannot run. That is fine while -26 stays in `ci.sh`'s pending list ahead of anything that runs battery-21, and worth a line on the board so another stream is not surprised.
- **N8. Execution dates and a field tool that syncs late (predicted).** A late sync is admitted if the execute decision was recorded before the arrival, the arrival is on the decision's UTC day, and the decision is still live and no covering block has been recorded since. Two honest flows are refused: a crew that arrives and then asks for the day's check (arrival precedes the decision), and a visit synced after the core has re-evaluated the address. The contract in R1 (the decision is written before the visit) covers the first if the core follows it; the second means a disconnection that really happened may have no executed-visit row. Not for -26 to solve; the core's contract should say what the tool records then.
- **N9. "Decision recorded before the act" for executions only (executed).** I agree it cannot be applied to a charge's date. For a notice I half disagree: today the core can write a notice decision "evaluated" 20 days ago and log the shutoff notice as sent 20 days ago (both admitted; the event shows `event_date` 2026-11-08, recorded 2026-11-28), and the notice's date is what starts a waiting period. The record does show both dates. Suggested for the contract: a waiting period counts from the later of the notice's date and the day it was recorded.
- **N10. Tests missing,** beyond those named in B1, S1 and S2: [A10] on an execution (my probe passes; the battery tests the order and the notice only); a race on [A10] (a block being written while an act is recorded; my run passes); CR8c at SERIALIZABLE, which the plan promised (same code path).
- **N11. Residuals.** R1 as extended, R6 and R7: none blocking. R6 should name N2's detour in so many words.

## Answers to the brief's four questions

1. **Round 1's findings:** thirteen fixed; item 7 partly (B1); item 9 partly (S1).
2. **What r2 broke:** the shared location lock and [A10] are complete for an order naming no meter, a notice with and without a meter, and an execution, and a concurrent decision cannot escape (executed); the side effect is S2. The stage's ordering is sound (N1). The line gate refuses no mirrored path (N5) but is too loose (B1). The approver change refuses nothing mirrored (N3). A caller can set an order's `created_at` (S1). The invariant catches the drift it lists; S3 is the one gap I would close. The ALWAYS trigger misbehaves on no load path, given the load order (N4).
3. **The tests:** R9a and M147 are weaker than their labels (S1). No mutation I read passes for the wrong reason. "Executions only": agreed, with N9.
4. **Residuals:** none blocking.
