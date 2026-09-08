# Review Brief — v5.4.2-10, ROUND 2 (A-3 follow-up: snapshot coordinate binding)

**File under review:** `sql/v5.4.2-10-snapshot-coordinate-binding.sql`
**     778 lines, md5 `9160f8afbbc942dfb8213a6970655d78` — FROZEN for this round. Verify before testing; if it differs, stop and say so.** Round 1 was `bb7cdbd9…` (682 lines); its brief is `review-brief-10.md` and still describes the intent.

## What changed since round 1 (every finding folded into this one body)

| Round-1 finding | Fix in this revision |
|---|---|
| Fable CRITICAL-1: `invoices.created_at` UPDATE-able on an unsnapshotted draft → off-run lower bound forgeable (also via on-run → off-run re-home) | `created_at` is write-once for every non-superuser, snapshot or not (`enforce_invoice_snapshot_inputs`). Battery F21a/b/c. |
| Fable HIGH-2 (draft decoy as "original"), HIGH-3 (deletable draft snapshot anchors original-world replay), Codex MEDIUM-3 (non-void original → two live bills) | Correction branch requires the replaced invoice to be RLS-visible, same-tenant and `status = 'void'` (checked at insert AND issuance). Only a void bill's period_end and snapshot are sealed. Battery F22. |
| Fable LOW-6 / Codex MEDIUM-2: cross-tenant read through `get_correction_rate_date` (SECURITY DEFINER) | The replaced invoice is read invoker-rights (RLS) BEFORE the resolver is consulted; another tenant's id is "not found". Battery F23. The resolver's direct EXECUTE by tally_app is pre-existing and recorded as an A-23 item, not changed here. |
| Fable MEDIUM-4 (two workers deadlock through the run-row FOR SHARE) + author probe A-1 (heartbeat blocked) | Validator takes the run row FOR KEY SHARE (compatible with plain UPDATEs); the run election guard escalates its own row to FOR UPDATE before checking. Live: heartbeat 3 ms while a writer held; election change waited then refused; two workers snapshot + bump totals in one txn each — both commit (`races/two-workers-r2.out`). |
| Fable MEDIUM-5: `run_type` read but not frozen | `run_type` added to the frozen set and the trigger's UPDATE OF list. Battery F24. |
| Fable LOW-7: two corrections per target both pass | One snapshotted correction per (run, replaced bill); the target row is the mutex — the validator takes its row lock via `UPDATE … SET updated_at = now()`. Live: RC loser waits then is refused; RR loser gets `serialization_failure` (`races/corr2-race-*.out`). Battery F25. |
| Codex HIGH-1 / Fable LOW-8: isolation pin fires before the EXISTS check | All three guards check EXISTS first (frozen → `restrict_violation`), then refuse non-READ-COMMITTED with a message saying WHY (absence cannot be verified under RR). **The pin itself stays** — see "Attack this" below. |
| Fable disagreement: `data_cutoff_at` as an anchor; AC-15 "one pair per run" | Neither landed; both stated in the header's NOT-landed list with reasons (cutoff = candidate-set freeze line, not a lookup coordinate; one-pair-per-run breaks on per-target original-world replays). |

Battery is now **47 green** on the clean apply and the pre-seeded apply (report NOTICEs fire). Strict apply ×2 clean.

## Attack this (round 2 focus)

1. **The isolation pin, as re-ordered.** Under REPEATABLE READ, editing a binding column on a draft with no visible snapshot is still refused. Author's reasoning: a snapshot writer may have committed after the RR transaction's snapshot; the row-lock wait does not refresh an RR snapshot, so absence cannot be verified, and SSI only protects if the writer is also SERIALIZABLE. Is there a correct alternative that admits RR edits of never-snapshotted drafts? If not, is AC-31 ("edit these columns under READ COMMITTED") acceptable?
2. **The void requirement.** Does requiring `status = 'void'` refuse any legitimate correction flow? (Held → void discards; corrections of pre-A-3 bills; consolidated parents/children; a void bill later un-voided — A-4 says never.) Can a void original's inputs still move — e.g., can its snapshot be deleted, its period changed by anything?
3. **The new mutex UPDATE on the target row inside the validator.** Side effects (set_updated_at, RLS, privileges), deadlock shapes with the target guard or with void_invoice(), and whether a caller can defeat it (target for another meter? two target rows? `UNIQUE(billing_run_id, voided_invoice_id)` exists per Codex).
4. **FOR KEY SHARE vs the FOR UPDATE escalation**: any run-row write path that changes the election without passing through the guard (superuser aside)? Any deadlock between the escalation and another guard's lock order (invoice FOR SHARE → run KEY SHARE → target row lock)?
5. **created_at write-once**: any legitimate writer of `invoices.created_at` (imports, consolidation, void_invoice)? Superuser exemption reach (all definer functions are owned by the superuser role — Codex checked five; confirm none writes created_at).
6. Everything from round 1 that held — re-run your own repros against the new hash and confirm each is now refused.

## How to test

As round 1: `docker exec tally-pg psql -U tally -d <db>` (no host port, no `postgres` role). `s10c` = fresh + revision 2 (pristine, yours); `s10b` = pre-seeded apply; `s10` = revision 2 + committed race fixtures; `tally` = virgin. Patch at `/tmp/p10.sql` (md5sum matches), battery at `/tmp/battery-10.sql`. Fixture minimums and the v1 snapshot body as in round 1. **New:** a correction's replaced bill must be void — `void_invoice(id, user, reason_code, notes, rebill_expected)` as the tenant's user (`SET app.user_id`); drafts are not voidable (hold first, or issue to pending).

Report as before: hash verified; findings most-severe first with repro and fix; disagreements; what held; verdict.
