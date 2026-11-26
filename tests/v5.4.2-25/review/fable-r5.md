# v5.4.2-25 r5 — Fable's review (disputes, round-4 findings fixed)

**Date:** 2026-11-26. **Reviewer:** Fable (claude-fable-5-2). **Verdict: ready** — no blocking item, and I found no fault in the patch's code. One should-fix (S1, executed) is in the tests only: four of the comparator's "looser" branches have no fixture, and turning three of them into "cannot be ranked" lets the utility's looser term back into a record while the battery stays green. It needs fixtures and mutations, not a code change, and not another review round.

**Frozen files:** the ten md5s and the brief's own md5 match. Reviewed only those copies; read my own `fable-r4.md`, the r5 plan in full, the DECISION-LOG entry of 2026-11-26, and `r4-to-r5.diff` in full. Did not read any `opus-*` or `codex-*` file. Read the PATCH-LESSONS index and the sections on lock order as a rule, checks narrower than their claim, every branch and stated default tested, triggers running as every writer, and the rule-table fixture notes.

**Reproduced** (clones of `tally`, TEMP revoked from PUBLIC, `tally_app`, `tally_core`; frozen patch applied strictly, `search_path=''`, `check_function_bodies=on`):
- strict apply succeeded on both clones; the second run said "already applied (disputes exists); nothing to do";
- `battery-25-frozen-r5.sql` on `rv25fable`: 318 PASS, 0 FAIL, rolled back;
- `disputes-25-frozen-r5.sh` on fresh clones of its own, three runs: 29 of 30, then 30 of 30 twice. The one failure was **DR2** in the first run ("session B was never seen waiting on a lock"), while another reviewer's clones were busy on the same server: the flake the brief describes. DR16 and DR17 passed in all three runs, session A the loser each time, end states `disputed/open` and `disputed/open,withdrawn`;
- `terms-25.py` (live copy, md5 equal to the frozen one and to r4's): 0 failures;
- `assert_dispute_guard_invariants()` passes with the three changed hashes and the new function.

Not run, per the brief: `mutations-25.py`, `migration-25.py`, `ci.sh`. No role created, dropped or altered (probes used `SET LOCAL ROLE` only). Both clones and my files in the container are dropped. `tally`, `sql/tu.sql` and the repo are untouched (this file is my only write).

How the probes ran: single-session probes were appended to a copy of the frozen battery after D9i, inside its one rolled-back transaction, on its own D9 fixtures (`tight2_sql`, `det2_sql`, `combo`). The battery runs its D8 and D9 records as the owner; I re-ran the main ones as `tally_app` under `app.user_id`. The verdict mutations in S1 replaced `dispute_tariff_compare_sections` inside that same rolled-back transaction and ran the battery up to the H section (286 checks; the H section pins the function's hash). The two-session probe used committed rows on the race script's tenant in the race clone.

---

## B — blocking

None.

---

## S — should fix

### S1. Four "looser" branches of the comparator have no fixture; three of them guard what a record may hold — executed

r5's new distinction matters in one direction above all: a pair wrongly called "cannot be ranked" keeps the utility's looser term as an alternative, and the determination guard then admits a record under it. The battery pins that direction for two branches only (the law's undisputed charges against any strategy, D9d; fewer days against more days, D9e2) and for the ranked start (D9h). I changed each remaining "looser" verdict to "not comparable", one at a time, and ran the battery:

```
X1  end:      the tariff's "earlier of resolution and N days" against a law of "resolution"   -> SURVIVED (286 of 286)
X2  must-pay: a tariff of full_bill against a law's cap                                       -> SURVIVED
X6  must-pay: a smaller withholding fraction against the law's                                -> SURVIVED
X3  start:    fewer days from the same anchor                                                 -> SURVIVED (no recorded field; harmless to a record)
X4  must-pay: against a law of undisputed charges                                             -> caught at D9d
X5  end:      fewer days against more days                                                    -> caught at D9e2
X7  start:    a narrower kind of one order                                                    -> caught at D9h
```

What each surviving change would let through: X1, a last day recorded under a law that ends the shelter only at resolution; X2, the full bill demanded where the law caps it; X6, the utility's smaller withholding where the law allows more. The frozen code classifies all three correctly (the matrix in N3), so nothing is wrong today; the tests would not notice if it went wrong. `mutations-25.py` has no mutation in this direction at all: M157, M171 and M172 turn "not comparable" into "looser", never the reverse. This is the lesson `every-branch-and-stated-default-tested`.

**Fix (tests only):** one D9 case per branch on the real path, both sides — a tariff ending at day 60 under a law of resolution (a last day refused [D4s], none admitted); a full-bill tariff under a law's average cap (the tariff's component refused [D4g], the law's admitted); a 0.5 withholding under a law of 0.8 (the same); a direct-call check for the start. Then a mutation per branch, "looser taken as not comparable", anchored on those cases. No code change, so a mutation run is enough to confirm it.

---

## N — notes

- **N1. My round-4 findings — executed.** S1 (a list section replaced whole) is closed on both sides: the governing-body appeal survives a tightened regulator and its stage event is admitted, as `tally_app` too (my probe A1); the tariff's 10-day first decision and the law's 10-day regulator both stand; a stage before the wrong decider is still refused [D5b] (D9a2); the open filing window is kept beside the quicker decision (D9b); subjects combine in all three pairs of kinds (D9c–D9c3, and my reverse case: a listed tariff under a law of kind "any" excluding deposit and identity theft gives "any, excluding identity theft"). N2 (the lock order as a rule), N3 (the close-first race, DR16), N4/N9 (the comment), N1/N7 (the amount lines' comment), N5 (stage ids, as a contract line), N8 (residual R9) and N10 (`v_pos`) are taken. See N4 for what the rule still leaves out.
- **N2. The ruling's checks admit exactly what fits one of the two — executed.** Two averages kept both: as `tally_app`, the tariff's component `m1` and the law's `law:m1` are admitted, `m3` refused [D4g] with "m1 or law:m1" in the message. Sixty days against the regulator's close, on a bill of June 10: no last day admitted; August 8 (the 60th day) admitted; August 9 and August 20 refused [D4t]. A single end keeps [D4p] and [D4s] as in r4. If the combination returns NULL the component check refuses [D4g] (read, not run). Nothing else reads a section that may hold `either`: the event guard reads a stage's id and decider only; the readers return recorded fields only; the pending -26 patch reads neither function. I did not reach "tariff ends at the regulator's close, law ends by days" on the real path (7.45 refuses that tariff at filing, correctly); the guard's loop treats the two alternatives alike, so the order does not matter.
- **N3. The verdicts, pair by pair — executed (13 tariff terms against 18 law terms).** Every "looser" is right for every customer, given the comparator's long-standing premise that undisputed charges ask no more than any strategy. One premise worth a sentence in the comparator's comment: a tariff's average-usage cap against a law of undisputed charges is "looser" only if the average cap is read as "the undisputed part plus the disputed part up to the average"; if the core ever reads it as "the bill up to the average", a customer with a small average pays less under the tariff and the pair depends on the customer. Two pairs are called "not comparable" though one side wins for everyone, both on the shelter's start, which has no recorded field, so no record is affected: a tariff of "within N days" under a law of "any time" (the law's wins), and a tariff of "any time" under a law of "within N days" or "on a regulator complaint" (the tariff's wins; and such a tariff is still refused at filing, as before r5). Both alternatives reach the core, which picks the wider.
- **N4. One deadlock is still outside the rule as stated — executed.** The rule orders a dispute's lock against its reading's row, and two readings against each other. It does not order two disputes' locks. Two clerks each recording an amount on disputes D1 and D2 of one customer, in opposite order, with no close and no reading involved:
  ```
  A: BEGIN; amount on D1; (2 s); amount on D2; COMMIT        -> committed
  B (1 s later): BEGIN; amount on D2; amount on D1; COMMIT   -> ERROR deadlock detected (40P01), on the advisory lock in dispute_lock
  end state: A's two amounts, none of B's
  ```
  "Writers retry 40P01" covers it. One more sentence in the header closes the rule: a transaction that takes more than one dispute's lock takes them in id order (as the reading's move already does) or can deadlock with another. r5 adds no lock: the three changed functions and the new one read only their arguments, the cited rows and `dispute_subjects`.
- **N5. When the law inserts a stage in the middle, the tariff's displaced stage is duplicated after the law's last — executed.** Tariff: employee, regulator (15 days, open filing window). New law: employee, governing body, regulator (10 days, filed within 30 days of the prior decision). The combined stages are `s1` employee, `law:s2` governing body, `s3` regulator (the law's: 10 days, 30-day window), then `s2` regulator (the tariff's: 15 days, open window). All four stage events are admitted as `tally_app`, including `law:s2` (the marked id is recordable; D9b3 checks it by direct call only) and a `stage_entered` naming the tariff's 15-day regulator stage. Nothing is dropped, so the standing rule holds, but the document has two stages before one decider, and the tariff's open window was not merged into the law's regulator stage because the merge matches by place. Either match a displaced stage to the law's later stage of the same decider, or add a contract line: where two stages share a decider, the core treats them as one with the wider window and the quicker decision. Add the real-path case for a `law:` id to the battery.
- **N6. The law's `final` flag reaches the combined document only when the stages section has a finding — executed.** A tariff whose regulator decides in 10 days, not final, with its own appeal after, under a law whose regulator is final: no finding, so the tariff comes back as it is and the regulator reads `final: false`. The same tariff with a 15-day regulator has a finding and reads `final: true` (D9a). The comment says both things (a tariff no looser comes back as it is; the law's place keeps the law's flag), and the contract line already says the law's final decision binds; add to it that the core takes `final` for a law's stage from the law row, not from the combined document.
- **N7. Paths around the new rule.** The guards are `ENABLE ALWAYS` and the battery's D9 refusals run as the owner, so a superuser history load meets [D4g] and [D4t]; my probes show the same as `tally_app`. All four functions are invoker-rights and STABLE; `tally_app` and `tally_core` can each call the comparator's structured form and the combination (five findings at once: stages, subjects and start looser; end and must-pay not comparable; each section combined independently). A marked id cannot collide: the schemas' id pattern admits no colon. A filing at the tariff's insert is refused as before, as `tally_app` (the N section and D9i).
- **N8. -17's template and -23's seal.** Battery P and H checks pass. The diff has no hunk in the seal invariant; the manifest hunks are three changed hashes and one new function in its three lists (body, settings, grants).
- **N9. Tests otherwise.** New checks have both sides. M158 is caught for a slightly indirect reason (with the alternatives unread, the guard meets a term of no known kind and admits everything, so D9g3's refusal fails); it is still the damage the label names. D9g and D9g3 sit a week either side of the boundary; my A4/A5 pin the 60th day and the day after, worth adding.
- **N10. Residuals R1–R9.** None blocking.
