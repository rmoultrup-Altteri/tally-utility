# Decision Log — schema decisions, with the why

A permanent, cumulative ledger of decisions made while bringing `sql/tu.sql` to parity with the spec. Newest session on top; never rewrite an old entry (append a dated correction instead). `HANDOFF.md` is rewritten every session and is **not** a durable record — anything worth keeping from its Key Decisions / Failed Approaches tables is copied here at wrap-up. Kyle's rulings live in `gas-billing-memory/application/`; this file records the drafting-time calls made inside those rulings and the Phase 2/4 calls Ryan owns directly.

Format per decision: **what** → *why this, and why not the alternative* → where it lives.

---

## 2026-09-08 (A-3 follow-up) — v5.4.2-10: the snapshot's coordinate pair is bound to facts the database holds (A-23 1e)

Kyle-independent work while A-2 waits on his Part 4. Ryan ruled strict on both drafting calls (an ordinary bill is priced at exactly `period_end`; a correction with no correction-run target row is refused). Five hash-frozen review rounds (`bb7cdbd9` → `9160f8af` → `2530daf7` → `2d0ece3c` → `f143c1cb`; Fable `general-purpose`, Codex `codex:codex-rescue`); round 1 found a CRITICAL and two HIGHs, round 2 two semantic MEDIUMs, round 3 one shared lineage gap, round 4 two LOWs (rebill typing; a pre-existing tenant-blind FK), round 5 confirmatory.

### Decisions

**D-2026-09-08-01 · An ordinary bill's `valid_at` IS its `period_end`, exactly — not "a date inside the period".**
*Why:* the v5.4.2-03 formula convention prices at `period_end`; a snapshot priced at a read date would be a silent engine defect, and a bracket would admit it. If read-date pricing is ever wanted, the guard changes with the engine — visibly. (Ryan, strict.)

**D-2026-09-08-02 · A correction's `valid_at` is whatever `get_correction_rate_date()` resolves at insert; no re-derivation at issuance; the election inputs are frozen instead.**
*Why:* the v5.2.1 resolver IS Kyle's correction-rate-mode ruling (custom > per-target > run default); reimplementing it would fork the ruling. Its `current` branch is `CURRENT_DATE`, so a re-derivation at a later issuance day would falsely refuse — the freezes on the target row, the run's election and `run_type`, and the draft's binding columns are what hold the insert-time check.

**D-2026-09-08-03 · A correction must sit on a correction run with a `correction_run_targets` row; an off-run manual rebill is refused.**
*Why (Ryan, strict):* the target row is where the operator's rate-date election is recorded (CI-005); a rebill with nowhere to record its election is exactly the bill an auditor asks about. Nothing previously required this — it is a new rule, chosen knowingly.

**D-2026-09-08-04 · The replaced bill must be RLS-visible, same-tenant, `void`, and once issued (`first_issued_at`).**
*Why (round 1 Fable HIGH-2/3, Codex MEDIUM-3; round 2 Fable MEDIUM-1/2):* a live draft as the "original" let the resolver read a `period_end` the attacker moved after the check and let a deletable draft snapshot anchor an original-world replay; only a void bill's period and snapshot are sealed (A-4 / CI-015). A held-then-voided discard is a real void row nobody was billed for — hence `first_issued_at`, stamped by the database on the first draft/held → non-void issued transition, write-once, INSERT values discarded (the app-written `invoice_events` could not serve as the check; it serves only the one-time backfill, stated as an approximation). (Uniqueness: D-08.) *Not chosen:* binding the correction's period or customer to the original's — `service_date_error` and `wrong_customer` are void reasons and the rebill legitimately moves both.

**D-2026-09-08-05 · `recorded_at` lies in `[run.started_at, now()]` (on a run), `[invoice.created_at, now()]` (off-run), or — for a correction only — equals the replaced bill's snapshot `recorded_at`; both lower bounds are the database's clock; `data_cutoff_at` is not a coordinate.**
*Why:* AC-15 says `recorded_at` is now() at calculation, or the original run's instant to reproduce a bill (16-bi-temporality §5.1 "original world's truth"); a correction cannot invent a third instant. `started_at` is stamped on set and write-once; `created_at` is stamped at INSERT and write-once for non-superusers **regardless of snapshot state** — round 1's CRITICAL was a plain UPDATE of `created_at` on an unsnapshotted draft setting the off-run bound to any year. `data_cutoff_at` (Fable, disagreement) is the candidate-set freeze line by entity `created_at`, not the transaction-time coordinate of the reference lookups; an engine wanting cutoff knowledge starts the run at the cutoff. AC-15's "one pair per run" is deliberately not enforced (per-target original-world replays differ) — A-23.

**D-2026-09-08-06 · Writers hold the run row FOR KEY SHARE, never FOR SHARE; the election guard escalates its own row to FOR UPDATE.**
*Why (author probe, Fable MEDIUM-4):* FOR SHARE conflicts with every plain UPDATE of the row — a heartbeat waited behind a snapshot transaction, and two workers bumping run totals deadlocked. FOR KEY SHARE conflicts only with FOR UPDATE / DELETE / key changes, so heartbeats pass (3 ms live) and the election change still waits behind in-flight writers and then sees them.

**D-2026-09-08-07 · The validator writes a row version onto the invoice, the replaced bill and the target (UPDATE of `updated_at` — the -08 mutex idiom); the invoice and target freeze guards therefore carry no isolation pin; the run guard keeps its pin, EXISTS-first.**
*Why (Codex round-1 HIGH-1, Fable + Codex round 2, independently):* a REPEATABLE READ editor whose snapshot predates a writer's commit fails on the row version with Postgres's own `serialization_failure`, and one that starts later sees the snapshot — so RR edits of never-snapshotted drafts are admissible. A row version on the run row would block heartbeats again, so there the absence of a concurrent snapshot cannot be verified under RR and the pin stays (checked after EXISTS, so a frozen row says "frozen"). (Lock order: D-08.)

**D-2026-09-08-08 · One live snapshotted correction per bill LINEAGE, not per replaced bill: the check walks `replaces_invoice_id` to the root and looks at every descendant at any hop; the root's row is the mutex.**
*Why (round 3, Fable LOW-1 and Codex MEDIUM-HIGH, independently):* per-hop scoping let C correct the void B while D corrected A directly — two live bills for one service, the shape round 2 had closed one level down. A correction of a correction supersedes the whole chain; the customer has one live bill per lineage. `invoice_lineage_root()` is bounded at 64 hops (check_reversal_chain_depth caps chains) and runs invoker-rights, so a chain leaving the caller's tenant ends where visibility ends. Lock order: invoice → lineage root → replaced bill → target → run; an operator transaction touching a void bill and its targets edits the bill first (Fable LOW-2).

**D-2026-09-08-09 · Only `correction`, `credit_memo` and `duplicate` may carry `replaces_invoice_id` through the binding; the lineage count covers every other live snapshotted descendant; the `replaces_invoice_id` FK is tenant-composite.**
*Why (round 4, Fable LOW-1; Codex LOW):* a `regular` bill with `replaces_invoice_id` set was a rebill in all but name and escaped a count keyed on `invoice_type = 'correction'` — typing is caller-chosen, so the count keys on the link, and the ordinary shape refuses the link on any type that is not a credit memo or a reprint. The plain FK let any tenant point `replaces_invoice_id` at any tenant's bill (pre-existing); the lineage walk now traverses that column, so the FK moves onto A-3's `UNIQUE (id, tenant_id)` with a self-verifying precondition that names existing cross-tenant links rather than silently failing the ALTER.

### Failed approaches (permanent record)
- **Freezing `created_at` only while a snapshot exists** — the draft window before the snapshot is exactly where a caller moves it. Write-once always.
- **Accepting any `void` row as a correction's original** — a held-then-voided discard is void and never billed. The database needs its own "was issued" fact; the app-written event log is not it.
- **Uniqueness scoped to (run, replaced bill)** — a second correction run rebilled the same bill. Scope to the bill; mutex on the bill's row.
- **FOR SHARE on a row the engine heartbeats** — blocks every plain UPDATE for the writer's whole transaction; two writers deadlock through it. FOR KEY SHARE + FOR UPDATE escalation in the guard that must wait.
- **An isolation pin where a row version does the work** — where the writer UPDATEs the row an editor must also UPDATE, Postgres's write-write detection already makes RR safe; the pin only refused legitimate edits. Keep pins only where no row version can be written.
- **Counting rebills by `invoice_type`** — the type is caller-chosen; count by the lineage link, and refuse the link on types that are not rebills.
- **Templating race scripts with sed** — a stray line left a session that never committed, and the "race" passed for the wrong reason. Write each session's SQL out in full.

### Outcomes
- tu.sql 20,407 → 21,165 (pure append; anchors 337/3600/3679 intact). Catalog after -10: 82 tables / 81 policies / 80 FORCE RLS / 357 CHECKs / 357 FKs / 10 EXCLUDE / 59 UNIQUEs / 255 triggers (187 ENABLE ALWAYS) / 571 indexes / 392 functions; TEMP revoked. Battery 58 green on clean, pre-seeded and the fresh build; the -09 battery still green on the build. Nine live two-session shapes green (`tests/v5.4.2-10/review/races/`).
- GBM: CI-015 text amended (the pair is bound); CI-005 text (target row required; replaced bill void + issued); CI-003 unchanged (the engine's use of the pair is still discipline — R-16); A-23 (1e) → LANDED, new (1f) residue: direct EXECUTE on `get_correction_rate_date` by `tally_app`; AC-15 "one pair per run" unenforced; `duplicate` unbound; parity plan A-3 line amended; ingestion Section BA.
- Next: the small structural residuals (four views' `security_invoker`, A-23's three unpinned definers, `anomalies.entity_type` CHECK); socialize AC-29–AC-31; Kyle brief consolidation; A-10 / A-2 per the fence.

---

## 2026-09-04 (A-9) — v5.4.2-09: tax exemption certificate evidence and renewal surfacing

Wave 3's first landing (A-2 is fenced by Kyle's own Part 4 stop). Three review rounds (hashes `b8318398` → `af834c44` → `90af192e`, frozen per round); round 1 surfaced a CRITICAL and a HIGH, round 2 caught the author fixing a boundary's display instead of the boundary.

### Decisions

**D-2026-09-04-01 · Certificate evidence means "contains at least one alphanumeric character" — a content whitelist, not a whitespace blacklist.**
*Why:* the drafted `btrim()` blank-check strips ASCII space only; a single tab, newline or NBSP passed as evidence (Codex CRITICAL, round 1). Enumerating invisible characters is an open-ended family (NBSP variants, zero-width, combining marks); requiring one `[[:alnum:]]` character closes the family in one move and also refuses punctuation-only placeholders. Verified against 20 unicode edge values under `en_US.utf8` (non-Latin scripts pass — no over-blocking; circled digits and lone combining marks refuse). Residual, accepted: letter-bearing placeholders ("N/A") pass — inherent to any content test; the gate is an omission barrier, not a fraud barrier. Lives in `enforce_tax_exemption_lifecycle` and the deploy precondition, expression-identical.

**D-2026-09-04-02 · The deploy precondition blocks on EVERY current assertion head (active, expired, revoked) lacking required evidence — not just active.**
*Why:* `customer_tax_exemption_as_of` does not filter on status, by A-1 design — a current revoked/expired head still suppresses tax for its bracket on any rebill, and unlike a draft it can never be fixed in place (Codex HIGH, round 1: a pre-patch evidence-less revoked head sailed past as a NOTICE and `should_charge_tax` kept honouring it, unfixable forever). Closed history stays NOTICE-only: as_of never returns it at current knowledge. Old legacy heads blocking a deploy is the correct trade-off vs silently permanent under-taxation — refuse and report, never audit first (the R-13/R-4 pattern).

**D-2026-09-04-03 · The certificate-required-vs-flag-only designation is per category in `tenants.settings` behind a raising accessor, DEFAULT TRUE; wrong shape at ANY path level raises; flips are audited and never re-judge asserted rows.**
*Why:* R-13 ruled the table holds certificate-backed exemptions only and Rule 3.287 puts the liability on the seller — required is the only defensible default. The A-20 settings-accessor pattern (validated, loud, defaulted) fits because a boolean per enum category has no unit-confusion failure (the CCK-9 objection to jsonb config was a 10x numeric typo); but `#>>` path traversal reads a malformed ancestor as "absent", so both the `tax_exemptions` node and the `certificate_required` node are shape-checked (rounds 1 and 2 each found one level). Config sincerity: the gate consults the knob at entry to assertion only — a later flip cannot invalidate frozen rows — and every flip lands in v5.4.1-02's `tenant_configuration_history` (verified live, full old/new subtree).

**D-2026-09-04-04 · No stored `renewal_due_at`, no `renewal_notice_sent_at` on the exemption row; the renewal prompt is a view plus a tenant window config.**
*Why:* both are later facts about a frozen assertion — the exact shape D4-1's `remitted_on` rejection named on A-7. `renewal_due_at` is derivable (the view's `notice_window_opened_on`); notice-sent tracking belongs to the communication-log work CI-046's scope note already assigns it to. A mutable timestamp on a bi-temporal row is a hole in the freeze.

**D-2026-09-04-05 · The renewal queue admits a row ON the day exactly N days remain (`<=`), and a LAPSED row stays listed — even with a renewal on file — until its valid-time expiry succession closes it.**
*Why:* "notify N days before expiry" means the first notice day has N days remaining; the drafted `<` silently gave N−1 days, and the round-2 "fix" bent the displayed `notice_window_opened_on` to match the wrong boundary instead of fixing it (Codex, round 2 — the battery's check asserted the column against its own formula and could not catch it; the replacement check pins the boundary to real dates). Lapsed-stays: a gapped renewal used to hide a lapsed head entirely (Fable, round 1), but the lapsed head owes its expiry succession regardless — it leaves the queue exactly when that succession lands. Suppression by a renewal on file applies only to rows still inside their bracket.

**D-2026-09-04-06 · The legacy `customers.is_tax_exempt` / `tax_exemption_*` columns stay unguarded — recorded residual, not a patch item.**
*Why:* `should_charge_tax` reads only the exemptions table (verified independently by both reviewers), so the manual flag cannot cause under-taxation; the divergence is display-only (`customer_summary`, `compliance_statistics`, hard-coded 60-day window). The honest fix is a DB-written projection in the A-21 `deposit_*` style, which rebuilds `compliance_statistics` — out of A-9's scope, queued as a register note under CI-046.

**D-2026-09-04-07 · No per-category certificate validity period is seeded.**
*Why:* "typically 1–5 years" is not a citable figure per category; the certificate's own `effective_end` is the validity period, set per row from the document. Seeding a default length is the corrected-water-rule / R-21 failure mode: a number nobody can cite, in a compliance table.

---

## 2026-08-31 (A-7 follow-up) — v5.4.2-08: ruled surcharge lines, invoices and rules freeze together

Ryan's directive ("land the -08 rider now") on Fable's -07 residual; four review rounds (hashes `0f04ee93` → `7acb4dbd` → `cd9abc58` → `f7372b30`, frozen per round) each closed a vector and surfaced the next member of the same family — every route to billing one service past the cap by moving something OTHER than the line's amount.

### Decisions

**D-2026-08-31-09 · A ruled surcharge line's `invoice_id` is frozen exactly like its `rate_item_id`; reclassifying or relocating a line is delete + new line.**
*Why:* with the rider link frozen (-07), re-parenting the line onto a draft dated outside the cycle found no rule at the destination — the guard is date-scoped — freeing the (rate item, meter) total in-cycle (Fable, -07 final pass). Uniform refusal beats a destination-date check: delete + rewrite re-runs every check where the line lands.

**D-2026-08-31-10 · An invoice's `invoice_date` cannot walk a ruled line out from under its rule: the NEW date must resolve to the SAME rule row; within-cycle moves are free.**
*Why (both reviewers, independently):* a draft's date was freely editable; re-dating it out of the cycle dropped its ruled lines from the cap sum AND from `regulatory_surcharge_billing_summary` (the §8.201 report lost the line entirely — Codex). Comparing rule IDENTITY (not "some rule exists") also refuses cycle-to-cycle hops. The into-cycle direction stays with the issuance gate, as before.

**D-2026-08-31-11 · A rule correction cannot shrink its cycle out from under existing non-void lines, and a rule with lines in its cycle cannot be retracted.**
*Why (Codex):* a routine cycle-shortening correction — a legitimate operational act — silently orphaned a billed line: out of the cap sum, out of the compliance view, meter re-billable to the full cap (2.00 on 1.00 reproduced). Retraction had to be fenced too: retract-then-reassert was the route around the successor check. A-1's deferred successor trigger blocks the unlinked-successor and two-hop launderings (probed). Cap-only corrections, extensions, and shrinks that still cover every line stay free; the message directs to void the bills first.

**D-2026-08-31-12 · Line writers hold the governing rule row FOR SHARE to end of transaction; rule corrections and retractions must run under READ COMMITTED (refused otherwise).**
*Why (Fable, the last hole):* the shrink/retraction checks read `invoice_line_items` with no coordination — a correction committing between a line's check and its commit could not see the in-flight line (READ COMMITTED phantom) and orphaned it. An advisory lock was the WRONG tool again (the -07 HIGH-4 lesson: it serialises writers, not snapshots). FOR SHARE on the rule row makes the correction's close-UPDATE wait behind every in-flight checked line; requiring READ COMMITTED on the correction path makes its post-wait statement snapshots see them; a REPEATABLE READ line writer whose rule changed fails at the FOR SHARE with Postgres's own serialization error and retries (the AC-27 contract). No deadlock: line writers share the lock, the per-meter mutex upsert comes after the FOR SHARE (no ABBA), verified in both interleavings. Stated contract: an app running admin writes above READ COMMITTED must special-case rule corrections; a line written before its rule exists is unchecked at INSERT (nothing to lock) and is caught at the deferred issuance gate (verified: pre-rule 50.00 vs a later 1.00 cap).

### Failed approaches (permanent record)
- **Closing one vector at a time and calling the rest "by design"** — the re-parent, the date walk, the shrink, the retraction and the race are ONE family (move the line, the invoice, or the rule so the date-scoped sum no longer sees the pair). Each "as designed" disclaimer fell to the next round's repro. Name the family, then freeze every leg.
- **A disclaimer where a guard fits** — "the issuance gate governs those, as designed" undersold a live 2x-cap route (Codex re-graded it HIGH).
- **`SET TRANSACTION ISOLATION LEVEL` inside a savepoint** (reviewer harness) — Postgres refuses it in a subtransaction; test isolation fences in fresh top-level transactions.

### Outcomes
- tu.sql 20,094 lines (pure append; anchors intact). Catalog after -08: 251 triggers (183 ENABLE ALWAYS) / 384 functions; all other counts unchanged from -07. Fresh build zero errors; battery 173 green on the build; three live races verified.
- GBM: CI-038 text amended (the freeze family + the two stated contracts); Appendix A-7 addendum; ingestion Section AV.
- Next: unchanged — Wave 3 (A-2 first, pending the cluster-27 check).

---

## 2026-08-31 (A-7) — v5.4.2-07: regulatory cost-recovery surcharge riders — the Texas Pipeline Safety Fee

Appendix A-7, CI-038 / CI-045 and Kyle D4-1 (2026-07-10: "PSF is a rate-page line item, no timing enforcement machinery") are the authority; these are the drafting-time calls plus what two reviewers × two rounds (Fable, Codex) changed. Wave 2 closes with this patch.

### Decisions

**D-2026-08-31-01 · No remittance gate and no billing-window check land — D4-1 is read strictly; the structural residue of CI-038 is the cap, the state-agency exemption and the tax-base exclusion.**
*Why:* Appendix A-7 (written 2026-07-03) names a `regulatory_remittances` ledger and a gate; D4-1 (2026-07-10) ruled both out and made "never bill before remitting" operator guidance. Landing a gate anyway would decide by inertia what Kyle decided the other way. `remitted_on` / `remitted_amount` were drafted on the rule and removed: a later fact on a frozen assertion needed either a mutable column outside the audit trail or a correction close for a non-correction. Lives in: the patch header; CI-038's re-grade names the boundary.

**D-2026-08-31-02 · The rider classification is its own in-place bi-temporal table (`regulatory_surcharge_rules`), keyed by (rate item, assessment cycle), not columns on `rate_item_versions`.**
*Why:* the cap and its cycle are per assessment, the classification is per rider, and both need the transaction-time pair; one table in the `franchise_fee_rules` shape carries both without re-versioning every rider on a cycle change. The cycle is a bracket of BILL dates (§8.201 speaks of "the billing cycle or cycles"); the rider's own valid-time bracket still says whether it is on the schedule for a service period. The cap is a configured amount, never a literal in a CHECK: CI-038 says $1.00, D4-1's research note $0.50 — Kyle's to resolve.

**D-2026-08-31-03 · "Per service" = per meter; the cap sums only POSITIVE amounts on non-void invoices, drafts included, serialised on a per-(rider, meter) mutex row.**
*Why:* the fee is per service line; a premise with two gas meters is two service lines, so a capped line without a meter is refused rather than aggregated by location. Drafts count because two concurrent runs would otherwise both pass and both issue. Positives only (Fable HIGH-1, then its round-2 follow-up): any rule that lets a negative line offset lets the discard or void of that line release more than it took — a −5.00 draft let a +6.00 bill issue; the correction path is void + rebill, which releases the voided amount. The mutex row replaces an advisory lock (Fable HIGH-4): an advisory lock serialised the writers but under REPEATABLE READ each summed its own stale snapshot (1.20 on a 1.00 cap); an upsert on a shared row makes the loser fail with a serialization error and retry. Stated gap: a meter change-out mid-cycle resets the cap (candidate Kyle item).

**D-2026-08-31-04 · The state-agency designation is a customer attribute with history (`customers.is_state_agency`, CHECK: government only), evaluated at the END of the billed period from `customer_attribute_history`, day boundary pinned to America/Chicago.**
*Why:* `customer_type = 'government'` is broader (cities, counties, school districts are not exempt); a certificate-style `customer_tax_exemptions` row is the wrong shape (the PSF is not a tax and the exemption is statutory). Evaluating at period end from history answers a correction rebill of an old period (CI-005) and the axes doc's "prospective from the change date"; a period that predates the account's history uses its earliest recorded value; no history raises. Fable MEDIUM-1: a session-TimeZone cast moved the boundary. A zero-amount line on a state agency is allowed (it shows the exemption, CI-046's shape); a charge is refused.

**D-2026-08-31-05 · A-21's event ledgers gain an INSERT fence here (`enforce_event_written_by_db`: refused at `pg_trigger_depth() < 2` inside the guard unless the writer is a superuser), and boolean attributes are CHECKed to 'true' / 'false'.**
*Why (Fable HIGH-3, Codex CRITICAL-2):* `tally_app` held INSERT on `customer_attribute_history` and `customer_state_events` with no fence; a direct `is_state_agency = 'false'` (or 'banana') row cancelled the exemption without touching `customers`, and a direct state event rewrote `customer_status_as_of()`. A-7 is the first patch whose enforcement READS that history, so it closes the hole rather than filing an A-21 rider. Revoking INSERT was not an option: the logger runs with the caller's privileges. With TEMP revoked (D-2026-08-28-37) the depth is structural. Note the convention: inside a BEFORE trigger a direct statement is depth 1, the logger's writes depth 2 — the first draft tested `= 0` and fenced nothing.

**D-2026-08-31-06 · The base composition is a first-class table (`invoice_line_item_bases`), frozen with the invoice; every non-zero tax / percentage line must carry one at issuance; an excluded surcharge line can never be cited; the citing line must still carry a base at issuance.**
*Why:* CI-045 says the per-bill base composition is materialized on the invoice; without it "PSF is excluded from the franchise-fee base" is a promise, not a check. This also makes K4's open question (`franchise_fee_rules.applies_to` vs the per-item `is_taxable` chain) not block CI-038 — whichever the engine uses, the composition is written down and checked. A tax line MAY cite another tax line (tax-on-tax is #23 stage 3 / A-8, unruled). A zero-amount tax / percentage line may have no bases (an empty composition has no rows); a fixed charge may not carry one; a rider re-classified to fixed after its rows were written is refused at issuance (Codex MEDIUM-3). A draft line with a composition cannot be re-parented and a cited line cannot shrink under its base (author's probes); a draft's composition cascades with it.

**D-2026-08-31-07 · The issuance gate judges on CURRENT knowledge — `(invoice_date, now())` for the rules, `(period_end, now())` for the classification — not on the snapshot's coordinate pair.**
*Why (Fable HIGH-2):* A-3 refuses only a future `recorded_at` and does not bind `valid_at`; a `recorded_at` of 2020 hid the rule, a `valid_at` of 2025 hid the rider's calculation type, and both invoices issued. The snapshot is the run's record of what it used; compliance at issue time is a fact about the bill. A-3's unbound `valid_at` is recorded in A-23 (1e).

**D-2026-08-31-08 · A ruled surcharge line's `rate_item_id` is frozen; the reverse taxability direction is enforced at configuration time; one open `pipeline_safety_fee` rule per tenant per bill date.**
*Why:* Codex CRITICAL-1 — `UPDATE … SET rate_item_id = NULL` detached a capped line from every check while it kept the label PSF, and 999.00 issued; reclassifying a line is delete + new line, which re-runs every check. A rider made taxable after its rule exists would be a silent CI-045 drift until the next bill; the rule guard and the version / override guards refuse in both directions. Fable MEDIUM-2a — two PSF riders each capped billed 2.00 on one meter; the fee is one assessment per tenant.

### Failed approaches (permanent record)
- **`pg_trigger_depth() = 0` as an INSERT fence** — inside the trigger the direct statement is already depth 1; the fence admitted everything. Use `< 2` (A-21's convention).
- **An advisory lock as the cap's concurrency guard** — serialises writers, not snapshots; REPEATABLE READ passed a stale sum. A mutex row that the loser must UPDATE is what raises the serialization error.
- **Netting negative lines against the cap** — every variant (drafts positive-only, issued netted) leaks through the discard or void of the negative line's invoice. Positives only.
- **Trusting the snapshot's coordinate in a compliance gate** — it is caller-supplied by A-3's design.
- **`remitted_on` on a bi-temporal rule** — a later fact on a frozen assertion.
- **Editing the patch file while reviewers were testing** — both reviewers reported a moving target; both froze copies and re-verified by hash, but every round-2 request must carry the hash and the file must not change between "launch reviewers" and "collect verdicts".
- **A test harness helper `_f(k text)` reading `WHERE _f.k = k`** — in a SQL function the column shadows the parameter; every fixture resolved to the first row. Prefix parameters.
- **Fixture `INSERT INTO t SELECT … FROM (INSERT … RETURNING)`** — not legal SQL; use a `WITH … AS (INSERT … RETURNING)`.

### Outcomes
- tu.sql 18,822 → 19,779 lines (pure append; anchors 337/3600/3679 intact). Catalog after -07: 82 tables / 250 triggers (182 ENABLE ALWAYS) / 357 CHECKs / 357 FKs / 10 EXCLUDE / 59 UNIQUEs / 81 policies / 80 FORCE RLS / 571 indexes / 383 functions; TEMP still revoked. Fresh build zero errors; battery 161 green on the build (`sql/DEPLOY-VERIFICATION.md`).
- GBM: CI-038 → `partially-structurally-enforced` (cap, exemption, exclusion structural; remittance gate and billing window are operator guidance per D4-1); CI-045 text (base composition materialized and checked; stack contents / stacking order still A-8); Appendix A-7 LANDED; A-23 (1e); parity plan A-7 struck — **Wave 2 complete**; ingestion Section AU.
- Next: Wave 3 (A-2 → A-9 → A-10; A-8 held for a Kyle brief). Before the first bill-run calculation code: CI-003's GUC net (R-16) and A-3's snapshot value contract + `valid_at` binding.

---

## 2026-08-28 (A-21) — v5.4.2-06: account lifecycle state-events, date-effective attributes, deposit / interest ledger

Appendix A-21, CI-121/125/129–131, Kyle 2026-06-12 (effective-dated rate table) and 2026-07-10 (day-30/31 first) are the authority; these are the drafting-time calls, plus what two reviewers × up to four rounds (Fable, Codex) changed. Numbering continues the day's series.

### Decisions

**D-2026-08-28-34 · The account state log is written BY THE DATABASE from `customers.status`, with the reason carried on the row for one statement only: `status_reason` is required on the UPDATE that changes status, consumed into `customer_state_events`, and cleared.**
*Why:* an application-written log can be skipped; a trigger-written one cannot. The first draft left the reason on the row and Fable reused it for the next transition with a bare `SET status` — CI-121's "every transition is a reason-coded event" was satisfied by a leftover. The BEFORE trigger now inserts the event itself and NULLs `status_reason` / `status_changed_by`; a reason on a non-status update is dropped. Only two matrix rules are enforced (closed reopens only to active; closed refused while a deposit is unsettled) — the rest is Kyle's. `clock_timestamp()` + an identity `seq` order events within one instant (Fable M6: 19 of 20 same-transaction trials read the wrong state).

**D-2026-08-28-35 · Date-effective account attributes are a change log (`customer_attribute_history`: attribute, old, new, effective_at), not versioned `customers` rows; a new customer gets its eight initial rows at insert.**
*Why:* the invariant asks "what was the value on date X"; a narrow log answers it without a header/version split on the widest table in the schema. `customer_attribute_as_of()` returns NULL before recorded history, never the current value. Fable M7: without initial rows every new account answered NULL until its first change.

**D-2026-08-28-36 · Deposit status is a projection of events; `customers.deposit_*` are a projection of deposits; the events are the only write path.**
*Why:* decision tables #53–#55 found six representations disagreeing because each was written independently. `deposits.status` / `refunded_on` / `released_on` and the six customer scalars are maintained by triggers and direct writes are refused (`pg_trigger_depth() < 2`). `payments.deposit_status` is reconciled at patch time and CHECKed against `is_deposit`; a `deposit_refund` credit names its deposit (trigger on INSERT / change).

**D-2026-08-28-37 · `pg_trigger_depth()` is a fence only if the application role cannot define a function or a trigger: TEMP is revoked on the database from PUBLIC and `tally_app`.**
*Why (Fable CRITICAL):* with TEMP, `tally_app` created a temp table, a `pg_temp` plpgsql function and a trigger on it, and rewrote `deposits.status` and `customers.deposit_amount` at depth 2 — A-20's counter guard had the same hole. `tally_app` has no CREATE on any schema and no TRIGGER on any table; without TEMP it owns nothing and can define nothing (Fable verified CREATE TEMP/TABLE/FUNCTION/TRIGGER/RULE/EVENT TRIGGER/ALTER … DISABLE TRIGGER all denied; DO blocks run at depth 0). *Not chosen:* a transaction-local GUC sentinel — a caller can `set_config` any GUC, so it is forgeable; the depth fence plus no code-definition privilege is structural. The fence remains a superuser-only convention (A-23).

**D-2026-08-28-38 · Interest is events, never an accumulator, and the ledger recomputes every accrual: period, rate in force (`deposit_interest_rate_as_of`, no fallback), principal in force, amount = `deposit_accrual_amount()`; first period starts ON `posted_on`; periods contiguous, no overlap (exclusion), never across a rate change or a principal application, never on a non-cash instrument.**
*Why:* CI-125/130's failure modes are all "computed at the wrong rate over the wrong span"; refusing the wrong event is the enforcement, detection later is not. The day-31 cliff is two rules — no accrual until the hold exceeds 30 days, no accrual at all on a deposit refunded/exhausted within 30 days — so the cliff is visible in the events (Kyle's first scenario). A backdated rate is refused once any accrual for the tenant has settled through that date (Fable M8: a settled accrual silently became "wrong" with no correction path).

**D-2026-08-28-39 · The accrual horizon is the day before the return OR the day before the principal was exhausted by applications, whichever is first; a fully applied deposit is status `applied` and is settled by a zero-amount `refunded` event.**
*Why (Codex CRITICAL, then HIGH):* "accrue to the return date" could never be satisfied by a deposit consumed by the final bill — nothing was held to accrue on — and the customer could never close (customer-move-out Exc 2 inverted). With the horizon defined on money held, exhaustion ≤ 30 days owes nothing (and refuses any accrual, else the zero refund was blocked forever), exhaustion > 30 days owes interest through the day before exhaustion. CI-131 Alt 2: the obligation is still recorded — hence the zero refund, and `applied` blocks closure until it is.

**D-2026-08-28-40 · The waiver is a recorded determination (`deposit_waiver_determinations`) with its own dates, in its own RLS table; a §7.45-basis deposit is refused while one is in force; a §366 assurance deposit is not.**
*Why:* table #53 — the determination is a point-in-time event, not a re-derivation; a family-violence certification is among the most sensitive data the platform holds and does not go on `customers`. Rank 0 vs rank 5 (federal permission vs state mandate) is the basis distinction on the deposit. No column-level access control exists — flagged.

**D-2026-08-28-41 · The cap is on the record (`cap_amount`, `cap_basis_annual_billing`, `cap_binding`), required for a Texas residential cash §7.45 deposit, with `principal ≤ cap` a CHECK; its derivation is the application's.**
*Why:* CI-129's cap is the most-cited number in the sub-family and its input (estimated annual billing) is undefined for a new applicant (table #53 OQ5) — the database records and enforces what was decided; it cannot compute it.

**D-2026-08-28-42 · Legacy history is carried, never refused: `legacy_unknown` deposits from the scalars (applied / refunded via synthetic `backfill` events written before the sub-ledger guard exists), payments reconciled and the CHECK added VALID, credits linked where one legacy deposit exists; a legacy deposit with no accrual events may be refunded with a recorded reason.**
*Why:* Codex HIGH — the first backfill skipped applied/refunded scalars and the projection guard froze those customers with nothing to post against; Fable H4 — NOT VALID CHECKs still fire on any UPDATE of the offending row, freezing legacy payments and credits. No rate history exists to accrue a legacy deposit against; its interest is the carried `legacy_interest_earned`. **Flagged:** whether legacy deposits should instead require the rate history to be entered and accrued before refund (Kyle/Ryan).

**D-2026-08-28-43 · CI-131's standing obligation is a derivation plus a view (`deposit_refund_trigger_state`, `deposits_refund_due`, security_invoker), not a job.**
*Why:* the schema previously watched only refunds issued and unpaid; the view makes unmade refunds visible (twelve clean bills / ≤ 2 delinquencies / not delinquent, or an inactive-final_billed-closed customer), excludes §366 and legacy deposits, and the definition of "paid clean" is stated as an approximation in the function. Fable C2: the first view was superuser-owned and bypassed RLS.

### Flagged, deliberately not changed

- Only two lifecycle matrix rules are enforced; the full `customers.status` matrix (incl. `final_billed → closed`, customer-move-out OQ2) is for Kyle.
- Legacy refund without accrual (D-42); the credit-vs-disbursement refund path and the `minimum_refund_amount` exclusion (table #54 rule 8) are workflow; residential non-cash instruments accepted and recorded (table #55 rule 2 — decide, do not default); instrument-expiry alerting; a deposit may be posted for a closed customer (Fable L11).
- Grades: CI-130 → `structurally-enforced` (every rule of the Texas accrual/refund discipline is a refusal); CI-121, CI-125, CI-129, CI-131 → `partially-structurally-enforced` (matrix partial; the accrual job and the annual credit cadence are application; cap derivation and waiver eligibility evaluation are application; the refund job is application); CI-077 → `partially-structurally-enforced` (from `unenforced-gap`). Ryan may re-cut.
- A-23 gains the TEMP-revoke fence as a standing assumption; the four pre-existing views in tu.sql should be checked for `security_invoker` (Fable, out of scope).

### Failed approaches (permanent record)

- **`pg_trigger_depth()` as a privilege boundary while the app role has TEMP** — a pg_temp trigger function reaches depth 2 (Fable). Close the route (no TEMP, no CREATE, no TRIGGER), not the symptom; a GUC sentinel is forgeable.
- **A superuser-owned view over RLS tables** — bypasses RLS for every reader; `security_invoker = true`.
- **NOT VALID CHECKs to tolerate legacy rows** — they still fire on UPDATE of those rows; reconcile then add VALID, or enforce with a trigger on INSERT / changed columns.
- **"Accrue to the return date" without an exhaustion horizon** — a deposit consumed by the final bill was unsettleable; and after the first fix, an accrual for the pre-exhaustion days of a deposit exhausted within 30 days blocked the zero refund (append-only ledger: a wrongly admitted event is forever) — refuse it up front.
- **A reason column that lingers on the row** — reused by the next transition; consume it into the event in the BEFORE trigger.
- **`now()` / random-uuid tiebreak for ordering events** — same-transaction transitions read the wrong state; `clock_timestamp()` + identity `seq`.
- **The backfill stamp behind the lifecycle guard** — the guard reset it to OLD (NULL); create the guard after the backfill (the A-21 pattern now used for three triggers).
- **A set-returning function inside CASE/aggregate** — `set-returning functions are not allowed in CASE`; use `CROSS JOIN LATERAL`.
- **`<` vs `<=` on an application's effective day** — the basis must reduce from the application date forward.

### Outcomes

- tu.sql 17,704 → 18,822 (pure append). Catalog: 79 tables / 237 triggers (170 ENABLE ALWAYS) / 344 CHECKs / 345 FKs / 8 EXCLUDE / 78 policies / 77 FORCE RLS / 555 indexes / 56 UNIQUEs; `tally_app` without TEMP. Battery 141 green on scratch and on the fresh build; seeded backfill verified by the author and both reviewers.
- GBM: CI-130 → `structurally-enforced`; CI-121/125/129/131 → `partially-structurally-enforced`; CI-077 → `partially-structurally-enforced`; CI-126 text (deposit lineage); Appendix A-21 LANDED; A-23 (1d) amended; parity plan A-21 struck; ingestion Section AT.
- Next: A-7 (PSF surcharge — Wave 2 closes). Kyle: lifecycle matrix; legacy refund policy; the four deposit-workflow questions above.

---

## 2026-08-28 (A-20) — v5.4.2-05: read/bill exception queue and validation-state substrate

Kyle's D14-1 (`wu5-wu6-kyle-decisions-2026-07-10.md`) and CI-112/113/115/023 are the authority; these are the drafting-time calls, plus what two reviews × two rounds (Fable, Codex) and the author's own passes changed. Numbering continues the day's series.

### Decisions

**D-2026-08-28-25 · The read exception is a row (`read_validation_exceptions`), born open, resolved exactly once with an enumerated CI-112 disposition + free-text reason + resolver + server time, then frozen; never deleted.**
*Why:* CI-112's three resolution paths and "reason code recorded" need a place that outlives the read's status; the row is the lineage CI-088 wants (open once, resolved once). Dispositions are constrained per rule where the corpus narrows them (over-cap: override or field order only — flagged-read-analyst-review Exc 3). The reason code is free text — no catalogue exists; a later patch adds a CHECK. A field order or replacement read named at resolution must belong to the same meter (composite FKs + guard).

**D-2026-08-28-26 · The read gate refuses every step into approved / released_to_billing / locked while an open exception exists, and an exception cannot be raised on a locked / void_released read.**
*Why:* the first draft gated only the first billable entry; Fable raised an exception after approval and walked the read into released/locked, and Codex used the `void_released → released_to_billing` re-lock transition (permitted by the v5.2.1 matrix) to do the same. Every status change into a billable state is now checked. A billed read is corrected by a replacement reading (CI-012), so an exception on it is refused. The exception INSERT takes the reading `FOR SHARE` so it serialises with a concurrent approval.

**D-2026-08-28-27 · The consecutive-estimate streak is DEFINED once and used three times: the validated main-register estimates (`validated_at` set) whose `reading_date` lies after the latest-dated validated actual. The gate maintains it, `consecutive_estimate_state()` derives it, the backfill seeds it.**
*Why:* three successive designs failed under review until membership and order were separated. Status-based membership double-counted the rework loop (approved → pending → approved) and dropped excluded reads (Fable, Codex); validation-order (`validated_at DESC`) fixed those but let a back-dated actual validated later clear estimates dated after it — Codex ran five estimates past a cap of 3 that way. Membership is decided by validation (a read excluded after validation stays counted, a re-approval is not a new event); order is decided by reading date (a back-dated actual does not clear later-dated estimates; a same-day estimate beside an actual is not counted). **This refines D14-1b** ("resets only on a validated actual read") to "…dated at or after the streak" — the ruling did not consider out-of-order validation; flagged for Kyle, with the engineering reasoning that the customer is still being estimated for the later periods.

**D-2026-08-28-28 · `meter_readings.validated_at` is repurposed as the validation event: server-stamped (`clock_timestamp()`, so events in one transaction stay ordered) on the read's first entry into a billable state, caller values replaced, frozen; with it, `is_estimated` / `register_type` / `meter_id` / `reading_date` / `tenant_id` freeze.**
*Why:* the counter needs a once-only event that survives status churn; the existing column had no writer in tu.sql. The v5.2.1 whitelist froze the read's facts only at `locked`; between approval and lock a flipped `is_estimated` desynced the counter (author's pass). Backfill stamps historical billable reads from `locked_at`/`created_at` (approximation, reported) and clears stray values on non-billable reads (Fable round 2). A read excluded before the patch cannot be told from one never validated and is not counted — stated in the header.

**D-2026-08-28-29 · The counter is STORED on `meters`, written only from inside the read gate (`pg_trigger_depth() < 2` rejects direct writes), and must equal `consecutive_estimate_state()` — the battery and both reviewers assert it after every transition.**
*Why:* the cap check at approval must not scan history; the derivation keeps the stored value auditable. `pg_trigger_depth` is a structural fence with nothing for a caller to arm (no GUC); both reviewers confirmed no other trigger path in tu.sql writes those columns and `tally_app` cannot create triggers.

**D-2026-08-28-30 · The database raises the over-cap exception itself (AFTER INSERT of a pre-approval estimate that would reach the cap, counting the stored streak plus estimates already pending and dated after the last actual); the approval gate re-checks independently.**
*Why:* CI-113 says the cap is enforced; an exception the application forgot to raise is no enforcement. Estimates pending together (Fable L2) and a cap lowered after insert are covered by the re-check: approval at the cap needs a resolved over-cap exception on that read — raised by the database or, for pre-patch pending estimates, by an operator.

**D-2026-08-28-31 · `invoice_exceptions` stores decision table #35's routing outputs on the row (`queue`, `blocks_delivery`, `sla_days`, `escalation_target`, `routing_reason`); `blocks_delivery` and `routing_reason` freeze at insert; the gate refuses the transition, it does not auto-hold.**
*Why:* the queue is the table; a role model does not exist (rbac-model pending), so `queue` is an enum string. Clearing `blocks_delivery` would be an override without a reason — an override is a status with a reason code. A trigger rewriting `invoices.status` to `held` from inside an exception insert would fight A-4 (pending → held is backward) and hide the operator action CI-115 records; the gate (no pending / sent / `sent_at` / `delivery_confirmed_at` with an open blocking row) is what makes the hold non-optional.

**D-2026-08-28-32 · Tenant binding: composite FKs where a `(id, tenant_id)` key exists (new UNIQUEs on `meters`, `meter_readings`, `service_orders`); the plain FKs to `users` and `anomalies` are checked by the guards (`assert_same_tenant_user()`, platform admins excepted).**
*Why (Codex round 1):* FK checks bypass RLS, so a T1 operator could stamp a T2 user as `resolved_by` — lineage attribution outside the tenant. Adding `(id, tenant_id)` to `users` was not taken: `users` is the RLS root and platform admins legitimately act across tenants.

**D-2026-08-28-33 · CI-023's completeness gate is a function plus a refusal at `billing_run_meters`, not NOT NULL columns.**
*Why:* the attributes stay nullable by the v5.4.0-02 ruling (NULL = unaffirmed pending the activation gate); the invariant's clause is "billing against an incomplete master is rejected; the meter enters an exception queue" — enforced exactly there, with the reasons named. `temperature_compensated` still does not exist (unruled) and is not checked.

### Flagged, deliberately not changed

- **D14-1b refinement (D-27)** — a back-dated actual does not clear a later-dated streak; and should it raise a review exception of its own (Codex suggestion)? For Kyle.
- Tenant cap above the Texas 6-month ceiling is not bounded (decision table #4 open question) — for Kyle.
- Grades: CI-112 and CI-115 stay `partially-structurally-enforced` (detection — which rule failed, which criterion fired — is application code; the queue discipline is structural); CI-113 → `structurally-enforced` with the cap value configurable; CI-023 → `partially-structurally-enforced` (gate structural; attributes nullable; `temperature_compensated` absent). Ryan may re-cut.
- `anomalies.entity_type` has no CHECK (table #35 open question 2) — factual-defect set candidate; queue/role substrate and SLA escalation processing wait for rbac-model.
- The auto-raise does not fire for row 2 of table #4 (cap − 1 → "require an actual-read attempt") — a dispatch decision for the read-cycle workflow.

### Failed approaches (permanent record)

- **Counting the streak by status transitions** (double-counted rework; dropped excluded reads), then **by validation order** (a back-dated actual cleared later-dated estimates and let estimates run past the cap). The definition that held: validation decides membership, reading date decides order.
- **`ALTER TABLE … DISABLE/ENABLE TRIGGER USER` around a backfill UPDATE** — the ENABLE fails on the deferred FK's queued events; and without the toggle the v5.2.1 meters triggers broke under the strict prelude — a transaction-local `set_config('search_path', 'public, pg_temp', true)` inside the DO block is the answer.
- **`now()` for an ordering stamp** — identical inside one transaction; `clock_timestamp()`.
- **`length(btrim(col)) > 0` as a NOT-NULL check** — NULL passes a CHECK; pair with `col IS NOT NULL`.
- **An expected-error battery chunk that contains its own setup** — the subtransaction rolls the setup back; split setup from the assertion.
- **A NOTICE query that calls the raising cap function** — a misconfigured tenant made the patch refuse; report with a non-raising expression.

### Outcomes

- tu.sql 16,811 → 17,704 (pure append). Catalog: 73 tables / 213 triggers (146 ENABLE ALWAYS) / 316 CHECKs / 324 FKs / 7 EXCLUDE / 72 policies / 71 FORCE RLS / 531 indexes / 50 UNIQUEs. Battery 154 green on scratch and on the fresh build; seeded backfill verified by the author and both reviewers.
- GBM: CI-113 → `structurally-enforced`; CI-023 → `partially-structurally-enforced`; CI-112/115 text updated (tokens unchanged); Appendix A-20 LANDED; parity plan A-20 struck; decision table #4 annotated with the D14-1b refinement; ingestion Section AS.
- Next: A-21, A-7 (Wave 2). Kyle: D14-1b refinement + Texas ceiling bound.

---

## 2026-08-28 (A-3) — v5.4.2-04: invoice calculation snapshots, Option B

The locked decision (`bi-temporal-decision.md` §5: Option B) and CI-015's input list are the authority; these are the drafting-time calls, plus what the two pre-mirror reviews (Fable, Codex) and the author's second pass changed. Numbering continues the same day's A-1 series.

### Decisions

**D-2026-08-28-16 · Completeness is a commit-time gate on `invoices`, not a NOT NULL column: a DEFERRABLE INITIALLY DEFERRED constraint trigger requires exactly one snapshot, still agreeing with the invoice (period, billing run, customer, line id set + amounts), whenever an invoice moves into an issued status.**
*Why:* the snapshot is a child row (it cites the lines, which must exist first), so it cannot be a column on the invoice; the deferred trigger lets one transaction write invoice → lines → snapshot → status flip and still refuse at commit if any piece is missing or stale. Draft/held → `void` is exempt (Fable HIGH-1: `void_invoice()` lists held as voidable and nobody was billed; void is terminal under A-4, so the exemption cannot chain into an unsnapshotted issuance). *Not chosen:* gating on `invoice_type` (consolidated parents, duplicates, credit memos) — a carve-out makes "issued without a snapshot" legal again; the validator accepts empty-but-keyed sections instead. Flagged for Ryan if it proves heavy.

**D-2026-08-28-17 · Schema versioning is enforced, not labelled: `validate_calculation_snapshot()` enumerates the accepted versions (`v1`) and their required keys, nested shapes included; an unknown version or a missing key is rejected with the key named.**
*Why:* Option B's stated advantage over a JSONB column was that "schema version is explicit". A free-text version column is a label; a validator that knows the contract is the enforcement. Values are checked for presence and JSON type only — their correctness is the calculation code's contract (R-16's trigger: revisit when that code exists). `v1` is CI-015's list as of today, split into eight sections so each domain can evolve on its own key.

**D-2026-08-28-18 · The run's temporal coordinate pair lives on the snapshot (`valid_at`, `recorded_at`), not on `billing_runs`.**
*Why:* AC-15 says a run resolves ONE pair and passes it everywhere; the snapshot is the record of which pair this bill used, and an off-run invoice (`billing_run_id NULL`) still has one. `recorded_at` may not be in the future; `captured_at` is the server's clock. `billing_run_id` is copied for the join and checked equal to the invoice's.

**D-2026-08-28-19 · `line_items` is stored twice on purpose and cross-checked (id set and amounts) at insert AND at issuance; amounts must be JSON numbers and compare unrounded.**
*Why:* CI-016 keeps the values on the line for the dollar calculation; CI-015 wants replay to read one document. If the two disagree the bill is not self-replayable, so agreement is enforced both when the snapshot is written and when the invoice commits as issued (a line edited in between invalidates the snapshot: delete + re-snapshot). Fable MEDIUM-1: the first draft cast to `numeric(12,2)` before comparing, so `20.004` matched a `20.00` line and `"10"` (a string) matched `10` — replay would have read a document that disagreed with the billed line.

**D-2026-08-28-20 · Immutability: UPDATE never; INSERT and DELETE only while the parent invoice is draft/held; a snapshot cannot be written for an already-issued invoice; `content_hash` is GENERATED.**
*Why:* there is no legitimate in-place edit of a frozen input set — a draft is re-snapshotted by delete + insert, which leaves no half-edited row. A snapshot inserted after issuance would be a reconstruction from today's reference layer, which is exactly what CI-015 forbids passing off as the original; invoices issued before this patch therefore have no snapshot and never will (the patch reports their count). `content_hash` (sha256 over versions + coordinate + all sections, pgcrypto `digest` so the expression is IMMUTABLE — `convert_to` and `timestamptz::text` are STABLE and were rejected) gives INV-099's content-addressable framing with nothing for a caller to write wrong.

**D-2026-08-28-21 · Provenance is a separate table (`invoice_snapshot_references`) validated for transaction-time visibility: the cited row must exist in one of the seven A-1 tables, in the snapshot's tenant, and be open at the snapshot's `recorded_at`.**
*Why:* "which rows did this bill read, and were they really what we knew then" is a question the JSON sections cannot answer structurally (seven tables, no polymorphic FK). The guard proves the citation was visible at the coordinate the run passed — a draft (`recorded_at IS NULL`) or a row closed before the coordinate is not citable. Valid-time containment is deliberately not checked (bracket columns differ per table; R-9's fallback legitimately reads outside a bracket). Optional per snapshot (a credit memo reads no reference data). *Not chosen:* validating version ids inside the JSON — fragile, and it re-implements the FK by hand.

**D-2026-08-28-22 · Functions are pinned `SET search_path = public, pg_temp` (the `void_invoice` / A-1 precedent), every reference still qualified — not `''`.**
*Why (Fable CRITICAL-1, Codex CRITICAL):* under `''`, the first RLS policy evaluation inside a guard calls the v5.2.1 helpers `get_user_tenant_id()` / `is_platform_admin()`, whose SQL bodies name `users` unqualified and inherit the caller's empty path — `tally_app` could not write a snapshot, add a citation or issue an invoice at all; only the superuser (which bypasses RLS) could, which is why the author's battery missed it. The durable fix — qualify and pin those helpers — is A-23's item, not this patch's. **Rule for future patches:** a trigger function that touches an RLS-protected table must not pin `''` until A-23 lands; the strict-apply prelude proves qualification, the `public, pg_temp` pin is what runs.

**D-2026-08-28-23 · Concurrency: the snapshot/reference guards read the parent invoice `FOR SHARE`; the deferred check locks the invoice's lines `FOR SHARE` and deliberately does NOT lock the snapshot row.**
*Why (Fable CRITICAL-2):* with plain reads, "issue" in one session and "delete the snapshot" / "edit a line" / "add a citation" in another both committed — an issued invoice with no snapshot. `FOR SHARE` on the invoice makes the guard wait behind an in-flight status flip and re-read the committed status; the line lock covers A-4's line guard, which reads the invoice without locking. Locking the snapshot row in the deferred check was tried and dropped: it deadlocked against a waiting delete (a BEFORE DELETE trigger already holds the tuple) and `FOR UPDATE` needs the UPDATE privilege `tally_app` deliberately lacks. Verified live by the author and both reviewers, both orderings.

**D-2026-08-28-24 · The two new FKs cascade on delete (`snapshot → invoices`, `references → snapshot`).**
*Why:* A-1 stripped cascades because a header delete destroyed history; here the only deletable parent is a draft (A-4), whose snapshot is deletable anyway — without the cascade a legitimate draft delete was blocked (author's second pass). No issued invoice can be deleted in any mode, so the cascade can never reach a frozen snapshot (Codex round 2 traced `tenants` and `billing_runs` too — both stop at their own CI-014 guards). Known edge: FK cascades are internal triggers and do not run under `session_replication_role = replica`, so a replica-mode draft delete leaves an orphan (Fable C3, LOW, accepted and noted in the header).

### Flagged, deliberately not changed

- **CI-015's grade is `structurally-enforced` with a stated boundary** (existence, shape, immutability and line agreement are structural; whether a section's values are the ones the calculation actually used is the calculation code's contract; pre-patch issued invoices have no snapshot; no replay function exists because no formula exists). Ryan may prefer `partially-structurally-enforced` — the boundary text is written so either token reads true.
- Every invoice type is gated, including consolidated parents, duplicates and credit memos (D-16).
- `enforce_invoice_has_snapshot` queues a deferred event on every `invoices` INSERT/UPDATE (it returns early for non-issuing rows) — a cost, not a correctness issue; note that `ALTER TABLE invoices` inside a transaction with pending events fails until they are flushed.
- The three unpinned SECURITY DEFINER helpers (A-23) are now a known trap for any strict-pinned trigger function (D-22).

### Failed approaches (permanent record)

- **`SET search_path = ''` on trigger functions that read RLS tables** — see D-22. The strict-apply prelude proved qualification and hid the runtime failure because the superuser bypasses RLS.
- **Locking the snapshot row `FOR UPDATE` in the deferred check** — deadlock + privilege (D-23).
- **A GENERATED column over `convert_to()` / `date::text` / `timestamptz::text`** — all STABLE; `public.digest(text, 'sha256')`, `(valid_at - DATE '1970-01-01')` and `extract(epoch from recorded_at AT TIME ZONE 'UTC')` are IMMUTABLE.
- **`text[] || 'literal'`** — the untyped literal resolves as an array literal and `malformed array literal` fires on the first message containing parentheses; use `array_append(arr, (…)::text)`.
- **A BEFORE INSERT guard that assumes the CHECK constraint ran first** — it did not; the dynamic `format('%I')` query hit `invoices` before the `source_table` CHECK could reject it (re-checked in the trigger).
- **Mirroring from the second `-- ====` line** (again — the header has three; the body starts after the last). Caught before the build; tu.sql reverted and redone.
- **Battery run standalone** — `SET LOCAL ROLE tally_app` needs one transaction (`psql -1` or a BEGIN wrapper); a standalone run silently tests as superuser.

### Outcomes

- tu.sql 16,245 → 16,811 (pure append; anchors intact). Catalog: 71 tables / 201 triggers (134 ENABLE ALWAYS) / 294 CHECKs / 308 FKs / 7 EXCLUDE / 70 policies / 69 FORCE RLS / 517 indexes / 46 UNIQUEs. Battery 90 green on scratch and on the fresh build; four races verified by three parties.
- GBM: CI-015 → `structurally-enforced` (boundary stated); Appendix A-3 LANDED; parity plan A-3 struck (Wave 1 complete); bi-temporal-decision §2.3 annotated; ingestion Section AR.
- Next: Wave 2 (A-20 → A-21, A-7). Before any bill-run calculation code: CI-003's GUC net (R-16) and the snapshot value contract (D-17).

---

## 2026-08-28 (A-1) — v5.4.2-03: the bi-temporal transaction-time substrate

Kyle's rulings R-9 … R-18 (`gas-billing-memory/application/kyle-decisions-2026-08-26-a1-bitemporal.md`) are the authority; these are the drafting-time calls made inside them, plus what the two pre-mirror reviews (Fable, Codex) changed.

### Decisions

**D-2026-08-28-01 · `change_type` is the inserted row's event — `initial | succession | correction | backfill`; retraction is not a value.**
*Why:* the design (§4.8) listed `retraction` in the insert enum, but a retraction is a close with no successor — no inserted row can legitimately carry it. It lives on the closing side as `closed_type = 'retracted'`, paired with `closed_reason`/`closed_by`. `backfill` exists only for the migration rows and is rejected on any live insert (see D-03).

**D-2026-08-28-02 · Lineage points backwards (`supersedes_id` on the successor), the close happens first, and "superseded" is verified at commit — per entity.**
*Why:* a successor cannot be inserted while its predecessor is open (the open-rows exclusion constraint forbids two open assertions over one valid point), and a closed row is frozen, so the pointer can only live on the successor. `closed_type = 'superseded'` therefore names a row that does not exist yet; a DEFERRABLE INITIALLY DEFERRED constraint trigger checks at commit that an **asserted** successor **of the same entity** exists — Codex reproduced a cross-entity satisfaction (close zone A as superseded, point zone B's new row at it; A silently loses its current assertion under a label claiming continuity) and Fable a draft satisfying it; both closed. The predecessor check on insert (`assert_bitemporal_predecessor()`) is generic: same entity-key columns (trigger argument), same tenant, closed, and closed *as superseded* — a retracted row cannot gain a successor.

**D-2026-08-28-03 · Transaction time is the database's. `recorded_at` is forced to `now()` on every insert and on every draft → asserted transition; `recorded_until` is forced to `now()` on the close; `backfill` rows cannot be inserted after the patch.**
*Why:* the first draft only rejected a future `recorded_at` and accepted any `recorded_until` in `[recorded_at, now()]`. Both reviewers showed the axis was forgeable — a 2010-dated "correction" inserted in 2026, an erasure by `recorded_until = recorded_at`, a born-closed `backfill` row planted at a chosen historical coordinate. CI-001's rationale (subpoena defence, "what did we know then") rests on this axis being tamper-evident. A row asserted and closed in the same transaction is zero-width — nobody could have seen it — and is tolerated as equivalent to never asserting. *Not chosen:* raising on same-transaction closes; it broke ordinary multi-step work and protected nothing.

**D-2026-08-28-04 · Every content change to an asserted row — including valid-time closings like revocation and expiry — is insert-and-close, never an in-place edit. The per-table in-place set is only lifecycle (`wna_monthly_adjustments.status` forward), `notes`, `metadata`, `updated_at`.**
*Why:* Kyle's "closings of the record, not in-place edits" (R-12) read strictly. An in-place `effective_end` would make "what did we believe on date X about when this ended" wrong — exactly the reproduction failure the substrate exists to prevent. A revoked exemption is a new row (`status = 'revoked'`, `effective_end`, `revoked_*`) superseding the active one; `customer_tax_exemption_as_of()` still finds the exemption for dates inside the bracket, which is why revocation-as-succession is semantically right. Fable's H2 (a revoked row inserted *beside* the still-open active row kept the customer exempt) led to the exclusion constraint on `(customer_id, exemption_type, bracket)` over asserted open rows.

**D-2026-08-28-05 · Group-1 version rows have no draft phase; the draft is the `rate_schedules` header, which is born `draft` (DEFAULT flipped from `active`).**
*Why:* R-14 put the draft concept on the header. A version row needs its header to exist first and activation requires an open version, so a header inserted `active` could never satisfy the rule; `INSERT` must be `draft`. Versions of a draft schedule are asserted immediately — editing a draft's content leaves history. That is the cost of one write path, and it is honest (Fable L3).

**D-2026-08-28-06 · Lifecycle status lives on the headers; `expired` is not a header state; archiving reconciles with the versions.**
*Why (R-14 rider 3):* three columns could say "not current". Resolution: transaction-time death is `recorded_until` only; valid-time death is `expiry_date`/`effective_end` only; `status` values that duplicated either were removed (`expired` from `rate_schedules`, `superseded` from `franchise_fee_rules`) or constrained (`archived` on the in-place tables requires an `expiry_date`). Fable's M1 extended this to the headers: archiving requires every open version to carry an `expiry_date`, an archived entity accepts no new versions, and an archived schedule is not assignable (the ruling said `draft`; `archived` follows by the same logic and is flagged as beyond the ruling). `archive_reason` is an enum required exactly when archived; `activated_at`/`archived_at` are stamped by the trigger, not supplied.

**D-2026-08-28-07 · `rate_item_history` is migrated bracket-by-bracket into `rate_item_versions`, then retired read-only; `archive_rate_item_history()` is a RAISE stub.**
*Why:* history rows are genuine `rate_value`/`rate_unit` history; every other column is copied from the live row and flagged as an approximation in `change_reason`. Three cases: no history → one live-row version; history with an open-ended bracket → the brackets only; history all closed → the brackets plus a live-row version from `max(end_date) + 1`. The exclusion constraint validates the migration — an overlapping legacy bracket fails the patch loudly rather than being reconciled by guesswork. Retiring rather than dropping keeps the migration source; the archive function is a stub so a scheduled caller fails loudly (both reviews of the design: a live DELETE path beside the table declared permanent is a defect from the moment the patch lands).

**D-2026-08-28-08 · Lookups are STABLE, invoker-rights, `RETURNS SETOF <row type>`; `should_charge_tax()` drops SECURITY DEFINER; `get_correction_rate_date()` is pinned by `ALTER FUNCTION … SET search_path` without re-issuing its body.**
*Why:* invoker rights make RLS apply to the lookups — Fable showed the definer `should_charge_tax` answered for any customer regardless of the caller's tenant. Zero rows means "unknowable at that coordinate" (D-2026-08-20-09: never a default). The pin on `get_correction_rate_date` is safe with an unqualified v5.2.1 body under `public, pg_temp` (D-2026-08-20-25's reasoning); the remaining three unpinned definer helpers (`get_user_tenant_id`, `is_platform_admin`, `validate_custom_fields`) stay for A-23.

**D-2026-08-28-09 · R-17's "review queue" is an `anomalies` row (`anomaly_type = 'reference_correction_review'`).**
*Why:* no generic review-queue table exists; `anomalies` is the operator work queue (`status`, `assigned_to`, `resolved_*`, `dedup_key`, RLS, in the A-4 protected set) and `rule_based` is a documented detection method. Invoices are counted through `invoice_line_items.rate_schedule_id` (the only invoice-side FK to a schedule). One correction over N open brackets produces N rows (flagged, not changed — each names its own version pair).

**D-2026-08-28-10 · R-9's reference is every open version, or — when none is open — the most recently closed one; `initial` is allowed only while the schedule has no versions.**
*Why:* Fable's H4 re-tagged a schedule by retracting the open version and inserting a fresh `initial` (or a `succession` with no `supersedes_id`), bypassing R-17's basis-and-review path. With the latest closed version as the reference, the only way to change `service_type` is the correction path — `supersedes_id` + `service_type_change_basis`, over the predecessor's exact valid bracket (H3: the first draft accepted a shifted bracket, i.e. a valid-time-dated service change dressed as a correction).

**D-2026-08-28-11 · Version rows carry a composite FK `(entity_id, tenant_id)` to their header.**
*Why:* the plain FK let a tenant-2 version row hang off a tenant-1 schedule (Fable M2). The headers gain `UNIQUE (id, tenant_id)` for it.

**D-2026-08-28-12 · Open-row uniqueness on the two lifecycle tables is scoped to asserted rows; drafts may sit beside the live assertion.**
*Why:* with drafts counted as open, a WNA restatement had to close the approved row before a draft could even be entered, and a draft could then satisfy the successor check (Fable H6). Now a pending restatement can be prepared beside the live month; approving it while the live row is open fails on the unique index, forcing close-first; the successor check ignores drafts.

**D-2026-08-28-13 · No `app.*` GUC carve-out anywhere in the patch.**
*Why:* design §4.8 suggested reusing `app.void_operation`'s shape for the close transition. The close is instead a row shape the guard recognises (content byte-identical, closing columns set), so there is nothing for a caller to arm and nothing to leak (the A-4 lesson).

**D-2026-08-28-14 · The self-verifying precondition set (R-13 pattern): `industrial` exemptions, unverified asserted exemptions, unapproved non-pending WNA rows, `superseded` franchise rows, archived rows without an expiry, `expired`/`archived` schedules.**
*Why:* each is a row the new constraints cannot accept and whose mapping only an operator can make; the patch refuses and reports the count rather than inventing values (Kyle: "removes a blocking question rather than adding one"). A fresh deploy has none.

**D-2026-08-28-15 · `application/DECISION-LOG.md` exists here, not in gas-billing-memory.** Kyle's record noted the brief promised a file "nobody maintains" — it looked in the wrong repo. The brief's closing note is corrected; the convention stands: rulings in GBM `kyle-decisions-*`, drafting calls here.

### Flagged, deliberately not changed

- A raw `UPDATE … SET version = version + 1` is accepted (the header trigger enforces monotone +1, not the caller); `assert_reference_version()` is the sanctioned path (AC-14). Distinguishing them needs the option-(a) SECURITY-DEFINER seal — still Ryan's call.
- `get_user_tenant_id`, `is_platform_admin`, `validate_custom_fields` remain unpinned SECURITY DEFINER (A-23 list, down from six to three).
- One `service_type` correction over N open brackets → N `anomalies` rows.
- Versions of a draft schedule are asserted immediately (D-05).
- `jurisdictions.wna_zone_id`/`wna_applicable` and `meters`/`meter_deployments.rate_schedule_id` assignment history (A-19) remain uni-temporal — this patch is their template.
- CI-003: revisit **before the first bill-run calculation code lands** (R-16), not after A-3; the explicit-parameter lookups are the layer a GUC-defaulted variant sits over.
- R-18 (sewer-to-water linkage: three enforcement gaps) → v5.5.

### Failed approaches (permanent record)

- **A Python wrapper that matched an INSERT by its header text** nested one DO block inside another because the third INSERT shared the first's header — the patch failed with a syntax error two statements later. Regenerate a region by its section markers, not by statement text.
- **Trusting a `SELECT 1` readiness probe on a freshly-run container** — Docker's init runs on a temporary server that accepts connections; the seed ran against a half-built schema and the strict apply died with "database system is shutting down". Wait for `PostgreSQL init process complete` in the logs (memory: `tally-pg-readiness-wait`).
- **`format('… %: …')`** — `%:` is not a specifier; two error messages raised "unrecognized format() type specifier" instead of the rule. `%s:`.
- **psql `:var` substitution inside `$$ … $$`** does not happen; 73 battery checks ran with a literal `:rs1`. Inline the literals.
- **`SET CONSTRAINTS ALL IMMEDIATE` is sticky for the rest of the transaction** — later close-then-insert steps fired the successor check at the close. Pair it with `SET CONSTRAINTS ALL DEFERRED`.
- **`UPDATE … RETURNING` inside a subquery** is not SQL; run the statement, then assert.
- **Rejecting a same-transaction close as "zero-width erasure"** — correct in spirit, but it blocks legitimate multi-step work inside one transaction and protects nothing once both stamps are server-set (D-03).
- **Comparing a uuid column to `jsonb ->> key` without a cast** in the dynamic successor check — `uuid = text`. Cast the column to text.
- **Dropping a UNIQUE before the FK that depends on it** on re-apply — drop the FK first.

### Outcomes

- Strict standalone apply (`search_path = ''`, `check_function_bodies = on`) clean; re-applied three further times on the same database (including after committed post-patch rows) with zero errors. The R-13 precondition refuses a seeded `industrial` row. Battery: 164 checks green on a fresh container seeded with pre-patch data (backfill of all three `rate_item_history` cases verified).
- Two pre-mirror reviews (Fable, Codex): Codex 1 CRITICAL + 1 MEDIUM, Fable 2 CRITICAL + 7 HIGH + 5 MEDIUM + 5 LOW — every CRITICAL/HIGH/MEDIUM fixed (D-02, -03, -04, -06, -08, -10, -11, -12), LOWs recorded above. Round-2 verdicts and the mirror are recorded in `sql/DEPLOY-VERIFICATION.md`.

---

## 2026-08-20 (A-4 follow-up) — v5.4.2-02 after two post-landing assessments

### Decisions

**D-2026-08-20-24 · Every patch must apply under `SET search_path = ''; SET check_function_bodies = on;` — the Docker preamble is no longer the deploy test.**
*Why:* -01's header claimed "every object schema-qualified" and the verification doc recorded "search_path = '' clean"; both were false for the re-issued `void_invoice()` (eleven unqualified refs inherited from v5.4.1-01). The fresh build, and every reviewer's fresh-load, went through `postgres/00_preamble.sql`, whose `check_function_bodies = off` masked it. The strict prelude is now part of the method and is recorded per patch in DEPLOY-VERIFICATION. The -01 patch file's false sentence is left as the historical record; the correction lives in -02's header and in DEPLOY-VERIFICATION.

**D-2026-08-20-25 · `void_invoice()` is pinned to `search_path = public, pg_temp`, not `''`.**
*Why:* `''` was tried first and broke at runtime — `get_user_tenant_id()`, `is_platform_admin()` and the event/ledger triggers are unqualified v5.2.1 bodies that inherit the caller's path. Pinning to `public` closes the definer-hijack vector (Fable reproduced a cross-tenant void against the -01 body with `evil.is_platform_admin()`) without re-issuing half of tu.sql. Six other SECURITY DEFINER functions (`get_correction_rate_date`, `get_effective_rate`, `get_user_tenant_id`, `is_platform_admin`, `should_charge_tax`, `validate_custom_fields`) still have no pin — flagged below.

**D-2026-08-20-26 · Writing `status = 'void'` is gated on the carve-out, from any prior status and on INSERT.**
*Why:* the assessment showed a bare `UPDATE … SET status='void', voided_at=now()` voided a sent bill with no reversal, reads still locked, charges still billed — then sealed it. Review of the first -02 draft found the gate sat below the draft/held early-return (held is voidable by `void_invoice()`, so held→void direct was the worst case) and missed INSERT; both fixed. The GUC is caller-settable (AC-12), so this is a fence against accident, not intent — same grade as the read and charge guards; a one-column slip is now a deliberate, greppable act. Alternative rejected: forcing `void_invoice()` by revoking UPDATE on `status` — that is the option-(a) SECURITY-DEFINER seal, still Ryan's call.

**D-2026-08-20-27 · All immutability guards are `ENABLE ALWAYS`, including the three that predate A-4.**
*Why:* 68 of -01's 77 guards were skippable under `session_replication_role = replica`; scoping the fix to "-01's guards" would have left `pga_monthly_reconciliations` and `tenant_configuration_history` as the odd ones out (both reviewers flagged it). Superuser/replication-apply only, but an audit guard that replication can drop is not an audit guard.

### Flagged, deliberately not changed

- Six SECURITY DEFINER functions without a pinned `search_path` (list in D-25) — factual-defect set candidate; the two tenant helpers are the ones a hijack would target.
- Everything from the -01 list (void⇔voided_at CHECK, issued-status ordering, voided balance freeze, `meter_readings` until A-1) and the assessors' judgment calls for Ryan: `pending` = issued, `due_date` frozen, clean drafts deletable / held never, `write_off`/`paid` non-terminal, `payments.status` default `posted`, whether to take the SECURITY-DEFINER seal.

### Failed approaches (permanent record)

- **`SET search_path = ''` on a definer function whose helpers are unqualified** — compiles (body is qualified), fails on first call inside the helper. Pin to `public, pg_temp` until the helpers are qualified.
- **Fresh-loading through the Docker image as proof of `search_path = ''` safety** — the preamble turns body checking off; only a strict prelude on the patch file proves it.
- **Writing "corrected in place" in a header before the doc step ran** — Codex's reviewer diffed the doc and called it. Header claims about other files are checked at review; write them after the edit, not before.

### Outcomes

- tu.sql 14,030 → 14,499 (pure append; anchors intact). Triggers 147 (80 ENABLE ALWAYS); `void_invoice()` `proconfig = search_path=public, pg_temp`; `enforce_invoice_immutable` fires on INSERT too. Fresh build zero errors; 89-check battery green on the fresh build; strict standalone apply clean ×3.
- Reviews: Fable (1 MEDIUM gate placement — fixed; 4 LOW), Codex (1 HIGH header-vs-doc ordering — fixed by doing the doc; 1 MEDIUM pre-existing guards — folded in; 1 LOW count). Fable's assessor and Codex's assessor both verdict "sound enough to build A-1 on" before this patch; it closes their MEDIUMs.
- GBM: A-23 amended (direct-void gap closed; SECURITY DEFINER pin list added); CI-012 text notes the gate; ingestion Section AO; no token changes.

---

## 2026-08-20 (later) — Phase 4 Wave 1, A-4 landed (v5.4.2-01)

### Decisions

**D-2026-08-20-16 · "Issued" = `status NOT IN ('draft','held')`; `pending` is on the immutable side.**
*Why:* the status COMMENT gives draft → pending → sent with held as a pre-posting detour; `void_invoice()` already lists pending as voidable (i.e. posted, corrected only by void + rebill). CI-012's "customer-visible" phrase is satisfied by "the ledger has seen it." → `is_invoice_issued(text)`, the single definition every CI-012 guard calls.

**D-2026-08-20-17 · Invoice immutability is column-scoped, not row-scoped.**
*Why:* an issued bill keeps living in collections (payments apply, dunning runs, late fees are assessed, delivery is confirmed, the void stamp lands). Freezing the row would break the shipped design; freezing nothing was the defect. The frozen set is "what the customer saw" (identity, lineage, period, dates incl. `due_date`, totals, `tax_breakdown`, estimated-read/anomaly flags, `pdf_url` once set, `id`). `late_fee_*` deliberately NOT frozen. → `enforce_invoice_immutable()`.

**D-2026-08-20-18 · Draft invoices may be hard-deleted — but only clean ones.**
*Why:* a draft is not posted, not voidable (`void_invoice()` rejects draft) and has no soft-delete path, so forbidding DELETE would leave an abandoned draft with no disposition. Review found `fk_adhoc_invoice` is ON DELETE SET NULL, so a draft carrying a billed charge would strand it as billed-on-nothing; the exception now requires no billed charge and no locked read. Line-item and event guards let the draft's cascade through by detecting "parent gone", which the FK makes unreachable otherwise. Held is not deletable (it carries an operator's reason and is voidable).

**D-2026-08-20-19 · `account_ledger` and `invoice_events` are INSERT-only with no exceptions; the other CI-013 tables freeze identity and seal terminal states but keep lifecycle columns writable.**
*Why:* nothing shipped updates either of the first two. `payments`/`invoice_applications`/`customer_credits`/`adhoc_charges` are modelled with mutable `applied_amount`/`remaining_amount`/`reversed_at`/`status`; making them append-only is a redesign (A-21), not an enforcement patch. Hence CI-013 is graded structural for the ledger + events, partial for the rest — stated, not blurred.

**D-2026-08-20-20 · The `app.void_operation` carve-out is extended to `adhoc_charges` rather than inventing a second mechanism — and named for what it is.**
*Why:* `void_invoice()` must move billed charges to pending/void_pending_rebill; the v5.2.1 GUC already exists for exactly this on `meter_readings`. Both reviewers showed it is caller-settable (so "only via void_invoice()" was false — wording fixed, AC-12) and Codex showed the leak: SET LOCAL never reset, so a later statement in the same transaction un-billed a charge on an unrelated invoice. Consensus overruled the first draft's "application contract, don't touch the 240-line body": `void_invoice()` is re-issued, identical except `set_config('app.void_operation','false',true)` before RETURN. A true seal (SECURITY DEFINER routing + column-level REVOKE) is application architecture — recorded, not taken.

**D-2026-08-20-21 · Option (b) triggers are the enforcement; option (a)'s REVOKE is a second fence only.**
*Why:* triggers bind the owner too and are undone only by a visible DROP; a REVOKE is undone by the next blanket GRANT and never binds the owner. So `REVOKE DELETE` on the protected set and `REVOKE UPDATE` on the INSERT-only tables ride along, and the guards on the audit-record tables are `ENABLE ALWAYS` so replication apply / `session_replication_role = replica` cannot skip them (Fable LOW-10).

**D-2026-08-20-22 · CI-014's protected set is the 33 operational tables, not "every table"; token is partial.**
*Why:* the rate_* family, `billing_cycles`, `read_routes`, `jurisdictions`, `import_staging`, AI scratch tables etc. are reference/config/staging; `rate_item_history` is moved to its archive by a shipped DELETE (tu.sql:90). Their retention is CI-004/A-1's date-effective discipline. Fable's review correctly called the first header's "structurally-enforced" an over-claim against the CI's "every other operational entity" clause.

**D-2026-08-20-23 · `payments.status` DEFAULT `'posted'` is left alone; the rationale was corrected instead.**
*Why:* Codex showed the "pending intake window" exists only for callers that set pending explicitly. Changing the default decides the intake design by inertia; the guard's behaviour (frozen once not pending, no way back) is right either way. → AC-11.

### Flagged, deliberately not changed (candidates for a later set)

- A CHECK pairing `status = 'void'` ⇔ `voided_at IS NOT NULL` (the trigger now enforces the transition; a CHECK would enforce the state).
- Forward ordering among issued statuses (sent → write_off → sent is accepted); `write_off`/`paid` are not terminal in the schema.
- Whether a voided invoice's `balance`/`amount_paid` should freeze — `void_invoice()` does not touch them.
- `meter_readings` in-place edits stay with `enforce_reading_validation_workflow` until A-1.

### Failed approaches (permanent record)

- **Bare `%` in `format()`** ("unrecognized format() type specifier") and **`text[] || 'literal'`** (parsed as an array literal) — both compiled fine and failed only at first RAISE. Use `%s` and `|| ARRAY['x']`.
- **Testing GUC-gated guards after calling `void_invoice()` in the same transaction** — the lingering `SET LOCAL` made three negative tests pass-through; reordering the battery exposed the real leak that the patch then fixed.
- **Cleaning up a fixture with the very write the guard forbids** — the guard was right, the test was wrong.

### Outcomes

- tu.sql 13,241 → 14,030 lines (pure append; anchors intact). Catalog: 66 tables / 65 policies / 64 FORCE-RLS / 229 CHECKs / 1 EXCLUDE / **147 triggers** (9 ENABLE ALWAYS) / 477 indexes / 275 FKs. Fresh build zero errors; 83-check battery green on the fresh build.
- Reviews: Fable (2 HIGH, 5 MEDIUM, 5 LOW), Codex (2 MEDIUM) — every HIGH/MEDIUM fixed; LOW-9/11/12 documented. AC-10..AC-13.
- GBM: CI-012 → structurally-enforced (header + line items; PDF artifact outside the DB); CI-013 → partially-structurally-enforced (structural for `account_ledger`/`invoice_events`/`invoice_applications`, identity-freeze elsewhere, GUC carve-out caller-settable); CI-014 → partially-structurally-enforced (33-table set). Appendix A-4 LANDED; A-23 records what remains application discipline. Ingestion Section AN.
- Next: A-1 (transaction-time pair), then A-3.

---

## 2026-08-20 — Phase 2 completed (v5.4.1-01 item 2.6 + -06 carryover, v5.4.1-02)

### Decisions

**D-2026-08-20-01 · Item 2.6 lands BOTH the EXCLUDE and the recorded column, where the plan said "either/or."**
*Why:* the CI-027 re-grade named two defects — premise not *recorded* on the read, and overlapping deployments making reconstruction ambiguous. Fixing only the EXCLUDE still leaves the premise unrecorded (the CI's own statement is "every meter read *records* … the service point"); fixing only the column records a value derived from an ambiguous history. Flagged as a scope widening in the patch header rather than landed silently. → `meter_deployments_no_overlap_excl`, `meter_readings.location_id`, `trg_populate_reading_location` (v5.4.1-01).

**D-2026-08-20-02 · The EXCLUDE range is half-open `[install_date, removal_date)`.**
*Why:* `sync_meter_deployments()` closes a deployment with `CURRENT_DATE` and reopens with `CURRENT_DATE`; a closed `[]` range would make every same-day Pattern A remove+reinstall collide with itself. Cost accepted: a zero-day row (`install = removal`) is an empty range that overlaps nothing and covers no read date — tolerated and stated in the COMMENT.

**D-2026-08-20-03 · The in-place active-meter relocation gap is DOCUMENTED (AC-7), not fixed.**
*Why:* both reviewers found that `sync_meter_deployments()` reacts only to `status` transitions, so `UPDATE meters SET location_id = B` on an active meter leaves deployment history — and every later read's snapshot — stale with no error. Auto close+reopen would fabricate a relocation date; rejecting the UPDATE would block legitimate typo corrections. The schema cannot tell relocation from correction, and deciding that by inertia is exactly what Phase 3's rule forbids. → Kyle brief candidate: *"how is an active meter relocated?"* Until ruled, CI-027 stays `partially-structurally-enforced` with this as the leading reason (not nullability).

**D-2026-08-20-04 · Removal/final reads resolve to the deployment CLOSED ON the read date, other purposes to the covering one.**
*Why:* with half-open ranges, a same-day pull-from-A/reinstall-at-B makes a read dated that day resolve to B — wrong for the removal/final read taken at A, the one read that most needs correct attribution (CI-124). A final read with no meter move finds no closed-on-that-day row and falls through unchanged, so the heuristic cannot misfire on the common case.

**D-2026-08-20-05 · `location_id` is never re-derived on UPDATE.**
*Why:* it is a snapshot of where the meter *was*; a later meter move must not reattribute historical consumption (the whole point of CI-027). Cost: a `reading_date` correction does not re-sync it (AC-2). Prefer the supersede pattern (new read row) over in-place date edits.

**D-2026-08-20-06 · CI-032 corrected to `partially-structurally-enforced` (the patch header's first draft said `structurally-enforced`).**
*Why:* the grade had been read off `invariant-scenarios/meter-and-premise-master-data.md`, a stale copy; the register re-graded it 2026-08-13 for two reasons — no temporal guard, and nullable `meters.replaces_meter_id`. 2.6a closes only the first. **Rule:** grades come from `canonical-invariants.md` only, never from scenario files.

**D-2026-08-20-07 · -06 carryover leaves `monthly_variance` / `deferred_balance_after` signed; only the gross inputs get non-negativity CHECKs.**
*Why:* the -06 header defines the sign as living in the variance/balance columns; `actual_gas_cost` is the gross supplier invoice and `pga_recovered_revenue` the gross billed revenue. A supplier credit month is a *lower* cost, never a negative one — stated so nobody later tries to post a negative "credit month."

**D-2026-08-20-08 · `tenant_configuration_history` is ONE key/value table with JSONB values, populated by trigger.**
*Why:* thirteen typed columns plus an open-ended `settings` blob do not fit a typed-column history; the 3M brief's own shape was key/value. Trigger-written rather than convention because with no application layer a convention-only history would grade `requires-application-discipline` and the hazard would remain. On tenant INSERT every key is recorded so an onboarding default becomes a recorded decision (W-tenant-onboarding item 5). Settings granularity is top-level key (whole sub-object before/after); finer is a later call. *Not chosen:* the brief's interim "snapshot resolved policy onto `billing_runs`" — that is A-3's territory.

**D-2026-08-20-09 · `get_partial_period_policy(uuid, timestamptz)` — `p_as_of` REQUIRED, NO live-column fallback, NULL RAISES, pre-history returns NULL. Old one-arg signature dropped.**
*Why:* CI-006 says the temporal coordinate is an explicit input, never implicit "now." A `DEFAULT now()` would have kept the time-blind form as the path of least resistance. The first draft's `COALESCE(... , t.default_partial_period_policy)` was caught by both reviewers: NULL `p_as_of` (realistic — `get_correction_rate_date()` documents returning NULL) and any pre-history coordinate silently resolved to *today's* value, i.e. the bug the patch exists to fix, back through the side door. Dropping the old signature is safe: zero callers in tu.sql. **Standing rule for every future temporal helper (A-1/A-3): no live-value fallback; NULL coordinate raises; NULL result means "unknowable," never "use the default."**

**D-2026-08-20-10 · The history bracket is transaction time, not valid time.**
*Why:* `effective_from` is `now()` at the change; an operator cannot say "this took effect last month" through the trigger path. Valid-time policy changes are the A-1 bi-temporal pair's job (bi-temporal-decision §6); inventing a second valid-time mechanism here would pre-empt it. Backdated rows remain *representable* as `change_source='manual'`. Hence CI-004 stays partial.

**D-2026-08-20-11 · Backfill stamps the deploy-time value at `tenants.created_at`, explicitly flagged as an approximation.**
*Why:* with no live fallback in the function (D-09), existing tenants must still resolve for pre-deploy coordinates, and `now()` would make all of them NULL. A value changed after onboarding is therefore recorded as if in effect since creation — unknowable either way; every backfill row carries a `change_reason` saying so.

**D-2026-08-20-12 · Direct inserts into the history are allowed for `tally_app` but guarded.**
*Why:* backdated corrections should not require a migration; RLS scopes them to the caller's tenant. But a direct insert may not impersonate the recorder (`pg_trigger_depth()` guard on `change_source`), must use a known `config_key`, and must carry a legal `default_partial_period_policy` value. TRUNCATE is rejected like UPDATE/DELETE; the tenant FK has no CASCADE — an audit trail must outlive its tenant (CI-093).

**D-2026-08-20-13 · Identity `seq` column as the deterministic tiebreaker.**
*Why:* `now()` is fixed per transaction, so two changes to one key inside one transaction tie on both `effective_from` and `created_at`; "latest row" was a coin flip in testing. Resolution orders by `effective_from DESC, seq DESC`.

**D-2026-08-20-14 · Two independent adversarial reviews (Fable + Codex) before every mirror; reviewers must fresh-load tu.sql + patch into a scratch database.**
*Why:* round two caught a wrong CI grade and a real attribution bug live testing had not; round three caught the time-blind fallback. The scratch-DB load was added after the btree_gist failure (below) to catch environment-dependent statements before the mirror.

**D-2026-08-20-15 · `application/APPLICATION-CONTRACTS.md` exists and is mandatory to update.**
*Why:* several patches now assume caller behavior the DB can't enforce (set `start_date` on reactivation; never pass NULL `p_as_of`; write `settings` at onboarding if you want it recorded). With no application code yet, these obligations had no home. Every patch that lands a constraint or trigger with a caller assumption adds an AC entry.

### Flagged, deliberately not changed (candidates for a later set)

- `rate_schedules.partial_period_policy` (no CHECK, **read** by `get_partial_period_policy`) duplicates `partial_period_policy_override` (CHECK-constrained, read by nothing). Two columns for one override; the unchecked one is live.
- `sync_meter_deployments()`: stale `meters.start_date` on Pattern A reactivation and stale `meters.removal_date` on deactivation now fail at the EXCLUDE/CHECK inside the trigger (AC-1). Substituting a date would be guessing; candidate Kyle brief whether the trigger should take an explicit reinstall date.
- Cross-tenant `meter_id` on a read passes the (not tenant-scoped) FK and leaves `location_id` NULL under RLS (AC-3). Same FK shape already flagged for the landlord and ledger lineage FKs.
- All three v5.4.1-01 cycle guards race under concurrent transactions (AC-6). Closing it needs advisory locks or SERIALIZABLE.

### Failed approaches (permanent record)

- **Trusting the iteratively-patched container as a deploy test.** `CREATE EXTENSION IF NOT EXISTS btree_gist;` worked in every psql session all day and failed the fresh build with `ERROR: no schema has been selected to create in`, because tu.sql runs under `search_path = ''` (tu.sql:65) and a psql session does not. Fix: `WITH SCHEMA public`. Rule: the fresh rebuild from `postgres/Dockerfile` is mandatory before commit, and reviewers fresh-load into a scratch DB before the mirror. Any statement that depends on search path must be schema-qualified; `pg_catalog` functions are safe, extension-provided operators/types are not.
- **Reading a CI grade from a scenario file** (see D-06).
- **Mirroring from the wrong banner line.** The patch header has two `-- ====` lines; the body starts after the *second* (the line before the first `-- Item` / body comment). Splitting at the first mirrored the whole header into tu.sql — harmless, but not the -06 form; redone.
- **Incomplete test fixtures cost four runs** — `service_locations` needs `address_line1/city/state/zip`, `service_orders` needs `order_number/description`, `import_jobs` needs `initiated_by/error_handling_policy` (enum), `rate_schedules` needs `customer_type` (enum). Query `information_schema.columns … is_nullable='NO' and column_default is null` and `pg_get_constraintdef` first; wrap negatives in `SAVEPOINT sp … ROLLBACK TO sp`.
- **`COALESCE` onto a live column in a temporal helper** (see D-09) — it reads as a harmless default and is exactly the bug class the helper exists to remove.

### Outcomes

- tu.sql 12,279 → 13,241 lines (pure appends; anchors 337/3600/3679 intact). Catalog after -02: 66 tables / 65 policies / 64 FORCE-RLS / 229 CHECKs / 1 EXCLUDE / 70 triggers / 477 indexes / 275 FKs. Fresh build zero errors; all batteries green on the fresh build (`sql/DEPLOY-VERIFICATION.md`).
- GBM: CI-004/006/017/018/027/032/093/118/122 re-checked — **every grade token unchanged**, descriptive text corrected; family-15 intro four → three; Appendix A-22 added; parity plan Phase 2 ✅; ingestion Sections AL + AM; `ryan` 15 commits ahead of `origin/main` (catch-up is Ryan's call).
- Next: Phase 4 Wave 1 — A-4 → A-1 → A-3.

---

## Before 2026-08-20

Decisions from Phase 0/1 and the first half of v5.4.1-01 (2.1/2.2/2.3/2.5) are recorded in `CHANGELOG.md` entries dated 2026-08-18/19 and in each patch file's own header (`sql/v5.4.0-0*.sql`, `sql/v5.4.1-01-*.sql`, "Drafting decisions" section) — the headers are the authoritative per-patch record. Kyle rulings: `gas-billing-memory/application/wu5-wu6-kyle-decisions-2026-07-10.md` and the decision tables.
