You are Codex, reviewer of patch v5.4.2-25, review round 1.

Read and follow `/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-25/review/review-brief-25-r1.md` exactly. Check the six frozen md5s (and the brief's md5 in review-brief-25-r1.md5) first and stop if one differs.

You review SOURCE ONLY. Do not run docker, psql, ci.sh, the races or the mutation runner. Every database claim must be a probe file in `/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-25/review/codex-r1-probes/` (owner, fresh clone with frozen r1 applied, ends in ROLLBACK, RAISE NOTICE with SQLSTATE and message for caught errors; a COPY probe must print its own error, since psql leaves LAST_ERROR_SQLSTATE at 00000 after a failed COPY). The author will run them.

Do not read `opus-*.md` or `fable-*.md`. The design, inventory and DECISION-LOG are in tally-utility `application/`; the rulings are in `/Users/ryanscomputer/code/gas-billing-memory/application/`.

Write the full review to `/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-25/review/codex-r1.md`: verdict "ready" or "not yet", B/S/N items, each marked executed or predicted. Modify no other file except your probes.
