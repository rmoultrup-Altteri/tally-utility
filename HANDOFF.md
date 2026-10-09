# Handoff: v5.4.2-17 (rule-terms step 2) is MIRRORED into tu.sql; next is the -13 migration

**Generated**: 2026-10-09, end of session
**Branch**: `main`, pushed (last commit is the mirror, `a0b27cf`, plus this handoff). gas-billing-memory unchanged (`091c990`) as of the last fetch this session; fetch both before orienting.
**Status**: v5.4.2-17 is landed. Patch `sql/v5.4.2-17-rule-terms-convention.sql` is the r9 freeze (md5 `ed1b8298d22de9f5015a9007422eab19`, 3,459 lines; battery `ac59a9437bd342138a952eb2a6477f56`, 276 PASS; 198/198 mutations). `sql/tu.sql` is 30,570 lines, md5 `5ac8ed99179e7e0f80ba35f21cd0043b`. `tally-pg` runs the new build. Verification: `sql/DEPLOY-VERIFICATION.md` (the -17 entry). `tests/ci.sh` passes in full; `PENDING` is empty.

## What -17 gave the next two patches
The convention, written once: `tally_core`; the term-schema registry and validator; facets; `rule_table_register()` and the law/tariff template (lookups, citations, the tariff check, seeds, one-time adoption of pre-convention rows); published values; audit findings; the core-inputs fingerprint. Read the patch header and residuals R1-R26 (end of the patch) before writing a consumer. `law/README.md` is the law-file format.

## Resume Instructions
1. Fetch both repos:
   ```
   cd ~/code/tally-utility && git pull --ff-only
   cd ~/code/gas-billing-memory && git fetch && git log --oneline HEAD..origin/main
   ```
   (Kyle pushes rulings to gas-billing-memory main directly.)
2. Next work, in this order (Ryan decides when):
   - **The -13 migration** (adopt `backbilling_rules`, follow residual **R14**): (1) add the template columns and compute the spans from the old columns; registration now runs the fill's own checks on every legacy row (non-blank key, a known state, system kinds of the row's service, spans equal to the sets), so repair those first; (2) register as adopting with `p_adoption_check`; (3) drop `enforce_backbilling_rule_history`; (4) fill the documents, window terms included. Typed NOT NULL columns that a facet names must become nullable (R23). Its triggers are `a_...` and sort before the template's. Until it lands, `assert_rule_table_invariants()` is vacuous (R24).
   - **The -15 rewrite** on the template: drop or justify its class-scoped rate (R10); city classes (R16). Its triggers are `a_...` too.
   - Bump the GitHub Actions versions (`checkout@v4`, `setup-python@v5` warn about Node 20).
3. Each patch: test first; the fail-first runner (`tests/v5.4.2-17/fail-first.py <db> [block]`) runs `-- rN:begin` blocks of a battery alone; mutation per clause; three reviewers (Opus, Fable as background agents with their own database prefixes; Codex via `codex exec -s workspace-write`, I run its probes); freeze the hash before the reviews; mirror only on Ryan's approval (procedure: the -17 entry in `sql/DEPLOY-VERIFICATION.md`).

## Warnings
- **`tu.sql` is append-only.** Mirror only after Ryan approves.
- **`mutations-17.py` clones `tally`, which now contains -17.** A rerun needs a pre-17 base (a database built from the -16 `tu.sql`, as the parity step did).
- **Revoke TEMP after every `CREATE DATABASE ... TEMPLATE`** (the helper scripts do; `assert_core_role_invariants()` checks it).
- **Freeze the hash before any review; one revision per round.**
- **Waiting on a background run:** never `pgrep -f` the script's own name inside a Monitor (it matches itself); poll its log file.
- **A reviewer's claim is measured before it drives a change** (the COLLATE claim was wrong).
- **Never `git add -A` in gas-billing-memory.** Explain choices to Ryan in prose; ask only on rule conflicts.

## Key decisions (unchanged from the convention)
Applicability as sets with NULL = every one; area key NOT NULL compared with `=`; a record cites the law row always and a tariff row optionally; a tariff is checked against the law rows sharing its key columns (a later law change is an audit finding, R6/R17); published values have no class scope (R10); `tally_core` has explicit grants only; one IMMUTABLE interpreter of a JSON Schema subset; registration shares the fill's checks by calling them.
