# Opus review — scenarios round 3 (SCN-0060 – 0077), 2026-11-05

Condensed from Opus's five messages. Checked against live `tally` (selects only), tu.sql, -10/-21/-23 sources, the measurement, DECISION-LOG 11-05, GBM outlines. Figures in 0069 ($64.20, +$1.63), 0070 ($66.74) and 0076 ($65.83) recompute; weekdays correct. 18 findings: 7 must fix, 8 should fix/add, 3 notes.

## Must fix

1. **0062 / 0065 / 0068.** Read-only Tally staff conflicts with 0062: the Rule and (f) have a platform administrator binding logins and restoring a supervisor, but `users` is a tenant table and the 11-05 ruling makes plain platform access read-only; impersonation can't help when the supervisor to impersonate is switched off. Nobody can restore Bluebonnet's supervisor or provision a new utility's first tenant admin. Fix: Open (Ryan): user administration as an exception, or the last active supervisor can't switch itself off.
2. **0067.** "Built within a run" covers only UNIQUE (billing_run_id, meter_id). Nothing makes an outcome final (tally_app has UPDATE on billing_run_meters; its only trigger is the exception/master gate) and nothing stops a failed run moving back to in_progress. (b)'s change of an outcome is accepted; (c)'s "BR-11 stays as it was" is not enforced.
3. **0067 (a).** "No size on file" is not an incompleteness `meter_master_incomplete_reasons()` checks (it checks rollover point and dial count both missing, pressure class missing, meter factor missing on an elevated-pressure meter). Use "no pressure class".
4. **0076.** Not "the pair of Nov 16": -10 fixes an ordinary bill's priced-at date to its period end (Nov 13; -10:946), recorded instant the run's.
5. **0071 Rule.** "A bill outside a run (a rebill) takes its own" is wrong: a correction is on a correction run, its instant inside that run's window or exactly the replaced bill's (replay; -10:660). Same phrase in the R-22 DECISION-LOG entry: flag to Ryan.
6. **0061 last bullet; 0062 (a).** A no-user or switched-off session still reads the 32 shared tables (no RLS, SELECT to tally_app: places, place_facts, backbilling_rules, rule_parameter_values, deposit_rules…). Say "no utility's rows".
7. **0063 Status; tenant-isolation.md header.** -29 was mirrored 2026-11-05 (tu.sql:47268; board), not in review.

## Should fix / add

8. **0062 (b), (c), (e)** can't be asserted as written: (e) PL-admin's row is hidden from BB-admin (another tenant), so 0 rows change rather than the trigger's refusal; (c) BB-clerk is switched off from (a) and sees no users row; (b) an unbound login has no user to set (AC-43). Say which session runs each step and whether a test checks an error or zero rows changed.
9. **0074.** (i) Eight records, not four (payment, its posting entry, application, its undo, the ledger reversal, the new payment, its posting, its application). (ii) The bill's paid/partial status is still app-written and can disagree with the derived position (CI-013 residual, -23 R3).
10. **0069.** (i) The rebill's recorded instant: inside the correction run ($65.83) or the original's (replay, $64.20, corrects nothing); add the replay branch. (ii) Carry the Kyle question from SCN-0033 (does the $1.63 go to the next bill?).
11. **0071 Given.** "From Dec 1" implies a mid-period rate change the cast doesn't have, and a December period straddling Dec 1 with no stated method; the $14.57 version's recorded date is unstated. State the period, prior value, method (or a cycle boundary) and when it was recorded.
12. **0066 (d).** A failed job frees its file even if rows were committed (`import_jobs_file_once` excludes failed/cancelled; partial_commit allowed; nothing ties failed to committed_rows = 0), so a re-import can post twice. Separate branch; say whether payments posted; add the double-posting case.
13. **0073 (e).** A draft is discardable only with no locked read or billed charge (enforce_invoice_immutable's DELETE branch); a run's draft holds BB-01's read.
14. **0067 (d).** "One live bill per meter and period" is wider than the read lock: a second run billing the period from an estimate or a replacement read is not caught (CI-119). Test expected to fail, or narrow the Rule.
15. **0076.** List every snapshot input class the test asserts (meter multiplier/factor, zone and place, customer class and attributes, period dates, proration method), not readings, rates, gas cost and tax only.

## Notes

16. **0071.** The GBM bi-temporal outline (A4) records a deliberately mixed basis for a rebill (original rates, current tax rules, operator's choice); -10 allows one priced-at date. Say it is ruled out, citing the ruling, or Open.
17. **0064.** Two more built link checks: -20's `enforce_attach_to_live_invoice` (a read or charge attached to another tenant's bill is refused), and the 86 two-column keys. Say (c) is accepted today. (Opus counted 271 one-column links vs the log's 273; method difference.)
18. **0060.** (i) Outside ids are unique per utility for meters and premises too; cover them in (c). (ii) tally_app can UPDATE tenant_sequences; "never reuses a number" holds because the unique key refuses the duplicate, not the counter.

Checked, no finding: 0060 uniqueness; 0061 (e); 0063 SELECT-only; 0064 (a); 0065 (b) admin writes today; 0066 fingerprint and previews; 0072; 0073 (a)–(d); 0074 write-once and status moves; 0075 delete triggers; 0076 snapshot immutable.
