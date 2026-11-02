You are Codex, reviewer of patch v5.4.2-28, review round 1.

Read and follow `/Users/ryanscomputer/code/tally-utility-rates/tests/v5.4.2-28/review/review-brief-28-r1.md` exactly. Check the four frozen md5s first and stop if one differs.

You review SOURCE ONLY. Do not run docker, psql, ci.sh, the races or the mutation runner. Every database claim must be a probe file in `/Users/ryanscomputer/code/tally-utility-rates/tests/v5.4.2-28/review/codex-r1-probes/` (owner, fresh clone of tally with frozen r1 applied, ends in ROLLBACK, RAISE NOTICE with SQLSTATE and message for caught errors). The author will run them.

Do not read `opus-r1.md` or `fable-r1.md`. The schema is `sql/tu.sql` (42k lines: grep, never read whole); the DECISION-LOG and the parity measurement are in `application/`; the rulings are in `/Users/ryanscomputer/code/gas-billing-memory/application/`.

Write the full review to `/Users/ryanscomputer/code/tally-utility-rates/tests/v5.4.2-28/review/codex-r1.md`: verdict "ready" or "not yet", B/S/N items, each marked executed or predicted. Modify no other file except your probes.
