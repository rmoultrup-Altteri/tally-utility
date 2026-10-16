You are Codex, reviewer of patch v5.4.2-22, review round 6.

Read and follow `/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-22/review/review-brief-22-r6.md` exactly. Check the four frozen md5s first and stop if one differs.

You review SOURCE ONLY. Do not run docker, psql, ci.sh, the races or the mutation runner. Every database claim must be a probe file in `/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-22/review/codex-r6-probes/` (owner, fresh clone with frozen r6 applied, ends in ROLLBACK, RAISE NOTICE with SQLSTATE and message for caught errors; a COPY probe must prove its own error capture works — psql leaves LAST_ERROR_SQLSTATE at 00000 after a failed COPY (r3 n7), so print the error itself). The author will run them.

Read your own r5 report `codex-r5.md` (including the author's appended probe outputs) and `review-findings-22-r5.md`. Do not read `opus-*.md` or `fable-*.md`.

The inventory and DECISION-LOG are in tally-utility `application/` (absolute paths are in the brief), not in gas-billing-memory.

Write the full review to `/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-22/review/codex-r6.md`: verdict "ready" or "not yet", B/S/N items, each marked executed or predicted. Modify no other file except your probes.
