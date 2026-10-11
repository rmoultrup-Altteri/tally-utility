# Review round 6: v5.4.2-18 (Opus, Fable, Codex: a delta check)

**Frozen r6** (`/Users/ryanscomputer/code/tally-utility`): patch `tests/v5.4.2-18/review/patch-18-frozen-r6.sql` md5 `baa6e72a0555c344473eb3b099c44fca` (895 lines); battery `battery-18-frozen-r6.sql` md5 `7adbcf318e773009fbcfb15c2fbb269f`. All three r5 reviews said ready; `diff patch-18-frozen-r5.sql patch-18-frozen-r6.sql` is the whole change. Briefs: `review-brief-18-r1.md` (full questions), `-r5.md`.

**r5 -> r6:**
- Codex r5 should-fix (reproduced by its probe 06): the migration now takes `LOCK TABLE backbilling_rules IN ACCESS EXCLUSIVE MODE` first, so a delegation committed by a writer already in flight is waited for and seen by the anchor pre-flight. Test P11 (a real second session; red on r5, where it aborted late at the fingerprint with the wrong message), mutation M107.
- Opus r5 note: priority capped at 2147483647 (-13's integer column; a C# core may read an int). Battery D40c, mutations M66 (re-pointed), M108.
- Opus r5 notes: the pre-flight HINT now says what to do with a delegation overlapping twins of different anchors; the adoption check's comment says the anchor is compared by the pre-flight; migration-18.py's cleanup drops all its databases.
`tests/ci.sh` passes; 107 mutations, all caught.

Look for what the lock breaks (idempotent re-run, deadlock with the later ALTERs/registration, the battery's and migration's own sessions, lock-wait behavior) and anything the cap breaks. R10 is Ryan's. Reports to `opus-r6.md`, `fable-r6.md`, `codex-r6.md`; Opus/Fable use own database prefixes and clean up; Codex writes probes to `codex-r6-probes/` and the author runs them.
