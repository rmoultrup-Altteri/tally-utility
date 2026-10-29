# tally-utility — working notes for Claude sessions

The TallyUtility database schema (PostgreSQL 16): `sql/tu.sql` plus numbered patches. What the product is: `CONTEXT.md`. Where the work stands right now: your stream's file in `handoffs/`, found through the board (`HANDOFF.md`), and nowhere else.

## The goal

The C# core build starts when four steps are done, in order (Ryan, 2026-10-13; no date). Since 2026-10-29, step 2 runs beside step 1; step 3 waits for both:
1. schema parity with the invariants CI-001…CI-135 (the live grades: `application/invariant-parity-measurement-2026-10-13.md`, re-graded only after a mirror);
2. scenarios and a test strategy;
3. a phase plan;
4. the build.

## Session start

Several sessions run at once, one per stream, each in its own clone (`~/code/tally-utility`, `~/code/tally-utility-rates`, `~/code/tally-utility-scenarios`). `HANDOFF.md` is the board, not a handoff.

1. `git pull --ff-only`, then `git -C ../gas-billing-memory fetch` and check `HEAD..origin/main` there. Kyle pushes rulings to GBM `main` directly; read them before saying anything waits on him.
2. Read `HANDOFF.md` (the board). Find your working directory in its Streams table, then read that stream's file in `handoffs/`. Its first line names its folder; if that isn't your working directory, stop and ask Ryan. Read the board's notes for your stream.
3. Commits by other streams are expected. When checking for drift since your handoff, count only commits that touch your stream's handoff or files.
4. If the work needs Docker, check `docker ps -q --filter ancestor=crystaldba/postgres-mcp | wc -l` first. Leaked containers run tally-pg out of memory.

Don't open the CHANGELOG, DECISION-LOG or the review files at the start. Open them when a task needs them.

## Reading big files

These are too big to read whole. Grep their headings, then read the section you need:

| File | Size | What it answers | How to read it |
|---|---|---|---|
| `application/DECISION-LOG.md` | 150 KB | why a schema decision was made | `grep -n "^## "`, newest on top |
| `sql/DEPLOY-VERIFICATION.md` | 135 KB | per-patch verification, object counts, md5s | the top two lines give the current counts; `grep -n "^## v5"` |
| `application/invariant-parity-measurement-2026-10-13.md` | 100 KB | one invariant's grade | `grep -n "^| CI-NNN "` and the dated Update sections |
| `application/APPLICATION-CONTRACTS.md` | 70 KB | what the schema requires of app code (AC-n) | `grep -n "AC-NN"` |
| `application/draft-candidates.md`, `a2-rules-for-the-core.md` | 90–190 KB | historical inventories | only when a task cites them |
| `sql/tu.sql` | 42k lines | the schema | grep for the object; never read it whole |
| `CHANGELOG.md`, `changelog-archive/` | — | what a past session did and tried | grep; the live file holds the newest 10 sessions |

For a patch round, the merged plan (`application/wave*-build-*/v5.4.2-NN-rN-plan.md`) is the summary of the reviews. Open a review file (`tests/v5.4.2-NN/review/`) only for one finding's evidence.

Before writing or reviewing patch code, read the index at the top of `sql/PATCH-LESSONS.md` and open the sections your change touches. A new lesson goes there, not into session memory.

## Standing rules

- `tu.sql` is append-only. A change is a new `sql/v5.4.x-NN-*.sql` patch: tests first, then built, frozen, reviewed (Opus, Fable, Codex), and then mirrored onto the end of `tu.sql` on Ryan's approval.
- Never edit the frozen review copies, or the bodies already mirrored into `tu.sql`.
- Commit to `main`; there are no feature branches. `git pull --rebase` before every push: other streams push too.
- Touch only your stream's tables (the board lists them); claim a patch number on the board before creating the file; follow the board's shared-resource rules (one `ci.sh` run at a time, the pre-mirror check).
- A change to GBM's `main` is logged in GBM `application/wiki-ingestion-pending.md` in the same edit. Kyle's answers sometimes arrive as a chat paste rather than a push; record them in GBM yourself.
- The parity record lives here, not in GBM's register (frozen at -12).

## Wrap-up

- Overwrite your stream's file in `handoffs/` (this is what `/claude-handoff:wrap-up` writes here, in place of `HANDOFF.md`). State lives only there: not in memory, not in CONTEXT.md. Never rewrite the board whole; edit only the lines your stream changed.
- Add the CHANGELOG entry directly under the header. Read only the header and the newest entry; never the whole file. The session that mirrors also moves the oldest live entries into `changelog-archive/YYYY-MM.md`, so 10 stay live.
- Refresh the roadmap data as `application/roadmap/README.md` describes.
