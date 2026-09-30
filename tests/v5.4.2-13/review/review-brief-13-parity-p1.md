# Review brief — v5.4.2-13 parity re-scope, round P1 (frozen) — ONE focused round

| Artefact | Lines | md5 |
|---|---|---|
| `sql/v5.4.2-13-backbilling-caps.sql` (= `review/patch-13-frozen-p1.sql`) | 2167 | `07ced77c92311ae73ffd3f19623ca4f9` |
| `tests/v5.4.2-13/battery-13.sql` (= `review/battery-13-frozen-p1.sql`) | 853 | `80a98fcbd3ac09ad37d20cb9812b512a` |
| `tests/v5.4.2-13/mutations-13.py` | — | `fe19110a0b56aacddde32a70b4168649` |
| `tests/v5.4.2-13/evidence-txn-13.sh` | — | `587a2b4ae524295820a36986fa63f3f5` |

Nothing in this table changes while the round is open.

## What changed since rounds 1–6

The earlier rounds reviewed r7, which *evaluated* Texas law inside about 3,700 lines of triggers. Ryan ruled on 2026-09-28:
- **The schema represents; the C# core evaluates.** Triggers protect record integrity. They never compute law: windows, forfeitures, who must approve, which causes may be reissued.
- **A Texas-only launch is not a Texas-only architecture.** Law is platform-held, dated rows keyed by (state, service, class, cause). Texas is only the first set of rows.

The design is `application/a2-parity-rescope-2026-09-28.md` (§1 keep, §2 drop, §3 rule tables, §4 what the DB still refuses, §6 as built). Everything the dropped triggers decided is in `application/a2-rules-for-the-core.md`.

## The two questions — and only these

**Q1. STORE.** Can the schema hold everything the law and the core need, without a schema change?
- Every attribute a Kyle ruling (R-19…R-39, E-1; see `a2-rules-for-the-core.md`) needs as a *rule parameter* is on the law rows.
- Every *input* the core needs to evaluate a correction is recorded, and every *output* it produces: the evaluation, per-period evidence, disposition, forfeited amounts, approvals, holds. Each output names the rule row and core version that produced it.
- A second state with different law fits as rows alone. Group Z of the battery (fictional state `ZZ`) is the existing proof. Find a plausible statutory shape that does NOT fit.

**Q2. PROTECT.** Are the records protected, whoever writes, as `tally_app`? This is the list in design §4:
- no rows from another utility (tenant isolation);
- evaluations, evidence, approvals, events and acquisitions can't be edited or deleted;
- a frozen case can't change;
- a frozen case can't point at another case's evaluation;
- a test that a frozen case cites can't be superseded;
- open holds can't overlap;
- a law row needs a citation, can't overlap another for its key, and is never edited, only closed and replaced;
- the app can't write the law tables;
- causes and classes must exist;
- timestamps and actor ids are stamped by the database, not supplied by the caller;
- evidence can be written only in its evaluation's transaction.

Also flag any **Texas literal or state/cause/service-name branch** left in a trigger or CHECK. The stopping rule is that no patch lands with one.

## Out of scope (do not report)

- Whether a correction is *lawful*: the window, forfeitures, approval rules, the reissue gate. Those are the core's job now, by design (§2). A finding that "the DB accepts an unlawful correction" is not a finding.
- The open Kyle questions (R3 rule date, R9 unprotected class, D1/D3/D5/D6) and residuals R1–R9 at the end of the patch. They are known and stated.
- City-level rules (R2) and the Texas-shaped class-mode names (R4). These were decided by Ryan.
- Contrived multi-step attacker chains. The bar: a plausible app bug or a plausible second state that the schema gets wrong.

## Rules

- Do **not** edit anything in the repo. Write probes in your scratch space only.
- Your database is already built: the -12 base plus the frozen patch, applied strictly. Use `docker exec -i tally-pg psql -U tally -d <your db>`. Act as `SET ROLE tally_app` for app-path probes. See the battery's fixtures for the minimum rows each table needs.
- Every finding needs a **runnable repro** and the observed result, or it isn't a finding.
- Rank by severity. Say which question (Q1/Q2) each finding answers.
- **Verdict:** "sound enough to mirror" or "not yet", with the findings that block it.
