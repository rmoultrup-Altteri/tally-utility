# v5.4.2-18 review round 3 — Opus

Hashes match: patch cc820b6d… (866 lines, = sql/v5.4.2-18-…), battery 294ea5f8… (unchanged). Strict apply on a clean clone of `tally`: OK. battery-18: 107 PASS, 0 FAIL. migration-18.py against `tally` with PATCH18 = frozen r3: 52 PASS, all pass. I did not run mutations-18.py.

r2 folds: R10 is rewritten correctly (cause facts are Kyle's classification and must be restated by the future tariff kind or the core; limitations law bounds a delegated window); R11 records the R-39 placeholders and the "no limit or tariff's limit" question; the note/class agreement check is right and tested (P7ah…).

## Verdict: READY (conditional on Ryan's R10 ruling, as before). One should-fix, not blocking.

### S1. The "same as the protected row" guard only fires when such a row exists
The new branch (patch ~243-256) raises only `IF EXISTS (protected row of the same state, service, cause and effective_from whose facts DIFFER)`. When there is no protected row with that start, nothing is compared, and the delegation drops the cause facts unseen. That is the exact case R10 says cannot happen ("a delegation drops them only when the protected row of the same cause says the same").
Reproduction on a clone of `tally`: I added a closed historical row, TX gas unprotected crossed_meters, 1990-01-01 to 1995-01-01, with units_invariant = true, delivery reissue, uncapped and permitted, and the note "16 TAC 7.45 does not reach this class; …". The patch applied, and the row became `{"governs":"delegated_to_utility","citation":"16 TAC 7.45","note":…}`, with units_invariant = true and reissue gone. No protected row starts on 1990-01-01, so the EXISTS found nothing to compare.
The same hole opens whenever the protected and unprotected rows of a cause have different starts, for example after one class's row was closed and succeeded.
The 16 rows all start on 2004-07-12, so this database is unaffected; it bites only on rows beyond them.
Fix: invert the test. Raise unless a protected row of the same cause exists whose facts are equal. Choose that row either by the same start, or as every protected row of the cause overlapping the delegation's range, all equal. Add a P7 case (a delegation with no protected counterpart) and a mutation (EXISTS-differs vs NOT EXISTS-equal).

### N1. The tail NOTICE always says "16 Texas rows adopted"
It says so even when more legacy rows were adopted (17 in my probe). It is cosmetic; count the rows instead.

### Checked and fine
- The note/class agreement uses IS DISTINCT FROM over a NOT NULL key, so a reworded note or a relabelled class is refused both ways.
- The protected row's OLD columns are still present during the fill (they are dropped after it), so the comparison reads real values whatever order the UPDATE visits rows in.
- The outcomes are compared as sorted sets.
- The anchor is coupled to the outcomes under v1, so leaving it out of the comparison is sound.
