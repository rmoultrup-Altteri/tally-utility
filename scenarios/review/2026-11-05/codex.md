# Codex review — scenarios round 3

Reviewed 2026-11-07: SCN-0060–0080 in `tenant-isolation.md` and `date-tracking-and-immutability.md`, after the Opus and Fable fixes, against Ryan's amended impersonation ruling. **Four must fix; two should add.** Findings already addressed from the other reports are not repeated.

Evidence is from the mirrored `sql/tu.sql` and the cited source documents. The board and parity updates correctly identify -27 as mirrored and -30 as unmirrored. I attempted the permitted SELECT of trigger definitions through `docker exec tally-pg psql`; Docker denied access to its socket. No live query succeeded, and no database writes were attempted. SQL conclusions below are static inspection, not executed reproductions.

## 1. SCN-0079 — must fix — A dry run can be inserted already approved or posted

**What is wrong:** The Status at `scenarios/date-tracking-and-immutability.md:198` says a dry run may not be approved or posted, without a gap qualification. The normal transition in (b) is guarded, but the same forbidden state can be supplied when the run is created.

**Evidence:** `sql/tu.sql:2367` admits both statuses. `enforce_dry_run_terminal_status()` at `sql/tu.sql:12044` checks them, but its trigger at line 12059 is **BEFORE UPDATE only**. The other insert guard, `enforce_billing_run_clock_and_election()` at line 20419, stamps the start and returns from its INSERT branch without checking status. No later definition in the mirror closes this path. Invoice, ledger and reading guards still prevent their respective side effects; an accepted posted status does not prove that a bill or money was posted.

**Fix:** Qualify the Status as built for transitions, with the insertion gap. Add an independent branch creating an otherwise valid dry run already `approved` and another already `posted`: refusal under the rule, expected failure of the protection test today. Keep the existing transition assertions.

## 2. SCN-0066 — must fix — Releasing the file fingerprint does not release the job key

**What is wrong:** (d1)'s retry is unconditionally accepted, although its unchanged filename and content generate the same job key as the failed job. That key remains occupied. Likewise, (e)'s changed content is insufficient for acceptance if the sender supplies the previous job key. The fixture never specifies the key strategy, so these acceptance tests cannot reliably pass as written.

**Evidence:** `scenarios/tenant-isolation.md:152` and line 159 require the failed job to remain while the identical file is imported again. `sql/tu.sql:5344` has unconditional `UNIQUE (tenant_id, idempotency_key)`. The insert function at line 12317 derives a missing key from filename, hash and preview/commit; supplied keys are kept. The partial index at line 37562 releases only the **hash** on failure/cancellation. The record guard at line 37572 freezes the failed job's key and final status. These protections coexist; neither replaces the other. The source outline's A9 explicitly distinguishes a reused key with different content.

**Fix:** Give the retry a fresh job key explicitly, and distinguish file-content deduplication from job-key deduplication. Add refusal cases for reusing the failed job's key and for changed content under an existing key. Specify a fresh/generated key for (e). Also replace (d1)'s “malformed row the bank fixes ... as the same content” with a transient processing failure if identical bytes are intended. This is separate from the already-reported partial-posting problem in (d2).

## 3. SCN-0080 — must fix — The zero-supervisor assertion contradicts the newly bound supervisor

**What is wrong:** (d) binds Bluebonnet's new supervisor BB-admin2; (e) switches off only BB-admin and asserts zero active supervisors; (f) has BB-admin2 sign in the next day. BB-admin is not the last active supervisor in that sequence. Excluding the Tally User cannot make BB-admin2 disappear from the count.

**Evidence:** `scenarios/tenant-isolation.md:227–229` gives the sequence; line 236 requires zero. Ryan's fourth condition at `application/DECISION-LOG.md:11` excludes the **Tally User**, not another utility supervisor. No inactive state or separate fixture for BB-admin2 is given.

**Fix:** Run (e) before (d), explicitly starting with BB-admin as the sole active utility supervisor. Assert zero immediately after switching it off, then provision BB-admin2 through the Tally User and assert one. This also demonstrates provisioning while no active utility supervisor exists, followed by BB-admin2 reading the history. Alternatively, make (e) a clearly independent fixture.

## 4. SCN-0071 — must fix — The mirror does not require both coordinates on every dated lookup

**What is wrong:** The Status at `scenarios/date-tracking-and-immutability.md:60` says “the schema makes every dated lookup name both dates.” This is broader than the mirrored implementation. The core's obligation to use one pair is correct, but part of the required lookup support is still missing, beyond the already-disclosed run-instant equality check.

**Evidence:** The mirrored `premise_places_as_of` at `sql/tu.sql:27021` takes a premise, a valid date and an axis, with **no recorded instant**. At line 27050 it selects memberships with `voided_at IS NULL`, so a later withdrawal removes membership from a historical lookup too. This matters to the places/tax inputs discussed by this family and SCN-0077. Unmirrored -30 adds the recorded-instant overload at `sql/v5.4.2-30-tax-levies-and-taxability.sql:780`; the board at `HANDOFF.md:37` says it is still in review. Even that patch retains a three-argument wrapper defaulting to `now()` at line 858, so “every lookup requires both” would remain too broad after its mirror.

**Fix:** Narrow the built claim to the lookup families that actually require the pair, and explicitly identify place reconstruction as pending -30. Retain the core rule that billing must choose the explicit-coordinate path. Add a place-membership correction during a run, asserting the start-of-run knowledge is used; tag the necessary lookup support as unbuilt in the mirror. Do not describe -30 as already built.

## 5. SCN-0077 / SCN-0078 — should add — Specify the billing periods around the March 1 change

**What is missing:** Both tests say “February bill” and “March bill,” without dates. SCN-0077 changes schedule on March 1; SCN-0078 changes pressure factor on March 1. The cast's demonstrated billing periods are mid-month (`scenarios/date-tracking-and-immutability.md:7`, line 63). A March period can therefore span the change. A test must invent the period and, for the schedule change, decide how the change applies across it. That choice can affect whether the whole bill uses the single new value asserted.

**Evidence:** SCN-0077's Given/When/Then are at `scenarios/date-tracking-and-immutability.md:166–171`; SCN-0078's are at lines 183–190. `scenarios/cast.md` §2 leaves a mid-period rate change's method to the utility, with no default. CI-004 and the bi-temporal outline A1/A2 require the relevant dates to be explicit.

**Fix:** Give both periods and computation instants. For a focused historical-assignment test, choose an explicitly invented calendar-month cycle, making March 1 its boundary. Otherwise state the applicable method instead of leaving the test author to choose. Add a lookup for a March date immediately before and after the March 2/3 recording instant to prove the knowledge axis as well as the February-versus-March effective-date axis. SCN-0078's correction figures themselves are correct.

## 6. SCN-0068 / SCN-0080 — should add — Prove the impersonation session stops authorizing changes when it ends

**What is missing:** The scenarios start and end sessions and inspect their history, but never attempt a further change using an ended session. SCN-0080(b) tests direct login without a session; that does not exercise reuse of a formerly valid impersonation context.

**Evidence:** `scenarios/tenant-isolation.md:197` and line 227 end the sessions. Neither corresponding Then tests subsequent use. Ryan's accepted condition at `application/DECISION-LOG.md:11` makes the Tally User reachable **only through an impersonation session**, records start/end, and requires every act to identify the actual employee. AC-43 at `application/APPLICATION-CONTRACTS.md:424` also identifies pooled-context leakage as a concrete concern.

**Fix:** After ending a session, attempt another utility change with that session's identity/context; require refusal and no utility mutation. Then open a fresh session and assert that its accepted change cites the new session. Include reuse of the connection by another request, so a stale Tally User context cannot remain authorized. Keep this marked not built. This follows the accepted session boundary without introducing a new utility-consent requirement.

## Checks with no additional finding

- Recomputed SCN-0069: $63.56 base + $0.64 tax = **$64.20**; corrected **$65.83**, difference **$1.63**. SCN-0070: $66.08 base + $0.66 tax = **$66.74**. SCN-0076: $65.18 base + $0.65 tax = **$65.83**. Decimal arithmetic with half-up cent rounding agrees.
- SCN-0078: 38.0 × 1.0500 = 39.9000; × $1.67 = $66.6330 → **$66.63**. The contrast at 1.0800 is 41.0400 × $1.67 = $68.5368 → **$68.54**.
- SCN-0062(f), SCN-0065 and SCN-0068 reflect the November 7 ruling: Tally-controlled powers through the utility's Tally User; named-user impersonation remains limited to that user's powers; cross-utility plain reading remains allowed; sessions and marking are correctly described as unbuilt. I do not recommend reinstating the superseded plain-platform-admin read-only rule.
- The prior corrections to snapshot pricing dates, correction-run placement, shared reads without an active utility user, incomplete-meter reasons, final-outcome gaps, locked-draft discard, payment history and snapshot input coverage are present. Their previously reported issues are not new findings here.
