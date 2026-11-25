# Fable review — v5.4.2-24 r12 (unmatched cash and agency pledges)

**Date:** 2026-11-24. **Reviewer:** Fable (claude-fable-5-2). **Brief:** `review-brief-24-r12.md` (md5 `64cf3366ec3a915300c68edfab3e3ba2`, matched its `.md5`).

**Frozen hashes checked, all matched:** patch `37630681…`, battery `96b21ecd…`, races `360dea4d…`, mutations `87d1bec0…`, ci diff `ec30f743…`, r11-to-r12 `ecb5feb6…`. I reviewed the frozen copies only.

**Verdict: ready.** No blocking item and no should-fix item. All four of my round-11 findings are closed, each re-executed: the bank's return code is now refused on every shape where rows sit beneath the named row (B1), a receipt's payment cannot be loaded already posted (S1), the deposit entry type is now guarded by fixtures and one mutation per walk (S2), and the end-of-battery conservation check no longer double-counts a nested bounce (N1). I could not build a coded `reversed` that hides a misposted part. Six notes follow; the first is the one shape I found where the conservation check itself is wrong while the patch is right (a test-only fix, one line, no fixture has the shape today).

**Scratch database:** `rv24fable` (TEMPLATE `tally`; TEMP revoked from PUBLIC, `tally_app`, `tally_core` right after each creation; frozen r12 applied strictly, twice the first time; dropped at the end, and `/tmp/fr12` removed from the container). I did not run `ci.sh` or `mutations-24.py`, created or altered no role, read no `opus-*` or `codex-*` file and no file of theirs in the shared scratchpad. To check individual mutations I wrote my own small runner that imports only the mutation list from the frozen file and rebuilds **my own** clone (`rv24fable`, never `m24`) per mutant; the clone was rebuilt clean from the frozen patch before the probes that followed (body md5 of `enforce_payment_suspense_pledge` checked: `c2857f86…`, the pinned value). Two `crystaldba/postgres-mcp` containers were running at my start; I did not touch them. My scripts and outputs: `/private/tmp/claude-501/-Users-ryanscomputer-code-tally-utility/e505317d-789c-4641-8100-8791f236e965/scratchpad/fable-r12/`.

## Reproduced (executed)

- Strict apply (`search_path=''`, `check_function_bodies=on`): clean; the second run skipped by its marker.
- `battery-24-frozen-r12.sql`: **352 PASS**, 0 FAIL, rolled back.
- `suspense-24-frozen-r12.sh rv24fable`: **29 PASS**, exit 0; `assert_suspense_pledge_guard_invariants()` clean afterwards.
- Trigger order by name, all ENABLE ALWAYS: on `payments` (before update) `enforce_payment_immutable` < `enforce_payment_suspense_pledge`; on `account_ledger` (after insert) `enforce_ledger_reversal` < `enforce_ledger_suspense_posted`. The order the new comments describe.
- Mutations, each alone on my clone, first failure shown: M168 → P23, M169 → P23, M170 → O7c, M171 → D2, M172 → D8, M173 → D7, M174 → D4b, M175 → D2; re-pointed M118, M129, M138 → D2, M143 → P24b; re-anchored M145 → P16, M146 → P17, M155 → O7, M156 → O7b. All sixteen caught at their named check. Control (no mutation): 352 pass.

## My round-11 findings

| Finding | State |
|---|---|
| B1: a bank code admitted over rows under the named row's undo | **Closed.** P23, P23d refuse; my probes A2, A11, A15, G7 and the race below. |
| S1: a receipt's payment loaded born `posted` | **Closed.** Owner INSERT and the same under `session_replication_role = replica`: both 23514 "is born posted … load it pending". Born pending by the owner, then its entry and the move: admitted, receipt holds 0. |
| S2: no deposit fixture | **Closed.** D1–D8, D4b; five walks, five mutations, each caught alone (above). |
| N1: the conservation check counted a nested bounce twice | **Closed** (P24; my G3 below reads 100 of 100 at every date). One other shape it gets wrong: N1 below. |

Round 10 and earlier: the battery checks that hold them re-ran (352).

## B — blocking

None.

## S — should fix

None.

## N — notes

### N1 (executed). The end-of-battery conservation check counts a pending payment twice once its posting entry is written.

The check adds a pending payment's amount (new in r12) and also what `payment_position_as_of` says the payment received, which already counts the posting entry. A pending payment whose posting entry is written but whose move to `posted` has not happened is a legal state that can be committed (the battery passes through it at D7), and the patch treats it correctly (the receipt holds 0). Probe G1: receipt 100, a pending payment of 100 from it, its posting entry inserted, no move:

```
S4c's sum for that receipt = 200.00 of 100.00, at every date from 2026-03-10
after UPDATE … status = 'posted': 100.00 of 100.00
```

No fixture is in that state when the check runs, so the battery passes. A one-line fix in the battery: count a pending payment's amount only where it has no posting entry (`AND NOT EXISTS (SELECT 1 FROM account_ledger l WHERE l.reference_type = 'payment' AND l.reference_id = p.id AND l.reverses_ledger_entry_id IS NULL)`), and leave one fixture pending with its entry written. Test-only; nothing in the patch changes.

### N2 (executed). No mutation is named for the conservation checks, but the new one does fire.

`S4b`, `S4c` and `S4d` are the named check of no mutation, and since r12 `S4c` runs last, so every mutation stops at an earlier check and never reaches it. To see whether it has teeth I ran the battery with its three helpers reporting instead of stopping (a copy, piped in; the frozen file untouched) under four mutants: `S4c` reported FAIL under M175 (the as-of share walks no deposit), M143 (the as-of share counts what the bank took) and M117 (a returned payment still listed), alongside the named checks; clean under no mutation. So it is a working oracle for the reader and the as-of share. By construction it cannot see a coded `reversed` that hides a misposting (it counts a coded payment's whole share as the bank's): that defect is held by P16, P17, P23 and P23d alone.

### N3 (executed). D2 is now the named check of five mutations and tests three things at once.

M118, M129, M138, M171 and M175 are all first caught at D2, whose condition is three facts joined by AND (the final share is 60; listed "60.00 since 2026-03-11" on 03-11; not listed on 03-10). Each mutation is caught alone, so the count is honest, but a D2 failure does not say which of the three broke, and the older checks those three re-pointed mutations used to name (S8f, S8g) now have no mutation of their own. Splitting D2 into three lines would give each mutation its own check. Not needed for the mirror.

### N4 (executed). The new code rule: every shape I tried, as `tally_app`.

Receipt 100, payment 100 to one customer, in each:

| Probe | Shape | Result |
|---|---|---|
| A2a | 100 reversed, undone, 100 taken again under the undo; code naming the childless 100 two levels down | 23503, -23: the named row must sit directly under the posting entry |
| A2b | same; code naming the first reversal | 23514 "nothing is filed beneath it" |
| A2c–g | same; no code, then return 100, then `bank_returned` 100 at the receipt | all admitted; listed "100.00 since 2026-03-12" before the return; receipt holds 0 after. The stricter route works end to end. |
| A11 | 100 reversed, undone, 100 taken again **under the posting entry**; code naming the re-take | admitted; nothing listed, receipt holds 0. So a clerk who re-files the bank's take-back under the posting entry still gets the code. |
| A5 | after that coded end: a plain undo beneath the named row; an nsf-typed undo; a return of 100 | 23001, 23001 (-23, "which has ended"), 23514 |
| A8 | 60 + 40 plain; code naming another payment's childless 100 | 23503 (-23) |
| A8b | 60 + 40 plain; code naming the 60 | 23514 |
| A12 | a negative row directly under the posting entry | 23514 (-23, opposite sign) |
| A13 | `reversed` with a code naming an nsf row | 23503 (-23) |
| A14 | 100 reversed, undone, 100 nsf under the undo; code naming the first reversal | admitted: the share is 0, the bank took it all as nsf rows; nothing listed, receipt holds 0 |
| A15 | 100 reversed, undone, 60 plain and 40 nsf under the undo | code refused (23514); without it admitted; return of 60 admitted; receipt holds 60 |
| G7 | A2's first shape (60 and 40 plain under the undo) on a deposit | code refused; without it admitted |

Why nothing can hide: -23 requires the named row to be a non-nsf row directly under the posting entry and the entry wholly taken back; -23's cap holds at every entry on a row's path, so with a named row of the full amount standing and childless, every sibling subtree nets to zero. The named row is then the only money standing. I found no legitimate end refused other than the route the plan names.

### N5 (executed). One-statement and two-session shapes.

One statement (payment posted, one childless 100 under the entry):

| Probe | Statement | Result |
|---|---|---|
| A6a | an unreferenced CTE inserts an undo of 40 beneath the named row; the main UPDATE ends with the code | 23001 (-23: the row gives money back to a payment that has ended) |
| A6b | the same, the UPDATE reading the CTE | 23503 (-23: the entry is no longer wholly taken back) |
| A6c | the coded end in a CTE, the main INSERT writes the undo | 23503 |
| A6d | the same, the INSERT reading the CTE | 23001 |

Afterwards the payment was still posted with nothing beneath the row.

Two sessions, committed fixtures, both as `tally_app`. The pair of rows is chosen to net to zero (an undo of 40 beneath the named row, and 40 taken again beneath the undo, one INSERT), so that -23's own check passes and only the new condition can refuse:

```
Race 1: the rows first (transaction held 4 s), the coded end second
  B waited (02:56:02 → 02:56:06), then 23514 "…and nothing is filed beneath it"   payment stays posted
Race 2: the coded end first (held 4 s), the rows second
  A waited, then 23001 "gives money back to payment …, which has ended"            payment reversed R01, nothing beneath
```

So the new read is ordered by the payment's lock, as the new comment says. No race in `suspense-24.sh` has this zero-net shape (SU13's mixed tree is refused by the share alone); it is not needed for the mirror, since the lock is -23's and pinned.

### N6 (read). The brief's remaining questions.

- **-23 and -27:** r12 adds no read of theirs and removes one (`ledger_entry_remaining` in the code rule); it reads `account_ledger` directly, which `tally_app` may. Nothing they see changes.
- **Invariants:** clean after the battery and the races; the two changed bodies are re-pinned (`c2857f86…`, `570a5ea9…`, the second a comment-only change).
- **Known limits L1–L6:** none blocking.
- **For the application contract at the mirror** (unchanged from round 11): after an end without a code, the whole misposted share goes back to the receipt and the bank's part is recorded there as `bank_returned`; until that second row is written the receipt shows the bank's part as held.

## The three questions put to me

1. **Is the new code rule right in every shape?** Yes, in every shape I could build (N4, N5): another level down, an nsf row beneath, a negative row beneath, a later row, a named row typed nsf, another payment's row, one statement, two sessions. Nothing legitimate is refused besides the named route, and a re-take filed under the posting entry keeps the code (A11).
2. **Is S4c now a sound oracle?** For the nested bounce, the link-only bounce, later-dated payments, a share returned and paid again, and deposits: yes (my G2, G3, G6, G7 and A-fixtures all read 100 of 100 at every date). One shape it gets wrong while the patch is right: a pending payment whose posting entry is written (N1). It fires under mutation (N2).
3. **Do the deposit fixtures and M171–M175 test what they claim?** Yes: five walks name `'deposit'`, each has one mutation, each is caught alone at its named check (executed). D2 carries more than one fact (N3).

## The brief's questions

1. **Closed?** Every round-11 finding of mine, and the earlier ones. The patch implements the design and the rulings within L5 and L6.
2. **Paths around a rule.** None found.
3. **-23 and -27.** Unchanged (N6); trigger orders are by name and right.
4. **Concurrency.** The new read is under the payment's lock (N5, both orders); races reproduce (29).
5. **Invariants.** Clean; pins current.
6. **Tests.** No check weaker than its label among the r12 additions, with the remarks in N1 to N3.
7. **L1–L6.** None blocking.
