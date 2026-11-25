# Codex — v5.4.2-25, review round 2

**Verdict: not yet.** Two predicted blocking defects remain: the same-statement close guard can confuse IDs from different tables, and the reading-release check has no handshake between concurrent closes of different disputes on one reading. Stage comparison also falls short of the stated never-looser promise.

This is a whole-patch, source-only review, not a review of only the r2 delta. No database, Docker, psql, CI, race script, terms runner, migration runner, or mutation runner was executed. No other reviewer's files were read. “Executed” below means a filesystem/source check actually performed; every database result is **predicted**, with a probe supplied for the author.

## N1 — executed: frozen inputs verified before review

All eleven MD5 checks matched before source review. The first checksum command had a filename construction error (`.md.md5`) and read no patch; the corrected command verified every entry successfully.

| File (under this review directory) | Expected and observed MD5 | Result |
|---|---|---|
| `review-brief-25-r2.md` | `99615d0997bad7a775065792844fb19f` | match |
| `patch-25-frozen-r2.sql` | `edf445bbdae2e1246f1f4ccd38464da5` | match |
| `battery-25-frozen-r2.sql` | `50f48c07e45fb95905f365075e5df862` | match |
| `disputes-25-frozen-r2.sh` | `9fb24be54e778203d23023c7fe8570f9` | match |
| `mutations-25-frozen-r2.py` | `1a6213269fc9e8b38afb8d871721771a` | match |
| `terms-25-frozen-r2.py` | `83d1484349ef8c3ad654eb40f2264eb6` | match |
| `migration-25-frozen-r2.py` | `55d80759b4066f5a037acc3bd104be20` | match |
| `fill-manifest-25-frozen-r2.py` | `e0664cca97f532fa4e62ae33e5824190` | match |
| `dispute_platform_defaults-frozen-r2.yaml` | `deb668299bc3bd44d1eb72a1aeb117d4` | match |
| `dispute_platform_defaults-frozen-r2.seed.sql` | `3832a44f5ae4c788a8451479390906ec` | match |
| `r1-to-r2.diff` | `46289b5a1048074a4c2d33a5a5641108` | match |

Read the r2 plan (including Item 9 design/as-built and Item 8 role), original design, inventory D, the 2026-11-22 and superseded November 7 decision-log entries, GBM's November 5 scenario answers, and the relevant -17/-23 source and seal lesson. Reviewed the frozen patch, battery, races, mutation definitions/runner, terms tests, migration checks, manifest generator, default YAML/seed and delta. Source verification also found all **30** pinned function-body MD5s equal to their frozen bodies; the default seed statements are embedded verbatim.

## B1 — predicted: matching UUIDs bypass “nothing after resolution” across tables

**Evidence:** `patch-25-frozen-r2.sql:3022` in `enforce_dispute_nothing_after_close()` filters closing events with `e.id IS DISTINCT FROM NEW.id`. This function is attached to **events, amounts and determinations**. Equality of an amount/determination ID and an event ID does not make them the same record; their primary keys are independent and application INSERT grants include `id`.

In a dependent writable CTE, insert a withdrawal first, then insert an amount (or determination) with that withdrawal's UUID. Its `record_seq` follows the closing event, but the AFTER guard excludes the event. The BEFORE guard still reads the pre-projection open status, which is exactly why r2 added the AFTER check. The same attack with distinct UUIDs should be refused.

**Probe:** [01-cross-table-id.sql](codex-r2-probes/01-cross-table-id.sql). Runs both shapes as `tally_app`, each with a distinct-ID control. Predicted: controls raise 23514 with D2e/D4k; equal-ID attempts succeed and print a later row sequence alongside a withdrawn status. The determination case uses a legitimate pre-default municipal `no_terms` determination to isolate the close guard.

**Fix:** remove the UUID exclusion (the strict sequence comparison already excludes the closing event itself), or qualify self-exclusion by the actual source table. Add equal-ID regression cases for both non-event tables. This leaves r2 plan item 1 incomplete and repeats the substance of the round-1 blocker, despite the ordinary CTE tests passing.

## B2 — predicted: two closing transactions can strand a reading in `disputed`

**Evidence:** `patch-25-frozen-r2.sql:3389`–3414, `enforce_dispute_reading_released()`. It reads sibling disputes' status without acquiring their locks or a shared reading-level mutex. `enforce_dispute_event()` takes only the closing dispute's mutex; `dispute_move_status()` updates only that dispute. The all-disputes locking loop exists in the reading's own status UPDATE, which neither closing transaction is required to perform when it sees another open dispute.

Starting from reading R marked disputed with open disputes A and B:

1. Session 1 closes A; session 2 closes B. Their dispute mutexes differ.
2. Before either commits, both run `SET CONSTRAINTS public.zz_dispute_reading_released IMMEDIATE` (or reach their deferred checks concurrently).
3. Session 1 sees B's committed open version; session 2 sees A's committed open version. Both checks pass.
4. Both can commit, leaving no open dispute and R still disputed.

READ COMMITTED does not order these reads. The advertised retry-on-deadlock contract does not help when the two operations never contend.

**Probe:** [02-reading-close-lock.sql](codex-r2-probes/02-reading-close-lock.sql). This is explicitly a **one-leg lock witness**, not a claimed execution of the two-session schedule. It establishes a valid two-open-dispute state, restores the setup-only disabled reading-status trigger, runs the invariant, closes A and forces its deferred check, then prints whether each dispute's advisory mutex is held. Predicted: A held, B absent. The file documents the exact concurrent schedule for the author to extend into the race harness. Its setup avoids acquiring both advisory locks through the fixture's status update; otherwise the fixture itself would conceal the missing handshake.

**Fix:** serialize all operations that decide the reading's open-dispute count on a stable common mutex, including opening a dispute, closing one, and moving the reading. Specify the acquisition order before adding sibling locks after a caller already holds its own lock. Add the two-close race and both orders of close versus reading-status movement. Item 6 is not closed under concurrency. The frozen DR1–DR12 script has no reading fixture or reading-status race, notwithstanding the plan's proposed coverage.

## S1 — predicted: stage comparison preserves categories, not the required stage's protections

**Evidence:** `patch-25-frozen-r2.sql:1810`–1819. The comparator reduces law stages to distinct `decider` strings. It explicitly does not compare deadlines, and also does not preserve their ordering or multiplicity. A tariff can retain the designated-employee and regulator categories while changing the seeded regulator's decision deadline from 15 to 3,650 days and imposing a one-day appeal deadline where the law document has none; the comparator returns no problems.

**Probe:** [03-stage-comparison.sql](codex-r2-probes/03-stage-comparison.sql). Derives a tariff-shaped document from the frozen protected law row, prints the equal-stage control, validates the narrowed document, and prints the comparator result. Predicted: no schema errors and empty comparison problems for both. This is a comparator probe, not a claimed executed tariff insert.

Item 2 says the tariff includes every stage the law requires. Matching only the category is weaker, and the “never looser” claim is broader still. Compare filing/decision windows in their protective directions and preserve required stage order, or obtain and document a narrower contract instead of treating the category check as completion. N9b/M114 only remove a category and cannot detect this.

## S2 — executed (source): a refusal test's fixture is weaker than its label

`battery-25-frozen-r2.sql:835` (D4f) says it tests another utility's tariff, using ID `…25ac`. N1b creates that tariff through `admits_undone`, so it no longer exists when D4f runs. The test exercises “not found,” not a visible foreign tariff's tenant/state/service/system comparisons. M65 removes that entire branch; a failure at D4f is therefore not proof that those individual comparisons have meaningful coverage.

Keep a real foreign tariff fixture and separately test the not-visible case and the owner/platform-visible mismatch cases; mutate the individual comparisons. This is a source-level test-quality finding, not a claim that the composite FK can be bypassed. The instrumented [00-contract-battery.sql](codex-r2-probes/00-contract-battery.sql) preserves the frozen fixture lifetimes for the author's baseline run.

Other source test limits: S2's “committed files (their ids and hashes)” checks ID strings and hash **format**, not equality with a committed schema hash; P15's pre-default half is actually P15b; H18b is an unmodified invariant smoke check, H18c tests extra grants, and H16d tests the dispute invariant's owner leg—not an independent owner-drift test of the carried seal invariant. The mutation runner requires the first reported failure to have its target label, which is useful, but a label alone cannot repair a weak fixture. I did not reproduce or independently certify the reported 140/141 run or its timing-flake explanation.

## N2 — predicted: item-by-item disposition and platform-default review

Database evidence for the ordinary boundaries is supplied as [00-contract-battery.sql](codex-r2-probes/00-contract-battery.sql), a standalone copy of the frozen battery with SQLSTATE/message notices added to every caught error, ending in ROLLBACK. It has **not** been run. It preserves the author's assertions rather than representing new independent coverage. [06-catalog.sql](codex-r2-probes/06-catalog.sql) supplies the invariant, grants and FK inspection checks.

| Plan item | Source-review disposition / probe checks |
|---|---|
| 1, records after close | Incomplete: B1. Ordinary multi-row and CTE shapes are in D5r/D5r2/D4k2/D2m2. |
| 2, duties and stages | Duty superset implemented; stage categories added, but S1 remains. N9a/N9b and equal/wider controls. |
| 3, counted end | Required and capped for a sheltered determination; equal day 60 versus day 61 and NULL covered by D4p/D4p2/D4x, D7c/D7c2/D7f. |
| 4, cite own tariff where law governs | D4q branch added; source order checks a supplied tariff before reading its document. D4q is the refusal test; add a successful law-plus-tariff determination counterpart. |
| 5, positive-charge amount cap | Added before amount stamping; D2g/D2g2 test 100.01 versus 100. Per-line cap remains D2c/D2. |
| 6, reading released | Single-transaction check added; T2e0/T2e/T2f. Concurrent closure gap B2 remains. |
| 7, tenant keys | New record-table links use tenant composites or a dispute composite that ties the row to its tenant; tariff `(id,tenant_id)` added. Inspect exact FKs with 06. Replica-mode FKs are not universally active; H17 covers specifically a dispute naming another tenant's bill, not every FK under replica mode. |
| 8, invariant and move role | Implemented in source; see N3. This freezes the implementation, including B1/B2, and does not prove its semantics. |
| 9, default | Representation and citation precedence follow the November 22 plan; P1–P15b and D7–D7p2 are the supplied baseline cases. |

For item 9, the default is a separately registered **table**, not a second ambiguous law row in `dispute_rules`. The template's registry, exclusion construction, lookup and citation functions take a table identity, so sharing the `dispute` kind does not merge the two tables' applicability spaces. No -17 function or delegation schema is loosened. The default's insert check rejects delegation and all three unruled sections, validates the class and invokes the document checks. The common facets still provide vocabulary validation. Its two seed documents cover both municipal gas classes, from November 22, and label their authority as the platform ruling.

The determination requires the tariff if present; otherwise, under a delegation, the matching default; otherwise `no_terms`. D7k excludes a default alongside a tariff or governing law. D7a/D7b and D4n cover absent/wrong/uncited defaults and a false `no_terms`. The initial default lookup is not itself locked, but the acceptance path calls `rule_law_row_cite`, which locks, rechecks in-force dates and resolves applicability again. The close floor uses the latest **received** date among all citations, including superseded determinations. P11, P15/P15b, D7b3, D7o, D7p/p2 exercise these boundaries; DR10's source tests citation-first close contention. Add a close-first/default-citation race and an explicit already-closed default citation case.

The November 22 start date and due-date-inclusive `before_delinquency` reading are supported by the recorded decisions/as-built plan, rather than new schema policy decisions in this review. Whole-bill treatment when no customer amount is supplied and the next-regular-bill due date after day 60 remain core evaluation/workflow obligations: the YAML says so explicitly. The database reader alone does not implement that whole-bill fallback (it reports zero before a determination, as R4 asserts); integration must materialize the evaluated amount/determination before relying on that reader for collection decisions.

## N3 — executed (source comparison); runtime checks predicted: seal and invariant preservation

The carried `assert_seal_role_invariants()` body was compared to the last definition in `sql/tu.sql`. Its changes are the new function ownership entry, the new exact grants entry/comment, and addition of `tally_dispute` to the role loop. Existing role grants, membership checks, ownership checks, core-definer restrictions and trigger list remain intact. The manifest generator now scopes its list replacement to `assert_dispute_guard_invariants`, avoiding the earlier seal-list overwrite.

The new role owns only `dispute_move_status()` in the stated allowlist, gets the required RLS helper execution and column grants, and the update guard keys actual status changes on `current_user`. RLS is intentionally applied inside the definer. A history writer must set a valid `app.user_id`; owner/BYPASSRLS rights outside the function do not supply its missing identity. [05-roles-and-isolation.sql](codex-r2-probes/05-roles-and-isolation.sql) covers owner-without-identity refusal, a valid replica-mode owner close, app/core direct-update refusal, and isolation pins. H18/H18c/H18d and H16 cover the baseline role and drift checks. No probe creates, drops or alters a role.

The dispute invariant checks the listed trigger definitions and ALWAYS state, validated constraints, valid unique indexes, body hashes, attributes, ACLs, NOT NULLs and exact policies. It is a catalog-drift assertion, not a scan for corrupt historical rows or a proof of lock correctness. It also does not claim that arbitrary extra triggers on ordinary dispute tables are forbidden. The template's own invariant provides its stricter restrictions on registered rule tables.

## N4 — predicted: paths, concurrency and residuals

- **Statement shapes:** the baseline probe covers ordinary inserts, multi-row events and writable CTEs; 01 adds chosen cross-table IDs. [04-copy.sql](codex-r2-probes/04-copy.sql) submits withdrawal plus escalation through owner COPY and prints COPY's own verbose error using `\errverbose`; it never trusts `LAST_ERROR_SQLSTATE`. Predicted refusal is D5f/23514, and its savepoint is rolled back. No database COPY result was observed.
- **Roles/isolation:** app and core paths are distinguished in 00/05/06; owner history paths retain ALWAYS guards and owner-selected stamps, with the status move subject to RLS. `dispute_lock` requires the literal READ COMMITTED setting; 05 probes REPEATABLE READ, SERIALIZABLE and READ UNCOMMITTED as refusals. Replica mode does not make ordinary foreign-key triggers ALWAYS, so do not generalize H17 to a complete historical referential-integrity audit.
- **Locks:** amounts/determinations/events use the dispute mutex; accepted citations then use law and tariff/default shared locks, matched by exclusive close locks. B2 is the missing ordering handshake. Reading UPDATE additionally already holds a reading tuple lock before its BEFORE trigger acquires dispute locks; operations touching multiple disputes can deadlock and need the stated retry contract. A repair should state the complete order, including the default and reading locks, rather than the header's current “nothing else.”
- **R6:** absence of a tariff is a lookup without a predicate mutex. The patch deliberately permits later backdated policy, so there is no serializable “no tariff can appear” promise. DR11 explicitly runs in turn; it is not a race proving concurrent insertion/citation ordering. Keep the audit obligation and add concurrent-policy coverage if a stronger promise is intended. I do not promote the accepted retroactive-policy residual itself to a blocker.

R1 (governmental class) and R2 (conditional PA shape) are bounded scope limitations. R3 (core evaluates eligibility/amounts), R4 (decider category, not the user's authority) and R5 (no reading-only shelter helper) are disclosed division-of-responsibility limits. R7 is a valid seal/RLS application contract, not a superuser-definer escape. R8 is a core term-boundary contract. None of R1–R8 by itself warrants a new blocker under the settled scope; B1 and B2 violate promises the patch does make and are not covered by those residuals.

**Required before ready:** close B1 and B2, address S1's incomplete stage comparison, repair the misleading test coverage in S2, regenerate the affected manifests, and have the author execute the supplied probes plus the added race/boundary tests. All runtime outcomes in this review remain predicted.
