# v5.4.2-20 review round 1: findings and how r2 answers them

**Verdicts on r1:** Opus "not yet" (B1, B2); Fable "not yet" (B1); Codex "request changes" (B1–B4). Every reviewer found the direct-write seals intact. Each finding below is settled by a standing rule. None needs Ryan.

## Blocking, folded into r2

| # | Finding | Who | Rule | r2 |
|---|---|---|---|---|
| F1 | The attach guard admits a bill the caller cannot see. RLS hides it, and the FK checks only the id. Repro: tenant 1 billed a charge onto tenant 2's void bill, stranding it. | Opus B1, Fable S3, Codex B2 | Guard the act | Refuse a pointer to a bill not visible. Refuse a bill of another tenant than the row, which covers the platform admin who sees both. |
| F2 | A void at REPEATABLE READ or SERIALIZABLE misses an attach that committed after its snapshot. Repro: the bill is void and the charge is still billed on it. | Opus B2, Fable B1, Codex B3 | Count-guards need a lock handshake | `void_invoice()` refuses unless the transaction is READ COMMITTED. An attach at REPEATABLE READ behind a void fails to serialise; that is a race test. |
| F3 | A charge can enter `billed` without its pointer changing: set the pointer on a pending charge, void the bill, then mark it billed. | Codex B1 | Guard the act | CHECK: a charge is `billed` if and only if it names its bill. Entering billed then always moves the pointer from NULL, which fires the attach guard. Reads need no change: the -19 guard writes their pointer only with the move to locked. |
| F4 | The new guards are origin-only, so `session_replication_role = replica` skips them. This contradicts D-2026-08-20-27. | Codex B4, Opus S5 | D-2026-08-20-27 | Every new guard is `ENABLE ALWAYS`. The invariant requires `A`. The S13 forgery disables the stamp trigger inside the rolled-back battery instead of using replica mode. |

## Should-fix, folded

- **F5. The invariant is narrower than its claim.** [Opus S2–S5, Fable S1, Codex S1]
  - Exact `regprocedure` identities.
  - A NULL-safe pin test.
  - An exact privilege allowlist per seal role: table, column, function and schema grants, and nothing else. This also covers writes to `users` and the core's definers.
  - Column-level privileges on the receipts.
  - The exact shape and `ALWAYS` state of every guard trigger, new and rewritten.
  - The lexical setting check is kept and described as lexical.
- **F6. Grants to `tally_void` narrowed.** [Opus S6, Fable S2, Codex S3]
  - Dropped: SELECT on `billing_runs` and on `invoice_events`.
  - UPDATE is column-level, on exactly what `void_invoice()` writes.
  - The charge guard's "keeps `billed_by_billing_run_id`" clause is removed, because the grant now fences it (memory rule: no redundant guard).
  - Batteries -19 (R4, R5c) and -20 (V9c, V10) now expect the role's own refusal, 42501.
- **F7. The no-deadlock claim was false.** [Opus S1, Fable S4, Codex S2] An attach in a transaction that already holds a child of the same bill can deadlock with a void. PostgreSQL aborts one, and nothing is stranded. The lock-order paragraph now says so and tells the caller to retry. A race test shows the deadlock and that nothing is stranded.
- **F8. Test gaps.** [Opus S7–S9, Codex S4]
  - S4e counts receipts.
  - S10g supplies wrong values and expects them stamped over.
  - S13e: a receipt for the same uuid under another header table.
  - MERGE (S14).
  - COPY by the application (T6).
  - The void-first and attach-first REPEATABLE READ cases (T7, RC3b).
  - V11 is relabelled for what it proves (the role cannot insert bills).
  - Not added: the issued-bill void with a real snapshot. battery-10 F0c voids a snapshotted issued bill through `void_invoice()`, which now runs as `tally_void`.
- **F9. The mutation harness** now requires the named check to be the *first* FAIL, for the race script too. New mutations cover F1–F6.
- **F10. Wording.** [Codex N2, N3, R8 note]
  - "Never" becomes "cannot by ordinary means".
  - "The only door" is said for ordinary writers, not administrators.
  - R8 now reads "no sanctioned workflow writes one".
  - Inventory V3 describes the approved RLS substitution.

## Not taken

- **Fable S5 (the version guard also checking the OLD entity on UPDATE).** The bitemporal guard already freezes the entity column, so a second check could never fail on its own (memory rule: redundant guards make a mutation miss). Recorded in a comment instead.
- **Codex B2's composite tenant FKs.** This is -19 residual R11, Ryan's call. F1's tenant comparison in the guard closes the attach case without it.
- **A check-first writable CTE case.** CTE order is not a protocol. AC-42 says to use separate statements.
