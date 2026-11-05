# Fable review — scenarios round 3 (SCN-0060 – 0077), 2026-11-05

Condensed from Fable's three messages. Checked against live `tally` (read-only), -10's coordinate check, the -19/-20/-21/-23 guards, the 11-05 rulings, the three GBM outlines. Figures in 0069 ($64.20, $65.83, +$1.63), 0070 ($66.74) and 0076 ($65.83) recompute. 12 findings: 2 must fix, 7 should add, 3 notes.

## Must fix

- **F1. 0076.** The snapshot check fixes an ordinary bill's priced-at date to its period's last day (`calculation_snapshot_coordinate_violation()`: "valid_at must equal the invoice's period_end"), the recorded instant at or after the run's `started_at`. Fix: priced at Nov 13, as known at the run's instant. Carry into 0071's Rule (period's last day for an ordinary bill; the elected rate date for a correction).
- **F2. 0071.** "A bill outside a run (a rebill) takes its own" instant: the schema refuses an off-run rebill (a correction must sit on a correction run, CI-005, -10). A correction admits any instant at or after its run's start, or exactly the replaced bill's own (replay). Fix: a correction run takes its own start unless the operator elects a replay; say which 0069/0070 use (the correction run's start). Tell Ryan the R-22 entry's phrase doesn't match the schema.

## Should add

- **F3. 0071 Given.** The "from Dec 1" R-R value falls inside a December period that straddles Dec 1, with no stated split method (Kyle 11-03, answer 1); a test must guess. Date it before the period (say Nov 1) or state the method.
- **F4. 0063 (d).** Contradicts `backbilling.md` line 5: a city's backbilling lookup refuses today, and under answer 8 reads a delegated row plus its own tariff record, never the Texas terms. Make (d) a plain read of the shared row; a Bluebonnet correction never reads the Texas row.
- **F5. 0073 (e).** `enforce_invoice_immutable()` refuses a draft's delete while a locked read or billed one-off charge is attached; a run's draft holds its read. Discard through the void (posts nothing, SCN-0003) or after release; a bare draft may be deleted.
- **F10. Gap: dry run** (bi-temporal outline A5; `billing_runs.is_dry_run`): issues and posts nothing, locks no read, never presented as a bill.
- **F11. Gap: A16** — whether a refused cross-utility write, duplicate import or double billing is itself recorded for the utility. One Open for Ryan.
- **F12. Gap: CI-004's other current-value facts** (meter multiplier and factors, zone assignment): a back-dated correction after a multiplier change, the shape of SCN-0077 (c).

## Notes

- **F6. 0069 / 0070.** The database requires the close's reason, not its closer (`rate_item_versions_close_consistent_check`: `recorded_until`, `closed_type`, `closed_reason`; `closed_by` nullable). Mark the closer as the app's (AC-43) or flag to rates. And the successor names the row it supersedes (`supersedes_id`), not the reverse.
- **F7. 0067 (a).** No outcome is "incomplete record"; use "skipped as unbillable, reason: meter record incomplete"; the open exception maps to `skipped_pending_review`, BB-01's error to `failed_calculation`.
- **F8. 0062 (c).** A switched-off user's own row is unreachable: its save touches nothing; binding BB-clerk2 is a raised refusal.
- **F9. 0070.** "Entered on the wrong utility's sheet" contradicts SCN-0061; "a supervisor retracts" has no source. Use "never adopted; entered in error" and a clerk, or mark the supervisor invented.

Checked true on tally, no finding: 0060, 0061 (102 policies; USING doubles as the write check), 0062 (binding guards), 0063 (SELECT-only shared tables), 0064 (refund check; 273 matches), 0065 (admin writes today), 0066 (`import_jobs_file_once`; final status), 0067 (b)/(d) (unique per run; read lock), 0068 (no impersonation object), 0072, 0073 (a)–(d), 0074, 0075 (no end date on cycles; delete refused), 0077.
