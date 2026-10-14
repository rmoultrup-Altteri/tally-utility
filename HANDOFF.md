# Handoff: v5.4.2-20 mirrored (the version check and the void, sealed); Kyle answered; Ryan's four wave-1 calls decided

**Generated**: 2026-10-14 15:20
**Branch**: `main` at `6a520ae`, pushed. gas-billing-memory `main` at `11ce5c5`, pushed (`Clippings/` uncommitted on purpose: never commit it).
**Status**: Ready for the next piece. Nothing is in review and nothing is pending in CI (`PENDING=()`).

## Goal

Reach the C# core build. Ryan's gate, in order:
1. schema parity with CI-001…CI-135 (**we are here**);
2. scenarios and a test strategy;
3. a phase plan;
4. build.

## Completed (this session)

- [x] **Kyle answered the tax-jurisdiction and gas-cost brief.** His file is `gas-billing-memory/application/kyle-decisions-2026-10-14-tax-jurisdictions-and-gas-cost.md` (`45dfff6`).
  - Logged in `application/DECISION-LOG.md` and in GBM ingestion manifest Section BO.
  - The gas-cost carve-out is closed: billing side only, so CI-033 and CI-036 are to be re-read as such.
  - Kyle asked where D-2 lives: Part 2 of `gas-billing-memory/application/kyle-decisions-2026-08-18-coda-items.md`. **This has not been sent to him.**
- [x] **GBM housekeeping:** Section BN and `marketing/state-and-differentiators-2026-10-02.md` committed (`11ce5c5`).
- [x] **Ryan's four wave-1 calls, all logged in `application/DECISION-LOG.md` (2026-10-14):**
  - **CI-016:** which bill lines must carry their arithmetic at issue. Usage, base and per-unit surcharges do; every other kind is the amount only.
  - **CI-017:** a reversal that undoes one thing must name it. A refund names a payment or a customer credit; that FK does not exist yet.
  - **CI-014:** 17 more tables refuse DELETE; 6 stay deletable. The custom labels are refused while in use.
  - **CI-011 / A-23:** seal the version check and the void, built as -20 below.
  **CI-016, CI-017 and CI-014 are decided but NOT built.**
- [x] **A-23 design review**, with three reviewers (`application/a23-seal-review-2026-10-14/`: brief, three reviews, `source-inventory-20.md`).
- [x] **`sql/v5.4.2-20-seal-version-check-and-void.sql`**, r3, 1,488 lines, md5 `0ae593499b0dbf52a5bf306b8e7f3eee`:
  - **Review:** three rounds (r1 all "not yet"; r2 all ready; r3 diff-scoped, all ready).
  - **Mirrored:** `sql/tu.sql` 38,016 → **39,349** lines, md5 `e13f0d72ffdcf65782e789a58ed4cb32`.
  - **Build check:** fresh build, zero init errors; catalog identity of 11,215 lines equal to the patched clone; `tests/ci.sh --build` 26/26.
  - **Docs:** `sql/DEPLOY-VERIFICATION.md` has the -20 entry; AC-12 rewritten and AC-42 new in `application/APPLICATION-CONTRACTS.md`.
- [x] **Tests:**
  - `tests/v5.4.2-20/battery-20.sql`, 80 checks;
  - `tests/v5.4.2-20/races/seal-20.sh`, 19 cases (RC1–RC6, RC3b, T1–T7c);
  - `tests/v5.4.2-20/mutations-20.py`, 53/53;
  - batteries -10, -11 and -19 adjusted (see the warnings).

## Not Yet Done

- [ ] **Ask Ryan:** Codex's identity question (-20 residual R1). `app.user_id` is caller-asserted, so any code running as `tally_app` can claim another real user, a platform admin included. Every tenant wall rests on it. One decision, in plain language, with a default.
- [ ] **Build the three decided calls** as the next patch: CI-016 (a deferred check at issue, by `charge_type`), CI-017 (lineage required; a new refund→`customer_credits` FK) and CI-014 (17 tables into `enforce_no_hard_delete`; the custom-label in-use guard). The decision-log entries carry the exact lists and what is left to drafting.
- [ ] **Fold the three -20 notes** into that patch:
  - convert `REVOKE TEMP ON DATABASE :"DBNAME" FROM PUBLIC` to `EXECUTE format(... current_database())`; it is the only psql variable in tu.sql, and redundant;
  - the PUBLIC-clause message says "relation";
  - a header comment: the trigger-definition strings in `assert_seal_role_invariants()` are PostgreSQL 16's rendering, so re-capture them on a major upgrade.
- [ ] **Update GBM for -20:** CI-011's grade, A-23 item 1, AC-12/R14 in the parity docs and `canonical-invariants.md`, plus an ingestion-manifest section (memory `log-changes-for-wiki-ingestion`).
- [ ] **Reply to Kyle** with where D-2 lives (above).
- [ ] **Wave 2** of `application/step1-sequencing-2026-10-13.md` (finance-released structures and cash). Kyle's answers now also release A-8 tax jurisdictions and the franchise-fee rework.
- [ ] **The -05 defect** (Fable -19 r1 N6): a non-estimated read inserted past `pending` fails on `meters_last_validated_actual_reading_id_fkey`. It needs its own small patch.
- [ ] **Carried over:**
  - backbilling tariff table;
  - the GitHub Actions bump (`checkout@v4`, `setup-python@v5`, Node 20 warnings);
  - Florida 25-7.083 text;
  - the waiver-determination rewrite;
  - low-confidence measurement rows;
  - the -15 r8 follow-ups;
  - step 2 onward not started.

## Failed Approaches (Don't Repeat These)

- **A receipt for the void.** It stays valid until commit, which reopens the window v5.4.2-01 closed: a charge attached to the voided bill later in the same transaction could be released with it. Use `current_user = 'tally_void'` in the guards; the window is exactly the call.
- **Column-only `REVOKE UPDATE (version)`.** It is a no-op while the table-level grant stands. Revoke table UPDATE, then GRANT the sanctioned columns back, and keep `updated_at` (the `rate_item_dependencies` mutex writes it).
- **The attach guard "leaving an invisible bill to the FK".** The FK checks only the id, so tenant 1 billed onto tenant 2's void bill. Refuse NOT FOUND, and refuse a tenant mismatch (a platform admin sees both).
- **A void at REPEATABLE READ.** Its child UPDATEs use the old snapshot and miss an attach that committed while it waited for the lock. `void_invoice()` refuses anything but READ COMMITTED.
- **A trigger only on "pointer changed".** A pending charge could carry a pointer through the bill's void and then be marked billed, unchanged. CHECK `adhoc_charges_billed_names_its_bill`.
- **New guards left origin-only.** `session_replication_role = replica` skips them, contrary to D-2026-08-20-27. `ALTER TABLE … ENABLE ALWAYS TRIGGER` every guard.
- **Duplicate checks:**
  - the void's explicit tenant compare duplicated RLS;
  - the stamp of xact/at was done in both the function and the trigger;
  - the charge guard's "keeps run" duplicated the column grants.
  Each made a mutation miss; removed (memory `test-the-boundary` / redundant-guard rule).
- **Battery forgery via `session_replication_role = replica`.** It stopped working once the stamp trigger was ALWAYS. Use `ALTER TABLE … DISABLE TRIGGER` inside the rolled-back battery.
- **One planted receipt shared across S13 cases.** A mutation got caught at the wrong case. Plant each forgery just before its own case.
- **`now()` for an `updated_at` touch in one transaction.** The value does not change. Use `clock_timestamp()`.
- **Comparing jsonb-stored oids with `@> to_jsonb(oid::bigint)`.** jsonb holds the oid as a string. Use `(c_owns -> r) ? p.oid::text`.
- **A python edit script that asserts on file 1, then edits file 2.** The abort silently skipped file 2's edits. Check each file's edit landed.
- **Counting `ERROR:` in `docker logs` after a CI run.** The tests' deliberate refusals are logged too. Count only before "PostgreSQL init process complete".

## Key Decisions

| Decision | Rationale |
|---|---|
| Two owner roles, `tally_seal` and `tally_void`: NOLOGIN, not BYPASSRLS, no members, an exact privilege allowlist | A superuser definer switches on about 12 superuser carve-outs and bypasses RLS. Separate roles because the void guards key on `current_user` |
| Receipts for the version check (Opus, Fable), not Codex's write API | It keeps the app's calling shape and was tested against every bypass. The write API is the next step if the version tables get a second writer (R4) |
| The receipt binds xact, `at = now()`, table + entity, and the header's current version | `at` covers xid reuse after a restore. Each binding has a forgery test (S13a–e) |
| A header lifecycle move needs the check too | An archive is an edit of the entity (Fable S6) |
| tally_void has column-level UPDATE only | Least privilege. Out-of-grant writes fail with 42501 (batteries -19 R4/R5c and -20 V9c/V10 expect it) |
| The r3 round was diff-scoped (Ryan agreed) | r3 changed only the invariant and the tests |
| Mirror the reviewed bytes even with the psql-variable wart | An unreviewed edit at mirror time is worse; the wart is noted for the next patch |
| The invariant's PUBLIC clause refuses any table or column privilege to PUBLIC | Every role inherits PUBLIC, so the allowlist would otherwise be incomplete (Codex r2 S1) |

## Current State

**Working:**
- `tally-pg` runs the **-20 build**: `tally` = `tu.sql` md5 `e13f0d72`.
- `tests/ci.sh` passes, 26 steps.
- TEMP is revoked for `tally_app`, `tally_seal` and `tally_void`.

**Broken:** nothing.
**Uncommitted changes:** only this HANDOFF and the CHANGELOG entry (to be committed now). GBM: `Clippings/`, untracked, never commit.

## Code Context

```sql
public.assert_reference_version(p_table text, p_id uuid, p_expected_version int) RETURNS int
  -- definer, owner tally_seal; P0002 not visible, 40001 stale; writes reference_version_receipts
public.reference_version_receipt_held(p_table text, p_id uuid) RETURNS boolean
  -- definer, owner tally_seal; this xact + at=now() + entity + current version
public.void_invoice(uuid, uuid, text, text, boolean) RETURNS jsonb
  -- definer, owner tally_void; READ COMMITTED only; FOR UPDATE on the bill; RLS is the tenant check
public.enforce_attach_to_live_invoice()      -- trigger, TG_ARGV[0] = the pointer column; FOR SHARE on the bill
public.seal_role_privileges(p_role text) RETURNS text[]
public.assert_seal_role_invariants()         -- in the patch tail and in CI
```

The guards admit the void's writes with `current_user = 'tally_void'`. A test that writes "as the void" does `RESET ROLE; SET ROLE tally_void;` from the superuser session. `GRANT EXECUTE` on the battery's `pg_temp` helpers to `tally_void` too.

## Resume Instructions

1. Fetch both repos:
   ```
   cd ~/code/tally-utility && git pull --ff-only
   cd ~/code/gas-billing-memory && git fetch && git log --oneline HEAD..origin/main
   ```
   - Expected: tally-utility at `6a520ae` plus this wrap-up commit. Kyle may have pushed to GBM (memory `fetch-gbm-before-orienting`).
2. `tests/ci.sh`.
   - Expected: `ci: all pass`, 26 steps.
   - If tally-pg is gone: `tests/ci.sh --build`, about 5 minutes.
3. Ask Ryan the identity question (R1): one decision, plain language, a default (memory `one-decision-at-a-time-plain-language`).
4. Then the next patch (v5.4.2-21):
   - CI-016, CI-017 and CI-014 from the decision log, plus the three -20 notes;
   - source inventory first;
   - strict-apply, battery, races, mutations;
   - freeze, and all three reviewers before the mirror.

## Warnings

- **Never edit the frozen review copies or `tu.sql`'s mirrored body.** `tu.sql` is append-only and mirrors only on Ryan's approval.
- **Revoke TEMP from PUBLIC, `tally_app` and `tally_core` after every `CREATE DATABASE … TEMPLATE`.** `assert_seal_role_invariants()` also fails if the seal roles can get TEMP through PUBLIC.
- **`tally_seal` and `tally_void` are cluster-wide.** Reviewers must not create, alter or drop roles. A leftover reviewer role (`tally_definer`) was dropped this session; check `pg_roles` after reviews.
- **The S13 forgery** disables `a_stamp_reference_version_receipt` inside the rolled-back battery transaction. It must be re-enabled with `ENABLE ALWAYS`, not `ENABLE`, or the invariant fails.
- **`mutations-20.py` clones into `m20`.** Its catches are valid only when the first failure line of any kind is the named check's.
- **The generator** for -20 lived in the session scratchpad and is gone. The patch file is now the source of truth; edit it directly in the next patch.
- **Never `git add -A` in gas-billing-memory** (`Clippings/`).
- **Ask Ryan one decision per message, in plain language.**
