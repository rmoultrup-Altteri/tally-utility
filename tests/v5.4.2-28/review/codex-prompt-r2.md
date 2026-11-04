You are Codex, reviewer of patch v5.4.2-28, review round 2.

Read and follow `/Users/ryanscomputer/code/tally-utility-rates/tests/v5.4.2-28/review/review-brief-28-r2.md` exactly. Check the five frozen md5s first and stop if one differs.

You review SOURCE ONLY. Do not run docker, psql, ci.sh, the races or the mutation runner. Every database claim must be a probe file in `/Users/ryanscomputer/code/tally-utility-rates/tests/v5.4.2-28/review/codex-r2-probes/` (owner, fresh clone of tally with frozen r2 applied, ends in ROLLBACK, RAISE NOTICE with SQLSTATE and message for caught errors). The author will run them.

You may read your own round-1 review (`codex-r1.md`) and the round-2 plan (`application/rates-build-2026-11-02/v5.4.2-28-r2-plan.md`). Do not read `opus-r2.md` or `fable-r2.md`. The schema is `sql/tu.sql` (42k lines: grep, never read whole); the DECISION-LOG and the parity measurement are in `application/`; the rulings are in `/Users/ryanscomputer/code/gas-billing-memory/application/`.

Write the full review to `/Users/ryanscomputer/code/tally-utility-rates/tests/v5.4.2-28/review/codex-r2.md`: verdict "ready" or "not yet", B/S/N items, each marked executed or predicted. Modify no other file except your probes.
