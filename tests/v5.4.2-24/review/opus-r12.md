# Opus review: v5.4.2-24 r12 (unmatched cash and agency pledges)

**Date:** 2026-11-24. **Reviewer:** Opus. **Brief:** `review-brief-24-r12.md`, md5 `64cf3366ec3a915300c68edfab3e3ba2`, which matches its `.md5`. I read the r12 plan, `r11-to-r12.diff`, my own r11 review, and the -23 guards the new rule leans on (`enforce_payment_immutable`'s cause check, `ledger_tree_ids`). I read no Fable or Codex file and none of their probes.

**Verdict: ready.** Nothing is blocking. Every round-11 finding is closed. I found no way to hide a misposted part under a coded `reversed` in any shape the brief names. The born-pending-or-voided rule holds as the owner, as a superuser in replica mode, and through COPY. Both orders of a race against the new "nothing filed beneath" clause serialise on the payment's lock and refuse the second writer.

- **S1 (executed):** S4c, the battery's conservation check, still reads a payment's pending state from its status now, not at each date. Two legitimate shapes the patch gets right break the oracle. The battery has neither shape, so S4c passes today. This is a test-oracle fix and does not need another round.
- **N1 (executed):** a posted payment whose posting entry is dated after its payment date shows its money nowhere on the days between. This is a variant of the r11 note about pending payments, for the mirror's contracts.
- **N2 (executed):** one race leg (SU2b) failed its "seen waiting" check on the first run under load. A fresh clone passed 29 of 29.
- **N3 (predicted):** S4d is satisfied by construction.

## Hashes and reproduction (executed)

- All six frozen md5s match: patch `37630681…`, battery `96b21ecd…`, races `360dea4d…`, mutations `87d1bec0…`, ci diff `ec30f743…`, r11-to-r12 `ecb5feb6…`. The live patch is byte-identical to the frozen copy (`cmp`).
- Clone `rv24opus` from `TEMPLATE tally` (which carries -30). I revoked TEMP from PUBLIC, `tally_app` and `tally_core` right after creation. The strict apply (`search_path=''`, `check_function_bodies=on`) is clean, rc 0. The second run prints "already applied (suspense_receipts exists); nothing to do".
- `battery-24-frozen-r12.sql`: **352 PASS, 0 FAIL**, rc 0.
- `suspense-24-frozen-r12.sh rv24opus`: the first run gave 28 PASS and 1 FAIL (SU2b: "session B was never seen waiting on a lock"; see N2). I dropped the clone, re-cloned, re-applied and re-ran: **29 PASS**, rc 0.
- Not run: `ci.sh`, `mutations-24.py`, and -25/-26 beside -24. For those I rely on the author's 61/61 and 169/169. I checked the mutation anchors statically instead (section 3).
- The clone is dropped (`pg_database` count 0), and the container's `/tmp/opus-*` files are removed.

## 1. Round 11's findings

| Finding | State | Evidence |
|---|---|---|
| Fable r11 B1: a bank code was admitted over rows filed beneath the named row's undo | **closed** | P23, P23b to P23d pass. I ran races RA and RB (section 2). |
| Fable r11 S1: a receipt payment could be born posted | **closed** | O7c passes. My own probes (executed, as the owner): a superuser load under `session_replication_role = replica` was refused (`is born posted … load it pending`). COPY FROM a CSV was refused with the same message. The rule is now `NOT IN ('pending','voided')`, and since `refunded` is not a status (Ryan, 2026-10-21), that is the whole set. |
| Fable S2, Opus S1, Codex N3: no deposit fixture | **closed** | Fixtures Rd1, Rd6 and Re1 (D1 to D8, D4b) pass. M171 to M175 each change exactly one of the five walks that name `'deposit'` (section 3). |
| Codex S1, Fable N1, Opus N2: S4c not a general oracle | **closed as reported** | The nested bounce (P24) and the bounce with no reference (P24b) pass. S4c now walks by link once, reads every date, and covers every receipt. One new gap remains: S1. |
| Opus r11 N1: lock-order comments | **closed** | The comments are at both places (`enforce_payment_suspense_pledge`, `enforce_ledger_suspense_posted`). |
| Opus r11 N3, N4 (mirror contracts) | **recorded** | The r12 plan's "Notes taken". |
| r10 and earlier | **still closed** | Battery 352 and races 29 pass. r12 changes only the code clause, the born rule and comments, plus the invariant's two new body hashes. |

**Design and rulings:** r12 changes nothing in CI-053's resolution paths, CI-056's readers or `cash_money_agency`, so my earlier answers stand. The stricter route the plan names is a whole reversal undone and taken again beneath the undo. It now ends with no code: its money comes back to the receipt, and the bank's part is recorded there as `bank_returned`. CI-053 is still met on that route, and P23b and P23c show the 60 held.

## 2. Is the new code rule right in every shape? (brief question 1)

The rule: a coded `reversed` with a share above 0 needs the share to be at least the payment, and the named row itself to be at least the payment with no row filed beneath it. It works together with -23's cause check, which I read in the clone. For `reversed`, -23 requires the named row to be non-nsf, a **direct child of the posting entry**, with the posting entry then having nothing left. So the named row cannot sit deeper in the tree, and it cannot be an nsf row.

I ran every probe below as `tally_app`, in one transaction over the battery's fixtures, rolled back. Each probe used its own ids.

| Probe | Shape | Result |
|---|---|---|
| Q1 | whole plain row c (100) directly under the posting entry, then a negative sibling of -30 | refused 23514 by -23: "a reversal has the opposite sign of the entry" |
| Q1b | the same, a further plain sibling of +30 | refused 23514 by -23's tree cap: "would come to 130.00, outside 0 to 100.00" |
| Q2 | nsf 40 (03-11), its undo -40 (03-12), whole plain c 100 (03-13); coded `reversed` naming c | **admitted**, which is right. Held 0, due none, and S4c's formula for this receipt holds on every day from 03-09 to 03-20. |
| Q2b | after Q2's end, a plain +50 under the posting entry | refused 23514 (cap, 150) |
| Q2c | after the end, c undone | refused 23001 ("gives money back to payment …, which has ended") |
| Q2d | after the end, a re-take of 40 under the nsf row's undo | refused 23514 (cap, 140) |
| Q3 | coded `reversed` naming an nsf row (all nsf) | refused 23503 by -23 ("a ledger row (not nsf) reversing its posting entry") |
| Q4 | one statement: a CTE inserts c's undo and a re-take of 100 under the posting entry; the main UPDATE ends coded naming c | refused 23001 (the CTE's rows land after the move) |
| Q4b | the UPDATE in the CTE, the two rows in the main INSERT | refused 23514 ("… and nothing is filed beneath it") |

**Why no part can be hidden.** The named row c is a direct child of the posting entry and is the whole payment, and -23's cap holds the tree's net take-back between 0 and the payment. So the net of every other branch is 0. Any money another branch took was given back inside that same branch. There is nothing left for the code to mislabel. A row added after the end is refused either by the cap or by -23's "ended" guard (Q2b to Q2d).

**Races (executed, committed fixtures on the race tenant, two sessions, B watched in `pg_stat_activity`):**
- **RA:** session A inserts an undo of c and a re-take under the posting entry, then holds. Session B ends the payment coded naming c. B was seen `Lock/advisory`, blocked by A. After A committed, B was refused with "… and nothing is filed beneath it". The payment stays `posted`.
- **RB:** session A ends coded naming c and holds. Session B inserts the same two rows. B was seen `Lock/advisory`, blocked by A, and then refused 23001 ("gives money back to payment …, which has ended"). The payment is `reversed R01`.

So the new clause's read is ordered by -23's payment lock in both directions, as the new comments say.

**Is anything legitimate now refused, other than the plan's route?** No. I checked these shapes:
- A whole row with fully undone siblings: admitted (Q2).
- A whole reversal undone and re-taken whole directly under the posting entry, naming the re-take: admitted (r11 E2b, unchanged). Naming the first row is refused, and should be.
- Splits into several plain rows: refused, as before (P17).
- An all-nsf tree: the clause does not apply, because the share is 0.

## 3. Do the deposit fixtures and M171 to M175 test what they claim? (brief question 3)

I imported the frozen mutation list, read only, applied each mutation to the frozen patch text and diffed the result. The runner's `rep()` asserts that each anchor is unique. Each of M171 to M175 changes exactly one line, in a different function:

| Mutation | Line | Function | Named check |
|---|---|---|---|
| M171 | 968 | `suspense_misposted_share` | D2: `share = 60` |
| M172 | 998 | `suspense_untyped_take_back` | D8: the end must be refused |
| M173 | 1029 | `enforce_ledger_suspense_posted` | D7 |
| M174 | 1146 | `enforce_suspense_disposition` (the return's date walk) | D4b |
| M175 | 1529 | `suspense_misposted_share_as_of` | D2: the `due` strings |

These are the only five places that name `'deposit'` (grep). M170 changes only line 810.

Reading each check against its mutation (predicted):
- D2 checks both the share (M171) and the due list at two dates (M175, through the as-of share), so one check catches both mutations for different reasons.
- Under M172, Re1's end passes -23 (the posting entry's remaining is 0), so D8 fails, as intended.
- Under M174, the date walk finds no rows. The 03-11 return then passes, because the share on 03-11 is already 60, so D4b fails, as intended.
- The deposit fixtures sit before any earlier check that would see a deposit, so the first failure is the named one.
- The re-pointing of M118, M129, M138 and M143 to D2 and P24b is consistent: each of those mutations breaks the share or the due list, which D2 and P24b now read first.

## 4. Is S4c a sound oracle? (brief question 2)

S4c's tree is the patch's own tree: the root is the posting entry, it walks down by link, and each row is counted once. The nsf flag sticks from the first positive nsf row downward. I attacked it with Q2 (an undone nsf sibling beside a coded whole row) and it held on every date. The bank's part and the coded share net correctly.

**S1 (executed): two shapes the patch gets right and S4c gets wrong.** S4c's pending term is `p.status = 'pending' AND p.payment_date <= d`, with the status read now.

| Probe | Shape | S4c's total |
|---|---|---|
| Q5b | a pending receipt payment whose posting entry is already inserted (the state `post()` passes through, and one a load can leave; -23 admits it) | 200 on every date from the entry's date (03-12 to 03-20): the pending term and `payment_position_as_of.received` both count the 100 |
| Q5c | the same payment moved to posted, with its posting entry dated 03-12 and its payment dated 03-10 (-23 does not tie the entry's date to the payment's) | 0 on 03-10 and 03-11: the status is posted now, and the entry is not yet dated |

The battery has neither shape, so S4c passes, but its label ("a pending payment's money counted") claims more than it checks.

The fix is in the battery only: count a non-voided payment's money as pending at date d when `payment_date <= d` and its posting entry is not dated on or before d. In other words, use `amount - sum(-posting entry dated <= d)` in place of the status. Add Q5b and Q5c as fixtures. No patch change and no new round are needed.

**N1 (executed, for the mirror's contracts).** In Q5c the patch's readers show the receipt holding 0 and the payment receiving 0 on 03-11, so the 100 is on no list for those days. This is the same gap as my r11 N3 (a pending receipt payment appears on no aging list): it is -23's reading of a payment not yet posted on the ledger. Record it in the same contract line, as "or posted with an entry dated after its payment date". It does not block -24.

**N3 (predicted).** S4d checks that every receipt has `received_on <=` the newest ledger date. But S4c's date set already includes every receipt's own `received_on`, so every receipt is read at least on its own day whatever the ledger holds. S4d cannot fail in any shape where S4c would skip a receipt. It is harmless, but it does not guard what its label says. A real guard would count the receipts S4c read: (receipt, date) pairs with `received_on <= d`, by distinct receipt.

## 5. Other questions in the brief

- **Paths around earlier rules, -23's and -27's properties, invariants, L1 to L6:** r12 touches none of their code. The battery (352) and races (29) re-pass. The invariant pins the two new body hashes (`enforce_payment_suspense_pledge @c2857f86…`, `enforce_ledger_suspense_posted @570a5ea9…`), and the patch's tail ran it clean in the strict apply. My r11 answers stand.
- **Concurrency:** the new clause is ordered by the payment's lock (RA and RB above). The born rule is insert-only and reads no shared state.
- **N2 (executed):** the first run of SU2b failed only its waiting check ("never seen waiting"). B's outcome was not reported as wrong. A fresh clone passed 29 of 29. The monitor polls 10 times at 0.15 s after a 1 s sleep, which can miss the wait when the host is loaded (three reviewers were running at once). This is not a patch defect. If it recurs in `ci.sh`, lengthen the poll window.
