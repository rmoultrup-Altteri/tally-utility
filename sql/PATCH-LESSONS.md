# Patch lessons — what the schema work has learned the hard way

Lessons from writing, testing and reviewing the `sql/v5.4.x-NN-*.sql` patches, each found by a review or a failed run. They were kept in Claude's session memory until 2026-10-28 and moved here so they are shared and loaded only when needed. "I" is the Claude session that wrote the entry.

**How to use this file:** before writing or reviewing patch code, read the index below and open only the sections that touch your change. Add a lesson here (with its *why* and *how to apply*) when a review or a run teaches one; don't put it in session memory.

## Index

**Environment and test setup**
- [tally-pg-readiness-wait](#tally-pg-readiness-wait) — After `docker run` of tally-pg, wait for the log line "PostgreSQL init process complete" before connecting — a `SELECT 1` probe succeeds against the temporary init server and runs scripts against a half-built schema
- [strict-apply-before-mirror](#strict-apply-before-mirror) — Docker fresh build does NOT prove search_path='' safety (preamble disables function-body checks); strict-apply the patch file before mirroring
- [template-clone-drops-acl](#template-clone-drops-acl) — CREATE DATABASE … TEMPLATE tally does not copy the database ACL — tally_app regains TEMP on every clone, so depth fences are open in battery runs unless TEMP is revoked after cloning
- [test-fixture-required-columns](#test-fixture-required-columns) — Minimum NOT NULL columns for hand-built tally-pg test fixtures (tenants, customers, service_locations, meters, users) — saves two failed rounds per session

**Roles, RLS and depth fences**
- [strict-pin-vs-rls-helpers](#strict-pin-vs-rls-helpers) — Trigger functions that read RLS-protected tables must pin search_path = public, pg_temp (not '') until the v5.2.1 RLS helpers are qualified — '' locks tally_app out and the superuser battery cannot see it
- [depth-fence-needs-no-temp](#depth-fence-needs-no-temp) — pg_trigger_depth() < 2 guards in tu.sql are a fence only while tally_app can define no code — TEMP is revoked on the database; never grant TEMP/CREATE/TRIGGER to the app role; GUC sentinels are forgeable
- [trigger-depth-fence-inside-guard](#trigger-depth-fence-inside-guard) — Inside a BEFORE trigger a direct statement is already pg_trigger_depth() = 1; a "written by the database" fence must test < 2, never = 0
- [seal-pattern-owner-roles](#seal-pattern-owner-roles) — How a "must go through this function" rule is sealed in tally — a dedicated NOLOGIN non-BYPASSRLS owner role, guards keyed on current_user, exact invariants
- [correct-by-status-not-delete](#correct-by-status-not-delete) — A mistyped row on a retained table is corrected by a stamped status (e.g. withdrawn), never an app DELETE; -21's retention invariant refuses any tally_app DELETE outside its fixed list

**Guard predicates**
- [guard-the-act-not-the-label](#guard-the-act-not-the-label) — key a guard on what happened, not on the type/status name the caller chose
- [app-written-logs-are-not-guards](#app-written-logs-are-not-guards) — A fact a guard depends on must be written by the database (trigger stamp, write-once); an app-writable log or event table can be forged by tally_app and only serves a one-time backfill, stated as an approximation
- [guards-must-act-not-record](#guards-must-act-not-record) — a guard that writes its own enforcement to a log without performing it is worse than no guard
- [two-fields-both-the-money](#two-fields-both-the-money) — invoices.amount_due and the line-item sum are both "the money" and nothing ties them; measure over both
- [blank-checks-whitelist-alnum](#blank-checks-whitelist-alnum) — Never use btrim() as a blank/evidence check — it strips ASCII space only (a tab or NBSP passes); require >= 1 :alnum: char instead, and coalesce the NULL leg
- [jsonpath-check-must-reparse](#jsonpath-check-must-reparse) — A CHECK must reparse from the text the catalogue prints (pg_dump writes that text): PG 16 prints `(@ * 10000).floor()` as `@ * 10000.floor()`, which does not parse, and the whole table is lost on restore; test with a reparse round-trip and a real dump/restore
- [check-passes-null](#check-passes-null) — A CHECK accepts a NULL result, so `reason ~ '[[:alnum:]]'` admits a NULL reason; name the NULL leg (`reason IS NOT NULL AND ...`); NaN likewise equals its own `round()` in numeric
- [early-return-branches-skip-fences](#early-return-branches-skip-fences) — A trigger's status-transition branches that RETURN NEW early skip every fence below them; fence derived columns first and compare the whole row
- [rules-bind-every-displacing-path](#rules-bind-every-displacing-path) — A rule about what may replace a fact must bind every path that can displace it — the linked correction AND a parallel row the readers rank above it
- [projection-checks-lag-in-one-statement](#projection-checks-lag-in-one-statement) — A BEFORE ROW check reading a column an AFTER trigger writes (deposits.status) is stale inside a multi-row/WITH statement; read the events, and judge cross-table facts in an AFTER trigger
- [append-only-vs-unique-deadlock](#append-only-vs-unique-deadlock) — append-only + a uniqueness key + a gate demanding a fresh row = a flow that can never complete

**Time and coordinates**
- [temporal-helper-no-live-fallback](#temporal-helper-no-live-fallback) — Standing rule for any as-of/temporal lookup function in tu.sql — no live-value fallback, NULL coordinate raises, NULL result means unknowable
- [date-from-snapshot-knowledge-from-now](#date-from-snapshot-knowledge-from-now) — issue-time checks classify at the snapshot's bound valid_at but under now(); the snapshot's recorded_at is caller-chosen and hides retractions
- [history-stamped-at-xact-start](#history-stamped-at-xact-start) — a history read latest-first by a now() stamp goes permanently wrong when the earlier-begun writer commits last; refuse that writer (40001), don't switch to clock_timestamp()

**Concurrency**
- [succession-checks-at-commit](#succession-checks-at-commit) — a "never closed from under X" check on code-keyed rows must run at commit (deferred constraint trigger, ALWAYS, all-tenants role), or it refuses every close-then-successor
- [count-guards-need-lock-handshake](#count-guards-need-lock-handshake) — A guard that counts rows can be defeated by an in-flight writer (phantom); pair it with a lock handshake — prefer a row-version mutex (UPDATE) over a bare lock, FOR KEY SHARE on heartbeated rows, and pin READ COMMITTED only where no row version can be written
- [lock-order-as-a-rule](#lock-order-as-a-rule) — State a lock order as a rule over the rows taken in order, plus "every writer retries 40P01"; never as a list of shapes
- [constraint-trigger-name-order](#constraint-trigger-name-order) — a deferred constraint trigger that reads what another AFTER trigger writes must sort after it by name: once a battery has run SET CONSTRAINTS ALL IMMEDIATE it fires at statement end, in name order, before the writer
- [race-barriers-clear-stat-snapshot](#race-barriers-clear-stat-snapshot) — two-session race barriers polling pg_stat_activity must call pg_stat_clear_snapshot() each poll; never edit test files while mutations-22.py runs

**Performance**
- [recursive-walks-join-on-link-alone](#recursive-walks-join-on-link-alone) — WITH RECURSIVE ledger walks — pin the plan (enable_seqscan/hashjoin/mergejoin off on the function); join only on the link; mutation runners VACUUM first and need statement_timeout

**Testing**
- [checks-narrower-than-their-claim](#checks-narrower-than-their-claim) — a self-check filtered by a narrower key than the property it certifies buys false confidence — enumerate by the property, and prove the check CATCHES drift, not just that it passes
- [test-the-boundary-not-the-formula](#test-the-boundary-not-the-formula) — When an off-by-one is flagged, fix the comparison, not the displayed value; a battery check asserting a column equals its own formula proves nothing — pin boundaries to concrete dates on both sides
- [every-branch-and-stated-default-tested](#every-branch-and-stated-default-tested) — a guard's exempt branch and any behaviour a header states need a fixture that takes them; -23 r2's refund exemption and K2 default had none
- [rule-table-fixture-notes](#rule-table-fixture-notes) — Notes from building -25: facets and owner types stored sorted; flush deferred checks as the owner; drop guard pieces another check always beats
- [rule-table-keys-are-text-codes](#rule-table-keys-are-text-codes) — a rule-template area key must be a text code (no uuid); key a place by kind and code, which also survives the place's succession; terms numbers canonical (1, not 1.0)
- [check-names-its-own-guard](#check-names-its-own-guard) — when two guards share a tag (a BEFORE guard and its commit-time backup), a battery check matching the tag alone still passes with either guard gone; match wording only one writes. A mutation that empties an already-empty list changes nothing

**Review process**
- [freeze-hash-before-reviews](#freeze-hash-before-reviews) — Do not edit the patch file while the two reviewers are testing it — freeze the hash at launch, batch all fixes into the next round
- [reviewer-fixes-need-measuring](#reviewer-fixes-need-measuring) — reviewers' findings are usually right and their proposed FIXES often are not — measure the fix before folding it; two independent reviewers converging is the strongest signal available

---

## Environment and test setup

<a id="tally-pg-readiness-wait"></a>
### tally-pg-readiness-wait

`docker run … tally-postgres` starts a temporary server, runs `/docker-entrypoint-initdb.d` (preamble + tu.sql), shuts it down, then starts the real server. A readiness loop that polls `psql -c "select 1"` connects to the *temporary* server mid-init (2026-08-28: the seed ran while tu.sql was only partly applied — `wna_zones.wna_adjustment_floor` "did not exist" — and the strict apply then died with "database system is shutting down").

**Why:** Both phases accept connections; only the second has the full schema.
**How to apply:** `for i in $(seq 1 120); do docker logs tally-pg 2>&1 | grep -q "PostgreSQL init process complete" && break; sleep 1; done; sleep 2` and then poll `select 1`. Also verify `count(*) from pg_tables where schemaname='public'` matches the expected count before seeding. Related: [strict-apply-before-mirror](#strict-apply-before-mirror), [test-fixture-required-columns](#test-fixture-required-columns).

<a id="strict-apply-before-mirror"></a>
### strict-apply-before-mirror

Every tally-utility patch file must apply cleanly with `SET search_path = ''; SET check_function_bodies = on;` prepended, before review and before mirroring into tu.sql. Pipe: `{ echo "SET search_path = ''; SET check_function_bodies = on;"; cat sql/<patch>; } | docker exec -i tally-pg psql -U tally -d tally -v ON_ERROR_STOP=1 -f -`.

**Why:** `postgres/00_preamble.sql` sets `check_function_bodies = off`, so the Dockerfile fresh build — and every reviewer fresh-load through the image — silently accepts unqualified plpgsql bodies. v5.4.2-01 re-issued `void_invoice()` with eleven unqualified refs, claimed "search_path clean", and was only caught by a post-landing assessment (fixed in v5.4.2-02, 2026-08-20). Also: `SET search_path = ''` on a SECURITY DEFINER function compiles but fails at runtime if its helpers are unqualified — pin `public, pg_temp` instead.

**How to apply:** run the strict apply in the live-test step and tell reviewers to use the same prelude; record it per patch in `sql/DEPLOY-VERIFICATION.md`. Related: [temporal-helper-no-live-fallback](#temporal-helper-no-live-fallback), [test-fixture-required-columns](#test-fixture-required-columns).

<a id="template-clone-drops-acl"></a>
### template-clone-drops-acl

`CREATE DATABASE x TEMPLATE tally` leaves `datacl` empty, so PUBLIC (and tally_app) has TEMP on the clone. `tally` itself has `{=c/tally,tally=CTc/tally}` (-06 revoked TEMP). Found by the Opus reviewer in the v5.4.2-15 round 1 (2026-10-02); confirmed with `has_database_privilege('tally_app', current_database(), 'TEMP') = t` on a clone.

**Why:** the pg_trigger_depth() fences hold only while tally_app can define no code ([depth-fence-needs-no-temp](#depth-fence-needs-no-temp)). Every battery run on a clone before 2026-10-02 ran with that fence open, so a TEMP-based bypass would not have been caught.

**How to apply:** right after any clone, run `REVOKE TEMP ON DATABASE x FROM PUBLIC, tally_app` (run scripts and mutation scripts included). Related: [tally-pg-readiness-wait](#tally-pg-readiness-wait).

<a id="test-fixture-required-columns"></a>
### test-fixture-required-columns

Minimum fixture columns when hand-testing DDL against the `tally-pg` container (verified 2026-08-20):
- `tenants`: name, slug
- `customers`: tenant_id, customer_number
- `service_locations`: tenant_id, customer_id, location_number, address_line1, city, state, zip (NOT `postal_code`)
- `meters`: tenant_id, meter_number, location_id, service_type (inserting with default status `active` auto-creates `meter_deployments` #1 from `start_date`)
- `users`: id, tenant_id, display_name, email, role

**Why:** The handoff notes listed only the first four service_locations columns; address_line1/city/state cost two failed test runs.
**How to apply:** Wrap negative cases in `SAVEPOINT sp; ... ROLLBACK TO sp;` inside the BEGIN…ROLLBACK battery so one expected rejection doesn't abort the rest. Query `information_schema.columns where is_nullable='NO' and column_default is null` before guessing. See schema-provenance.

---

## Roles, RLS and depth fences

<a id="strict-pin-vs-rls-helpers"></a>
### strict-pin-vs-rls-helpers

In tally-utility, `get_user_tenant_id()` / `is_platform_admin()` (v5.2.1, SECURITY DEFINER, unpinned) name `users` unqualified. A trigger function pinned `SET search_path = ''` that touches any RLS table makes the policy call those helpers under the empty path → `relation "users" does not exist` for every non-superuser (2026-08-28, A-3 round 1: both reviewers CRITICAL).

**Why:** the strict-apply prelude proves *qualification* at compile time but the superuser bypasses RLS, so the author's battery never exercised the failing path.
**How to apply:** pin `SET search_path = public, pg_temp` (the `void_invoice`/A-1 precedent) with every reference still qualified; every battery includes an end-to-end write as `tally_app` inside one transaction (`BEGIN; SET LOCAL ROLE tally_app; …`). Durable fix is A-23 (qualify + pin the three helpers). See [strict-apply-before-mirror](#strict-apply-before-mirror), [test-fixture-required-columns](#test-fixture-required-columns).

<a id="depth-fence-needs-no-temp"></a>
### depth-fence-needs-no-temp

tally-utility uses `pg_trigger_depth() < 2` to let only the database's own projection triggers write certain columns (A-20 estimate counter, A-21 deposit status / customers.deposit_*). Review (2026-08-28) reached depth 2 as `tally_app` with a temp table + `pg_temp` trigger function. v5.4.2-06 revokes TEMP on the database from PUBLIC and `tally_app`.

**Why:** the fence is structural only if the app role cannot create a function or own a table with a trigger; a transaction-local GUC "sentinel" is not an alternative — any role can `set_config` it.
**How to apply:** before granting TEMP, CREATE on a schema, or TRIGGER on a table to `tally_app`, re-read canonical-invariants Appendix A-23 (1d). New views over RLS tables need `WITH (security_invoker = true)`. See [strict-pin-vs-rls-helpers](#strict-pin-vs-rls-helpers).

**Amended 2026-09-09 (v5.4.2-11):** the TEMP revoke uses `current_database()`, and `CREATE DATABASE ... TEMPLATE` does NOT copy `datacl` — so every battery in this project runs on a clone WITH TEMP held by `tally_app`. The depth fences have never been tested in their deployed shape. Batteries now print the TEMP state they are actually running under; re-run the two `REVOKE TEMP ON DATABASE` lines by hand on a clone before testing anything that leans on the fence. A materialized view can carry neither `security_invoker` nor RLS at all — the grant is the only lever there. See [checks-narrower-than-their-claim](#checks-narrower-than-their-claim).

<a id="trigger-depth-fence-inside-guard"></a>
### trigger-depth-fence-inside-guard

In tally-utility guards, `pg_trigger_depth()` evaluated *inside* a trigger function is 1 for a direct INSERT/UPDATE and ≥ 2 for a write made by another trigger (the A-21 logger, the deposit projections). A fence meaning "only the database writes this table" is `IF pg_trigger_depth() < 2 THEN RAISE` (with superuser exempt for migration backfills).

**Why:** v5.4.2-07's first draft tested `= 0` and fenced nothing — the battery passed the direct insert as `tally_app`. A-21 already used `< 2` throughout.
**How to apply:** copy A-21's `< 2` convention; test the fence as `tally_app` at depth 1 and the logger path at depth 2 in the same battery. Related: [depth-fence-needs-no-temp](#depth-fence-needs-no-temp).

<a id="seal-pattern-owner-roles"></a>
### seal-pattern-owner-roles

Since v5.4.2-20 (2026-10-14), an act that must go through one function is sealed this way.

1. **The owner.** The function is SECURITY DEFINER, pinned to `public, pg_temp`, and owned by a dedicated role (`tally_seal`, `tally_void`).
   - The role is NOLOGIN, with no BYPASSRLS, no members and membership in nothing.
   - Its grants are an exact, column-level allowlist.
   - It is never owned by the superuser `tally`: that would bypass RLS and switch on about 12 rolsuper carve-outs.
2. **The guards.** The guards admit the sealed writes when `current_user = '<role>'`. That is true only while the function runs. Never use a GUC: it is caller-settable.
3. **The proof.** If a later write must prove the function ran (the version check), the function writes a receipt row. The receipt binds the xact, the transaction start time (`at = now()`), the entity and its current version, and is stamped by an ALWAYS trigger.
4. **The invariants.** `assert_seal_role_invariants()` checks:
   - the role attributes;
   - the exact privileges, grant options included;
   - that PUBLIC holds no table or column privilege;
   - the exact trigger definitions plus `ENABLE ALWAYS`.

**Why:** three review rounds found every weaker form open:
- a receipt for the void stays valid until commit;
- a column-only REVOKE is a no-op;
- origin-only triggers are skipped in replica mode;
- a definer under RLS still needs EXECUTE on the RLS helpers.

**How to apply:**
- A new definer gets the same shape, and its role is added to the invariant.
- Re-capture the trigger strings after a PostgreSQL major upgrade.
- Tests "as the void" use `SET ROLE tally_void` from the superuser session.
- A void caller must set `app.user_id`.

Related: [guards-must-act-not-record](#guards-must-act-not-record), [depth-fence-needs-no-temp](#depth-fence-needs-no-temp), [template-clone-drops-acl](#template-clone-drops-acl).

<a id="correct-by-status-not-delete"></a>
### correct-by-status-not-delete

When a reviewer asks for a way to correct a mistyped row (v5.4.2-22 r2: an accounting period entered wrong), do not grant `tally_app` DELETE. `assert_no_hard_delete_invariants()` (-21, CI-014) fails CI on any table where `tally_app` may delete or truncate outside the deletable set: "tally_app may delete or truncate accounting_periods, which is not in the deletable set". Use a status instead (`withdrawn`, with `withdrawn_at`/`withdrawn_by` stamped by the database), keep the row, and exclude it from the uniqueness or EXCLUDE rule with `WHERE (status <> 'withdrawn')`.

**Why:** retention is a standing rule (Ryan, CI-014); the invariant caught the DELETE draft within one CI run.

**How to apply:** grant UPDATE on the status and stamp columns only, and have the guard admit just open → withdrawn under the same lock and isolation pin as the insert. Related: [app-written-logs-are-not-guards](#app-written-logs-are-not-guards), [guards-must-act-not-record](#guards-must-act-not-record).

---

## Guard predicates

<a id="guard-the-act-not-the-label"></a>
### guard-the-act-not-the-label

A guard keyed on a caller-chosen discriminator is bypassed by choosing a different value for it.

v5.4.2-12's issuance gate tested `invoice_type = 'correction'`. Three things walked past it: a `duplicate` and a `credit_memo` (both legal carriers of `replaces_invoice_id`, and both explicitly exempted from v5.4.2-10's coordinate binding), and — needing no `replaces_invoice_id` at all — voiding a bill and issuing a fresh `regular` invoice for the same premise and period. The patch had quoted the governing principle ("the regulated act is the charge, not the void") one function earlier to justify a different design choice, then violated it.

**Why:** the type label is an assertion by the writer. The facts — was this premise and period billed before, does this bill charge more — are not.

**How to apply:** state the regulated act in one sentence with no type names in it, then write the predicate from that sentence. Here: "this bill charges more for a period already billed." Related: counting-rebills-by-caller-chosen-type if written, and [app-written-logs-are-not-guards](#app-written-logs-are-not-guards).

<a id="app-written-logs-are-not-guards"></a>
### app-written-logs-are-not-guards

In tally-utility, `tally_app` can INSERT into `invoice_events`, `account_ledger`, `deposit_events` and similar append-only logs. A guard that reads them to decide "was this bill ever issued / voided from an issued state / paid" is forgeable in one INSERT. When a guard needs such a fact, give the database its own word: a column stamped by a trigger on the transition (`invoices.first_issued_at`, v5.4.2-10; `billing_runs.started_at`, `invoices.created_at` write-once), never caller-supplied, superusers exempt for migrations. The app-written log may feed the one-time deploy backfill of that column — say so in the header as an approximation.

**Why:** Fable's round-2 decoy (held → void, never billed) was a real void row; only a DB-stamped "issued" fact could exclude it. The same reasoning killed `remitted_on` (A-7) and stored renewal fields (A-9): later facts belong in DB-written history or in the communication log, not on frozen rows.

**How to apply:** before reading any `*_events` / ledger table inside a trigger, check who can INSERT there (`GRANT … ON ALL TABLES` gives tally_app INSERT by default; only UPDATE was revoked). Related: [count-guards-need-lock-handshake](#count-guards-need-lock-handshake), [depth-fence-needs-no-temp](#depth-fence-needs-no-temp).

<a id="guards-must-act-not-record"></a>
### guards-must-act-not-record

A control that RECORDS what it would have done, but does not do it, is worse than having no control — because the log is what a regulator, an auditor or the next engineer reads, and it asserts a protection that never ran.

v5.4.2-12's backbilling trim computed the forfeited amount, wrote `trimmed = true` and the amount to a permanent append-only evidence row, raised a NOTICE announcing the forfeit — and then issued the bill at the full amount, because the gate refused only when the trim consumed *everything*. 55 tests passed over it.

**Why:** the failure is invisible from inside the system. Every artefact says the rule held. It took a reviewer running the whole flow end to end and reading the resulting bill.

**How to apply:** whenever a guard computes a number that is supposed to change an outcome, write the test that checks THE OUTCOME, not the number. "Was it recorded as trimmed" and "was it actually trimmed" are different assertions, and only the second one is the control. See [checks-narrower-than-their-claim](#checks-narrower-than-their-claim) — same family: the check certified less than it claimed.

<a id="two-fields-both-the-money"></a>
### two-fields-both-the-money

In tally-utility, an invoice's total exists twice and nothing reconciles them:

- `sum(invoice_line_items.amount)` — the itemised bill content, what 16 TAC §7.45(6)(B)(v) requires a backbill to break down per billing unit, and what the calculation snapshot binds.
- `invoices.amount_due` — a caller-set `numeric(12,2) DEFAULT 0`. Nothing in tu.sql derives it from the lines. It is what posts to the ledger: `void_invoice()` reverses exactly `-(amount_due)` (tu.sql:1276).

**Why:** a gate reading either one alone can be walked past through the other. Reading `amount_due` lets a $5,000 line item ride under a $100 total; reading only the lines lets an inflated `amount_due` reach the ledger under honest lines. Both were reproduced against v5.4.2-12.

**How to apply:** measure the charge as `greatest(line sum, amount_due)` — the most the customer can be exposed to by either path. Do NOT require them equal: the existing batteries build invoices with `amount_due = 0` against non-zero lines (there is no billing engine to maintain it), and an equality rule refuses them — measured, it broke battery-10 and battery-11. The schema-wide invariant belongs to the invoice, not to any one patch. Recorded as v5.4.2-12 residual R9. See [app-written-logs-are-not-guards](#app-written-logs-are-not-guards).

<a id="blank-checks-whitelist-alnum"></a>
### blank-checks-whitelist-alnum

A "field must be non-blank" guard built on `btrim(x) = ''` is bypassable with a single tab, newline, or NBSP — btrim with no character argument strips ASCII space (0x20) only. Found as a CRITICAL in the v5.4.2-09 review: a certificate_number of `E'\t'` passed the evidence gate.

**Why:** blacklisting invisible characters is an open-ended family (NBSP variants, zero-width, combining marks). Whitelisting content closes it in one move: `coalesce(x ~ ':alnum:', false)` — requires one alphanumeric character, also refuses punctuation-only placeholders, and handles unicode sanely under en_US.utf8 (non-Latin letters pass; circled digits and lone combining marks refuse).
**How to apply:** use the coalesce form inside trigger IFs — `NULL ~ pattern` is NULL, and an IF landing NULL silently does not fire (a bypass, not an error). Keep the expression byte-identical between a gate and its deploy precondition (comment each pointing at the other). See [freeze-hash-before-reviews](#freeze-hash-before-reviews).

<a id="jsonpath-check-must-reparse"></a>
### jsonpath-check-must-reparse

v5.4.2-28 r1 (Opus B1): the tier-rate CHECK used `(@ * 10000).floor()`. PostgreSQL 16 stores it fine, but prints it back as `@ * 10000.floor()`, and that text fails to parse ("trailing junk after numeric literal"). `pg_dump` writes the CHECK inside `CREATE TABLE`, so a restore loses the table and everything built on it (33 errors, 136 of 137 tables). The `pg_dump --schema-only` comparisons still "matched", because only reading the dump back fails.

**Why:** a CHECK's stored form is the deparsed text, not what you wrote. jsonpath's printer drops the parentheses around a method's receiver. Other deparsers may have similar gaps.
**How to apply:** don't call a jsonpath method on a parenthesised expression (`@ * 10000 % 1 != 0` reparses). In the battery, feed every CHECK's `pg_get_constraintdef` back through `ALTER TABLE <scratch copy> ADD CONSTRAINT` (battery-28 R6). For any patch that adds a CHECK or an expression index, `pg_dump -Fc` a clone and `pg_restore` it into a fresh database, then compare object counts.

<a id="check-passes-null"></a>
### check-passes-null

v5.4.2-28 r1 (Codex B1): `closed_reason ~ '[[:alnum:]]'` inside a CHECK let a close with no reason through. The pattern test on NULL is NULL, and a CHECK refuses only on false. -21's trigger had required a reason; the move to a CHECK lost it. Fable S2 in the same round found the numeric version: `'NaN' = round('NaN', 4)` is true, so NaN passed the four-decimal check.

**Why:** the [blank-checks-whitelist-alnum](#blank-checks-whitelist-alnum) coalesce rule is written for trigger IFs. A CHECK has the same hole in the other direction: NULL means pass, not "don't fire".
**How to apply:** in a CHECK, name the NULL leg wherever a value is required (`x IS NOT NULL AND x ~ '[[:alnum:]]'`) and `x <> 'NaN'` wherever a numeric is compared to its own rounding. Test with the column left out, an explicit NULL, a blank, a tab and punctuation, once for each branch that requires the value.

<a id="early-return-branches-skip-fences"></a>
### early-return-branches-skip-fences

In a BEFORE UPDATE guard with branches like "open → frozen: stamp and RETURN NEW", every fence written further down (derived columns, evidence immutability) is skipped by any statement that also changes the status. v5.4.2-13 round 1: `SET status='open', direction='customer_owes'` turned a fast meter's refund into a charge, and `SET status='frozen', tamper_field_report_ref='anything'` swapped approved evidence. Both reviewers found it independently; I had fenced direction only in the "still open" fall-through.

**Why:** a branch that returns early is a second path through the guard; fixing the fall-through leaves the parallel path open (the same shape as [rules-bind-every-displacing-path](#rules-bind-every-displacing-path)).

**How to apply:** put immutability fences for derived/stamped columns FIRST, before any branch can return. For a status change, refuse unless `to_jsonb(NEW) - <allowed keys>` equals the same on OLD, so a column added later is fenced by default. Write one battery check per branch plus one with no status change, or the mutation of a redundant fence stays green.

<a id="rules-bind-every-displacing-path"></a>
### rules-bind-every-displacing-path

When a guard constrains what a correction (a supersedes/replaces link) may do, the same outcome is usually reachable by a row that does NOT link — a parallel row the readers then rank on top by insertion order or type. In v5.4.2-12 review rounds 2, 3 and 4 each found this sibling after the previous fix (supersession rules → parallel date-only row → same-basis parallel row → ranking before readings).

**Why:** the fact that matters is what the READERS return (pointer, governing function), not whether the linking row was vetted. Guarding the link alone guards a label.

**How to apply:** for any "what may replace X" rule, enumerate every writer that can change what the readers return for X, and put the rule where the readers decide (their ORDER BY / selection), with the insert guard as a loud extra only where it refuses nothing legitimate. Mutation-test each ranking key separately. Related: [guard-the-act-not-the-label](#guard-the-act-not-the-label), [checks-narrower-than-their-claim](#checks-narrower-than-their-claim).

<a id="projection-checks-lag-in-one-statement"></a>
### projection-checks-lag-in-one-statement

A guard that reads a projected column (status, refunded_on — written by an AFTER ROW trigger, so queued to statement end) sees the pre-statement value for every row of a multi-row INSERT or writable WITH. Two refunds in one statement passed "nothing after refunded"; a refund notice plus a due row passed "return has started".

**Why:** found by Opus in -15 round 6, then the sibling in round 7 (all three reviewers). Reading the events instead fixes event-vs-event checks (a BEFORE ROW query sees earlier rows of the same statement), but NOT a check on another table in a writable WITH: which part runs first is not fixed (a diagnostic trigger saw 0 events in one order).

**How to apply:** (1) in a BEFORE ROW guard, derive history from the append-only events, never from the projection; (2) for a fact spanning two tables, add an AFTER INSERT row trigger (fires after every part of the statement) and keep the BEFORE check for its message; (3) write the multi-row / chained-WITH battery cases first and see them red on the previous revision (measure the finding), including the legitimate path (a refund citing the new due row in the same statement). See [reviewer-fixes-need-measuring](#reviewer-fixes-need-measuring), [early-return-branches-skip-fences](#early-return-branches-skip-fences).

<a id="append-only-vs-unique-deadlock"></a>
### append-only-vs-unique-deadlock

Three rules that are each individually reasonable can deadlock:

1. the table is append-only (no UPDATE, no DELETE),
2. it carries `UNIQUE (parent, key)`,
3. a gate refuses to proceed on a stale row and demands a current one.

Together: the gate wants a new answer, append-only forbids editing the old one, and the unique key forbids adding one. In v5.4.2-12 this meant a correction draft whose amount changed could never be issued at all. Caught only by writing a test for the RECOVERY path, not the happy path.

**Why:** each rule is added for a good separate reason, and nothing surfaces the contradiction until a flow needs all three at once.

**How to apply:** on an append-only table where re-evaluation is normal, drop the uniqueness key and let the gate read the latest row — but order by a MONOTONIC SEQUENCE, never by a timestamp. `now()` is constant within a transaction, so two rows written in one transaction tie and the gate silently picks one of two different answers. A sequence column needs an explicit `GRANT USAGE ... TO tally_app`; the blanket `ALTER DEFAULT PRIVILEGES` in tu.sql covers TABLES, not SEQUENCES. See [test-the-boundary-not-the-formula](#test-the-boundary-not-the-formula).

---

## Time and coordinates

<a id="temporal-helper-no-live-fallback"></a>
### temporal-helper-no-live-fallback

Any function that resolves a value "as of" a coordinate (pattern set by `get_partial_period_policy(uuid, timestamptz)` in v5.4.1-02, 2026-08-20): the coordinate is a REQUIRED parameter with no DEFAULT; NULL coordinate RAISES; there is NO fallback to the live/current column; a coordinate before recorded history returns NULL, the same contract as "not found." Applies to everything A-1 / A-3 will add.

**Why:** the first draft COALESCEd onto the live `tenants` column; both independent reviewers showed that NULL input (realistic — `get_correction_rate_date()` documents returning NULL) and pre-history input silently resolved to today's value, i.e. the CI-006 time-blind bug the function existed to remove. Recorded as D-2026-08-20-09 in `application/DECISION-LOG.md`.

**How to apply:** when drafting or reviewing a temporal helper, grep its body for COALESCE onto a non-history source and for a DEFAULT on the coordinate parameter — either is a finding. Also persisted: fresh-load tu.sql + patch into a scratch DB before the mirror (the btree_gist `search_path=''` lesson). See [test-fixture-required-columns](#test-fixture-required-columns), schema-provenance.

<a id="date-from-snapshot-knowledge-from-now"></a>
### date-from-snapshot-knowledge-from-now

A check that classifies something at a bill's coordinate (e.g. CI-016's per-unit surcharge test) takes the **date** from the calculation snapshot's `valid_at`, which -10 validates and freezes (the period end, or a correction's elected rate date). It takes the **knowledge** from `now()`, never from the snapshot's `recorded_at`.

**Why:** in -21, r1 read `(period_end, now())`, and Codex showed a correction priced at an elected date was misread. r2 read `(valid_at, recorded_at)`, and Fable showed `recorded_at` is the caller's to pick inside `[created_at, now()]`, so a backdated instant hid a retracted classification. Two reviewers each found one axis.

**How to apply:**
- Treat every coordinate a caller may choose as attacker-chosen, even when it is "admissible".
- Fail safe when nothing is visible at the coordinate: refuse, never read it as the benign class.
- Related: [temporal-helper-no-live-fallback](#temporal-helper-no-live-fallback), [guard-the-act-not-the-label](#guard-the-act-not-the-label). For the same lesson on roles (a demotion switches an administrator off, so guard every column that removes power), see [guard-the-act-not-the-label](#guard-the-act-not-the-label).

---

## Concurrency

<a id="count-guards-need-lock-handshake"></a>
### count-guards-need-lock-handshake

Any tally-utility guard whose refusal depends on counting other tables' rows (an orphan check, a cap sum, a completeness check) races concurrent writers: under READ COMMITTED the in-flight row is a phantom; under REPEATABLE READ even a committed row is invisible to a stale snapshot. An advisory lock is the wrong tool — it serialises writers, not snapshots (v5.4.2-07 HIGH-4).

Refined by v5.4.2-10 (2026-09-08), three rules:
1. **Prefer a row-version mutex to a bare lock.** If the writer `UPDATE … SET updated_at = now()` on the row the guard will also UPDATE, Postgres's own write-write detection makes REPEATABLE READ safe (the racing editor gets `serialization_failure`) and the guard needs NO isolation pin. A bare `FOR SHARE` writes no version, so an RR editor sees nothing and the pin is required (v5.4.2-08 used the pin; -10 replaced it on invoices and correction targets).
2. **Never `FOR SHARE` a row the engine heartbeats.** `FOR SHARE` conflicts with every plain UPDATE (FOR NO KEY UPDATE): a heartbeat waited behind a snapshot transaction and two workers deadlocked through `billing_runs`. Use `FOR KEY SHARE` for the writer and have the guard that must wait escalate its own row `FOR UPDATE` before its EXISTS check. A row version there would block heartbeats again, so this is the one place the READ COMMITTED pin stays — checked AFTER the EXISTS, so a frozen row says "frozen".
3. **One canonical lock order, stated in the AC** (v5.4.2-10: invoice → replaced bill → correction target → billing run). The reverse order in an operator transaction deadlocked against a writer.

Also the review lesson: the re-parent / date-walk / cycle-shrink / retraction / race holes were ONE family — when a reviewer finds one leg, enumerate the family before closing anything.

**How to apply:** see `validate_calculation_snapshot` (v5.4.2-10) for the mutex + KEY SHARE shape, `enforce_billing_run_clock_and_election` for the escalation + pin; DECISION-LOG D-2026-09-08-06/-07. Related: [trigger-depth-fence-inside-guard](#trigger-depth-fence-inside-guard), [freeze-hash-before-reviews](#freeze-hash-before-reviews), [app-written-logs-are-not-guards](#app-written-logs-are-not-guards).

<a id="lock-order-as-a-rule"></a>
### lock-order-as-a-rule

From v5.4.2-22 (mirrored 2026-10-16): four review rounds each found a lock-taking shape missing from the patch's list of shapes. What held was a rule over the rows taken in order, plus "every writer retries 40P01". -23 restates the ledger's and the close's lock order, and keeps -22's form.

**How to apply:** when a patch adds a writer that takes locks, state where it falls in the rule; do not extend a list. See [count-guards-need-lock-handshake](#count-guards-need-lock-handshake), [race-barriers-clear-stat-snapshot](#race-barriers-clear-stat-snapshot).

<a id="race-barriers-clear-stat-snapshot"></a>
### race-barriers-clear-stat-snapshot

Race barriers in `tests/v5.4.2-22/races/close-22.sh` (r6): a session signals a step with `SET application_name`, and the other polls `pg_stat_activity` (or `pg_blocking_pids`) in a DO loop. `pg_stat_activity` is snapshotted once per transaction, so the loop must `PERFORM pg_stat_clear_snapshot()` each iteration. Without it, CR15 and CR17 timed out; CR16 and CR18 passed by luck (the signal came before the first read).

**Why:** cost one failed race run on 2026-10-16. A barrier that passes only when the other side is already there looks fine until the timing changes.

**How to apply:** any new two-session test ordered by barriers. Deadlock races: accept either side as the victim (PostgreSQL picks it), and require exactly one 40P01 with the other side committed.

Also: `mutations-22.py` reads the live battery and race files on every mutation. An edit made during a run (even a label) reaches the mutations that run after it; a broken edit makes them fail on setup. Edit only between runs. See [freeze-hash-before-reviews](#freeze-hash-before-reviews).

---

## Performance

<a id="recursive-walks-join-on-link-alone"></a>
### recursive-walks-join-on-link-alone

Recursive walks over `account_ledger` (or any lineage table) inside trigger functions:
- join each step on the link alone (`l.id = u.id`, `l.reverses_ledger_entry_id = d.id`);
- carry type and customer through the CTE, so the final selection reads the CTE, not the ledger;
- apply tenant/customer tests outside the join: a CASE yielding NULL, or a carried `mine` flag;
- **pin the plan** on the function: `SET enable_seqscan = off`, `SET enable_hashjoin = off`, `SET enable_mergejoin = off`.

**Why:** found 2026-10-16 in v5.4.2-22 r3 and r4.
- On a ledger the planner believes empty (fresh, or just VACUUMed: reltuples 0), each step hash-joined a sequential scan of the whole ledger, running the RLS functions on every row.
- With only seqscan off, it merge-joined a full index scan instead.
- Link-only joins alone were not enough: R10g alternated between passing in 1.5 s and timing out at 30 s, depending on autovacuum.
- Earlier symptom: mutation M57 hung a run for 12 hours.
- Opus measured 5,000 reversals after a 200k-row load at 51 s. Pinned, it takes 0.8 s.

**How to apply:**
- Test performance claims after `VACUUM account_ledger`, not on a fresh clone; the mutation runner VACUUMs before each battery.
- Time deep chains and trees in one statement as `tally_app`, with `auto_explain` (`log_nested_statements`).
- Runners pass `PGOPTIONS=-c statement_timeout=300s`. A timeout check names `query_canceled` explicitly: `WHEN OTHERS` does not catch it.

Related: [reviewer-fixes-need-measuring](#reviewer-fixes-need-measuring), [test-the-boundary-not-the-formula](#test-the-boundary-not-the-formula).

---

## Testing

<a id="checks-narrower-than-their-claim"></a>
### checks-narrower-than-their-claim

v5.4.2-11's verification block asserted "every view runs with invoker rights" while filtering `relkind = 'v'`. It could not see `relkind = 'm'` (four materialized views leaking every tenant's data) and never looked at `relkind = 'r'` (79 tables). It printed a clean NOTICE with two whole classes of hole one and two relkinds away. The same shape recurred three more times in one session: `has_table_privilege` is blind to COLUMN grants; a five-signature by-name check cannot see the sixth function; `coalesce(polqual, polwithcheck)` never inspects `WITH CHECK` while `USING` is non-NULL (read-isolated, write-open).

**Why:** a check that cannot fail is worse than no check — the next author reasonably assumes the gate covers what its name says, so the false confidence propagates. Every one of these passed cleanly and was found only by an adversarial reviewer.

**How to apply:** write the assertion against the PROPERTY (any relation holding tenant data; any grantee that is not the owner; every non-NULL expression on a policy), not against the enumeration you happen to be thinking about. Then write tests that make it RAISE: create the leaky object and require the exception. If a check has never been observed failing, it has not been tested. Prove the consequence before the check — battery G10a proved a cross-tenant write actually landed before G10b asserted the raise, so it could not pass for the wrong reason. Related: [reviewer-fixes-need-measuring](#reviewer-fixes-need-measuring), [strict-pin-vs-rls-helpers](#strict-pin-vs-rls-helpers).

<a id="test-the-boundary-not-the-formula"></a>
### test-the-boundary-not-the-formula

In the v5.4.2-09 rounds, a reviewer flagged an inconsistency between a window's WHERE boundary (`<`) and its displayed `notice_window_opened_on` column. The round-2 "fix" changed the display formula to match the boundary — internally consistent, still wrong: "notify N days before" delivered N−1 days. The second reviewer caught it because the battery check only asserted the column equalled its own formula, which passes whether the boundary is right or wrong.

**Why:** two mutually-consistent wrong things pass any test that compares them to each other. The semantic question ("what does N days before mean?") has one right answer and it decides which side to fix.
**How to apply:** when reconciling two inconsistent expressions, first decide which one is correct against the stated contract, then fix the other. Boundary battery checks must pin CONCRETE values on both sides of the edge (a row at exactly N days IS listed, at N+1 is NOT) — never assert a derived column against the formula that derives it. See [freeze-hash-before-reviews](#freeze-hash-before-reviews).

<a id="every-branch-and-stated-default-tested"></a>
### every-branch-and-stated-default-tested

Every branch of a guard needs a battery fixture that takes it: the exempt branch, the posting path, and every behaviour the patch header or a brief states as "now".

**Why:**
- In -23 r2 no test anywhere posted a refund on the ledger. The refund exemption was keyed on a caller-written `reference_id` and could be abused with a +100 adjustment. Removing it still left 168/168 passing.
- The header, the plan and the Kyle brief all said a bounce with a pending refund is refused, but no code refused it.
- All three round-2 reviewers found both.

**How to apply:**
- When adding a guard with an exemption, write the fixture for the exempt path and a mutation that deletes the exemption.
- When writing "X is refused" in a header or brief, add the battery check in the same change.

Related: [checks-narrower-than-their-claim](#checks-narrower-than-their-claim), [guard-the-act-not-the-label](#guard-the-act-not-the-label), [test-the-boundary-not-the-formula](#test-the-boundary-not-the-formula).

<a id="rule-table-fixture-notes"></a>
### rule-table-fixture-notes

Recorded when v5.4.2-25 (disputes) was built, 2026-10-18:
- rule-table facets and owner types are stored sorted, so fixtures and comparisons must use the sorted form;
- flush a fixture's deferred checks as the owner;
- remove guard pieces that another check always beats: a mutation of them can never fail (see [checks-narrower-than-their-claim](#checks-narrower-than-their-claim)).

---

## Review process

<a id="freeze-hash-before-reviews"></a>
### freeze-hash-before-reviews

Once the review brief is written with `wc -l` + `md5 -q` and both reviewers (Fable `general-purpose`, Codex `codex:codex-rescue`) are launched, the patch file must not change until both round-1 verdicts are in. Fold the author's own probe findings and both reviews into ONE revision, then send the new hash for round 2.

**Why:** in the v5.4.2-07 session the file changed four times during round 1 (author probes + Fable's early findings); both reviewers reported a moving target, froze copies and re-verified by hash — it cost a round and blurred which hash each finding was against.
**How to apply:** keep a `patch-NN-reviewed-<hash>.sql` copy in the scratchpad; after the verdicts, comment-only edits (residual notes) are allowed but must be proven with `diff` on non-comment lines and both hashes recorded in DEPLOY-VERIFICATION. Related: [strict-apply-before-mirror](#strict-apply-before-mirror).

<a id="reviewer-fixes-need-measuring"></a>
### reviewer-fixes-need-measuring

In the v5.4.2-11 review (2026-09-09) every reviewer FINDING was real, but three proposed fixes were wrong: `ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ... FROM PUBLIC` is a silent no-op (PUBLIC's EXECUTE lives in the GLOBAL schema-less default; only the unqualified `FOR ROLE` form works); a `security_invoker` wrapper over a matview is impossible (an invoker wrapper needs the CALLER to hold SELECT on the matview — the grant being removed); "all 81 policies render to one canonical string" is two (`tenants` is keyed on `id`), so a strict-equality check written from that prose would have false-positived on day one. A stated mechanism was also wrong while its conclusion held (per-schema default ACLs are additive with the global one, not precedent over it).

**Why:** a reviewer testing a hole is exercising it; a reviewer proposing a fix is often reasoning. Folding a fix unmeasured ships a change that looks reviewed and is not.

**How to apply:** reproduce the finding yourself, then measure the fix — both branches where they differ. State the corrected mechanism in the patch header so nobody "fixes" it back. When two independent reviewers converge on the same miss (three times in that session: matviews, tables never checked, the WITH CHECK hole), treat it as near-certain and act. Related: [checks-narrower-than-their-claim](#checks-narrower-than-their-claim), [freeze-hash-before-reviews](#freeze-hash-before-reviews).

<a id="rule-table-keys-are-text-codes"></a>
### rule-table-keys-are-text-codes

Found drafting v5.4.2-30 (2026-11-05): `rule_table_register` requires each area-key column to be `text NOT NULL`, so a row id (uuid) cannot key a rule row. The template's terms validator also refuses a number written with trailing fractional zeros (`1.0`).

**Why:** the template keys rows by codes (state, service, system kind) so a rule row means the same thing across the life of the thing it names. A place's row id changes when the place is closed and succeeded (the -29 Texas succession defect); its kind and code do not.
**How to apply:** key a rule row that names a place by `place_kind` and `place_code` within its `state_code`, and resolve the place in force over the row's dates in the insert check (its successive rows may cover them together). Write terms numbers canonically in fixtures and seeds.

<a id="history-stamped-at-xact-start"></a>
### history-stamped-at-xact-start

v5.4.2-30 r2 recorded each premise's state in a history stamped `now()` (the transaction's start) and read the latest stamp. Two operators correcting one premise at once: the transaction that began first waits on the row lock, commits last, and its row sorts *below* the one it overwrote. The premise then sits in one state while every "as known now" read answers the other, forever, with no error (Opus and Fable, r2, two sessions).

**Why not `clock_timestamp()`:** a correction voids memberships in the same transaction; those voids are stamped `now()`. A history row stamped by the clock post-dates them, so a read between the two sees the old state without its places. One transaction must keep one instant.

**How to apply:** for any database-written history read latest-first by a `now()` stamp, have the writer refuse with 40001 (retry) when the entity already has a row stamped after its own `now()`. Both writers hold the entity's row lock, so the second sees the first's committed row. Test it with a two-session race in which the earlier-begun writer reaches the lock second, plus a planted future-stamped row in the battery. Reads at an instant still inherit the general limit that a writer in flight at that instant is invisible until it commits (-30 L7).

<a id="succession-checks-at-commit"></a>
### succession-checks-at-commit

-16's places are closed once and continued by a successor row of the same kind, state and code, and a code's rows never overlap. So the successor can only be inserted *after* the close. A rule like "a place is never closed while a levy keyed by its code runs past it" cannot be checked at the close: it would refuse every succession (-30 r2).

**How to apply:** make it a `DEFERRABLE INITIALLY DEFERRED` constraint trigger (`AFTER UPDATE OF effective_to`, `ENABLE ALWAYS`) that measures coverage across all the code's rows at commit. A close and its successor in one transaction pass; a dissolution waits for the dependent row's own close. The check runs under whatever role holds the session at COMMIT, so it must itself require the all-tenants role the close required (Fable r2 S1). The writer of the dependent row takes each found row's lock shared and then re-reads the rows, refusing (40001) if one was committed while it waited (-16's race R19 rule). In a battery, plant stamps before any close: `ALTER TABLE` is refused while deferred trigger events are pending.

## constraint-trigger-name-order

**Lesson (2026-11-07, -25 r2).** A deferred constraint trigger normally fires at commit, after every AFTER trigger of the statement. Once anything in the transaction has run `SET CONSTRAINTS ALL IMMEDIATE` (a battery's deferred-check helper does), it fires at statement end with the other AFTER triggers, in trigger-name order. -25's `enforce_dispute_reading_released` (reading the dispute's status) sorted before `z_dispute_move_status` (writing it), so it saw the dispute still open and passed a case it should refuse; the test passed nothing and looked like a broken guard.

**Why:** the firing point of a deferred trigger depends on the transaction's constraint mode, not only on its declaration.

**How to apply:** name a deferred check that reads another trigger's write so it sorts after that trigger (`zz_…` after `z_…`). In a battery, set the constraint back to DEFERRED after forcing it, and debug a silent pass by printing what the trigger sees.

## check-names-its-own-guard

Found by -25 r2's first full mutation run (2026-11-07): 121 of 125 caught.

- **Shared tags.** -25 refuses an amount or a determination on a resolved dispute twice: a BEFORE guard reading the status, and a commit-time check reading the events (for the same-statement shapes). Both messages carry [D2e] and [D4k]. Battery checks D2m and D4k matched the tag, so with the BEFORE guard mutated away the backup refused instead, and the checks still passed (M43, M55). Words they share ("nothing is recorded on it after") don't separate them either.
- **Empty lists.** M120 emptied `c_col_acls`, the list the unlisted-grant leg subtracts. That list was already empty, so the mutation changed nothing.
- **The wrong leg.** M124 removed the policy check's leg for a listed policy that changed or went missing, while its check, H16f, adds an unlisted policy.

- **A rule made exact.** -24 r8 made a misposting return equal the share exactly (it had been "at most"). The checks that proved the share by refusing share + 0.01 then passed under any wrong share, since every amount but the right one is refused; three mutations went missed (M106, M109, M111). Each such check now offers the amount the wrong rule would give.

**Why:** a check that passes whichever guard fires proves neither guard. A mutation that changes nothing, or changes a leg its check never reaches, reads as a missed guard that isn't one.

**How to apply:** when two guards can refuse the same row, give each battery check a phrase that only its guard writes, and keep the shape the backup guard holds as a separate check. Mutate the leg that the named check's shape actually reaches. When a list in the manifest is empty, mutate the query that finds extras, not the list. Run the full mutation suite once before a round freezes: that run is what catches these. Related: [checks-narrower-than-their-claim](#checks-narrower-than-their-claim), [rule-table-fixture-notes](#rule-table-fixture-notes).
