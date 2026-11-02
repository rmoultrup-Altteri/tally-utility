# Opus review: v5.4.2-23 r8

**Date:** 2026-11-02. **Reviewer:** Opus. **Verdict: not yet.**

r8 closes what round 7 found, in the shapes round 7 found it, and applies option A, K-10, Kyle's 10-30 answer and the 11-02 AC-44 decisions faithfully. Two blockers remain:
- **B1.** Money still comes back to an escheated credit, through the one path round 7 left unprobed: a refund's return stamped at its transaction's start (R17). The return commits after a take-back and after a sibling reissue's escheat, and moves the take-back's share off the escheated reissue. I ran it with real sessions, all tally_app, one act per transaction: the escheated reissue ends holding 10, and the utility can refund only 10 of the 20 it holds.
- **B2 (tests only).** With agree() narrowed to option A, nothing in the battery tests the per-side caps of the payment or the overpayment credit where they bind. Two cap-too-high mutations of my own pass all 390 checks. Under them the payment pays out 70 against its own 50, or the credit 50 against its own 30. This is N207's class, which r8 fixed for the reissue leg only.

## Setup

- **Frozen files.** All six md5s match the brief (executed).
- **Clone.** `rv23opus` from `tally` (TEMPLATE); TEMP revoked from PUBLIC, tally_app and tally_core right after; both read `f|f` (executed). Rebuilt once the same way after the race script's committed rows (they collide with battery fixture ids, as in r6).
- **Strict apply, twice.** Clean; the second run skipped on its marker, "already applied" (executed).
- **Battery.** 390 PASS, no FAIL, rolled back, 21 s after `VACUUM payments, customer_credits, account_ledger`; 23 s on a later run (executed).
- **Races.** `cash-23-frozen-r8.sh rv23opus`: 40 PASS, rc 0, 91 s; CR26 passes (executed).
- **Probes.** The files are in my scratchpad, not the repo:
  - The frozen battery with my probes appended before its ROLLBACK (history loads as the owner, draws as tally_app under `app.user_id`).
  - Two mutated copies of `check_cash_source`, created inside the battery's own rolled-back transaction.
  - One concurrent probe (J) on the race script's committed tenant, with real sessions.
  - One statistics probe.
- **Not run.** `ci.sh` and `mutations-23.py`, per the brief. I read N220–N226 and the runner's vacuum change.
- **Cleanup.** The clone is dropped and my files are removed from the container (executed).
- **Container note.** `docker ps` shows 2 `crystaldba/postgres-mcp` containers running. I did not touch them. `rv23fable` exists (Fable's clone).

Each claim is marked **executed** (run on the clone) or **predicted** (read from the code).

---

## Round-7 findings, item by item

| Round-7 finding | Status |
|---|---|
| **Opus B2, Fable B1, Codex B1.** With two holders of money beside a deficit, the covered one reads less than its caps admit. | **Closed by option A**, as Ryan decided. The comments now say what is true: the header, R17, R20, `overpayment_absorbed_as_of`, AC-44 and agree() (read). Q1–Q3 reproduce P2, P3 and G (executed in the battery). No position exceeds its caps, by construction (predicted): the cover only lowers a holder or lifts a deficit toward 0. **But** the narrowed agree() no longer tests the per-side caps: B2. |
| **Opus B1.** A give-back admitted onto an escheated credit while its restored money covers a deficit. | **Closed for H.** The give-back guard reads `customer_credit_own_remaining_as_of`: Q4 refuses 40, and Q4a admits 30, which only cancels K's deficit (executed). **Still reachable another way:** B1. |
| **Codex B2.** A refund of an escheated credit returned after the escheat hides its own money under the cover. | **Closed.** `enforce_escheated_credit_settled` reads the own side. Q5a refuses the return left on K; Q5b admits it carried to a reissue of 20; Q5c reads 50/0/20 (executed). |
| **Beyond the plan: the reissue sized on its credit's own side.** | **Right in direction, and it opens S1.** Sized on the covered position, Codex 02's reissue could not be made. On the own side it can. But the reissue's own *remaining* subtracts its own draws, so one statement that makes a reissue and draws on it is sized wrong (S1, executed). |
| **Opus S1.** The escheat move took the credit's lock without the payment's (D2). | **Closed.** The move to escheated of a family credit takes the payment's lock first (patch 2590–2596). CR26 passes (executed); the brief reports it deadlocks on r7. See N1 for the remaining row-lock order. |
| **Fable S1, Codex S1 (performance).** The family walks are plan-sensitive. | **Partly closed.** All four walks and `cash_source_draws` are pinned and in the invariant's list. Every recursive walk in -23 is now pinned (read: the 9 `WITH RECURSIVE` sites sit in 7 pinned functions). But under "pages present, 0 rows estimated" statistics, Z6 still takes 23 min 24 s, mostly inside the pinned functions (S2, executed). |
| **Codex S1 (Z6's positive control).** | **Closed.** Z6 now makes the 999th reissue with the deferred checks forced, refunds 1 from it, and fails on any other error (read; PASS executed). |
| **Fable S2, Opus N2.** A credit whose own money covers a deficit never closes. | **Closed as R24**, with AC-44's "netted, not dormant" note (read). |
| **Opus S2, Fable S5, Codex S2 (tests).** | **Closed for the named shapes:** P2, P3, G, H, Codex 02 (Q1–Q5d), D2 (CR26), N220–N226. **Gap:** B2. |
| **Opus N1 (999-deep timings).** | **Closed:** R21 records them (read). |
| **Opus N3 (AC-44).** | **Closed.** AC-44 now nets before an escheat report only where the state's rule allows (no rule row means report in full), and names -27's application to the shortfall as the record, never a billed charge (read). |
| **Codex S2 (`assert_cash_guard_invariants()` and the bound).** | **Closed:** the header no longer says the invariant compares the walkers (read). |

**Rulings.**
- **K-10.** The pool refused every excess I tried, including under both of my mutations (executed). The bounce's shortfall is never billed: AC-44 says so.
- **Kyle, 2026-10-30.** Applied within one payment. Across payments it is the core's, per AC-44.
- **Ryan, 2026-10-21 ("nothing comes back to an escheated credit").** Broken by B1.
- **Ryan, 2026-11-01 (option A).** Applied in the comments and agree(). The test gap in B2 follows from it.
- **Ryan, 2026-11-02 (AC-44, escheat netting per state; -27's row).** Applied in AC-44, R23 and R24 (read).

---

## Blocking

### B1. A refund's return stamped before a take-back moves the take-back's share off an escheated reissue (executed, real sessions)

**What happens.**
- Shares are read as recorded. A take-back falls first on what each credit *held at its instant*, the overpayment credit first, then the reissues in recorded order (`overpayment_shares`).
- A refund's return (the nsf row and the move to nsf) is stamped at its transaction's start. A return that began before a take-back and commits after it changes what the credit held at the take-back's instant. R17 accepts this and says "both readings are consistent".
- So the take-back can move, after the fact, from a later reissue to the overpayment credit. The later reissue's own side rises.
- If that reissue was escheated in between, nothing on the return's path looks at it:
  - `enforce_escheated_credit_settled` checks only the credit whose refund came back.
  - The give-back guard checks only give-backs.
  - The leaving move runs no recorded-order check against later rows under its payment's posting entry (`check_cash_order` is called only for draws and for rows under that entry).

**J (executed; tally_app, READ COMMITTED, one act per transaction, real `now()` stamps).**

Committed setup: payment 100; overpayment credit K 50; the payment's own 50 refunded; K's refund A of 20 posted; K's refund B of 15 came back and was reissued as R; K refunded its last 15. Reads: payment 0, K 0, R 15.

| Step | Session | Payment | K | R |
|---|---|---|---|---|
| T begins the return of A (18:53:01.10), then waits | T | | | |
| 10 taken back under the payment: K held nothing, so it falls on R (18:53:02.09) | S | 0 | 0 | 5 |
| R remits its 5 and is escheated: own side 0, admitted (18:53:02.65) | S | 0 | 0 | 0, escheated |
| T writes the nsf row and moves A to nsf, both stamped 18:53:01.10; commits | T | **0** | **10** | **10, escheated** |

- The share moved from R to K: `overpayment_shares` now gives the take-back to K.
- R's own side reads 10, on a credit already remitted.
- K refunds 10; 10.01 is refused. R refunds nothing (escheated). The payment refunds nothing.
- **The customer's money.** The utility holds 20 (100 − 10 taken back − 50 − 15 − 5 remitted). It can refund 10. The other 10 sits on a remitted credit, for good. This is the end state of my r6 B1 and r7 B1, reached through R17.
- On r7 the same path is open (predicted): the code on it did not change.

**Fix (direction).**
- Give every **leaving move** on a family the recorded-order check a draw already has. A refund of the payment or of a family credit leaving (voided, nsf, reversed), and a family credit's void, would be refused for retry (40001) when a row under the payment's posting entry was recorded after the move's stamp. That is `check_cash_order`'s arrival-entry leg, called from the leaving move under the payment's lock it already takes.
- The retry lands after the take-back, so the bank's return is still recorded; only its stamp moves.
- The shares as recorded then stay fixed once recorded. The escheat move, the give-back guard, the void's share check (Z5) and the reissue's size all already assume that.
- A credit's void needs it too (predicted). A reissue voided at t0 gives its money back to its predecessor at t0, so the predecessor held more at a later take-back. That moves the share off later reissues the same way.
- R17 should then say the return is retried, not stamped back.
- **Tests:** J as a race (CR27), the void variant, and a mutation on the new leg.

### B2. Tests only: the per-side caps of the payment and the overpayment credit are untested where they bind (executed)

**What happens.**
- Under option A, agree() checks that each line admits its position and refuses the pool plus a cent. It no longer checks what a line can pay.
- With one line holding money, the pool binds that line, so a per-side cap set too high cannot be seen.
- With two lines holding money, nothing pins either line's figure. Q1–Q3 check the positions and agree() only.
- r8 found this for one leg (N207, the reissue's share) and added Y7j2. The payment's leg and the overpayment credit's leg have no such check.

**Two mutations of `check_cash_source`, each created inside the battery's rolled-back transaction:**
- **mA:** the payment's cap subtracts the credit's share of a take-back twice (`l.amount - 2 * coalesce(x.absorbed, 0)`).
- **mB:** the overpayment credit's cap forgets its share (`… AND v_origin = 'refund_reissue'`), N207's mirror.
- **Both pass all 390 checks** (executed).

**They are observable (executed).** Shape S: payment 100, K 50, 20 taken back (K absorbs it). Payment 50, K 30.

| Refund | Unmutated | mA | mB |
|---|---|---|---|
| payment 50.01 | refused | **admitted** | refused |
| payment 70 | refused | **admitted** | refused |
| K 30.01 | refused | refused | **admitted** |
| K 50 | refused | refused | **admitted** |
| agree() on S | pass | pass | pass |

Under mA the payment pays out 20 of K's money; under mB, K pays out 20 of the payment's. The pool holds the total each time.

**Why it is blocking.** The per-side caps are the guard that decides what each line can pay, which option A still promises. The brief's "225 of 225" overstates coverage: two cap legs are untested. r8 treated N207, the same class, as a must-fix before freezing.

**Fix (direction).**
- agree() should pin each active line's payable figure: a refund of `min(its own side, the pool)` admitted, and that plus a cent refused.
  - For a credit, the own side is `customer_credit_own_remaining_as_of`. The caps compute theirs inline, so this is a real cross-check.
  - For the payment, compute it in agree() as the payment's cap does: its amount, less its draws, less the rows under its posting entry net of the family's shares.
- That restores the check round 7's agree() had, within option A. Every agree() site then tests the caps in every shape.
- Add mA and mB as mutations.

---

## Should fix

### S1. One statement that makes a reissue and draws on it is sized against the reissue's own draws (executed)

**What happens.**
- The size check runs in the reissue's AFTER INSERT row trigger. It now adds the credit's own remaining to the **reissue's own remaining**, which subtracts the reissue's draws.
- r7 added the reissue's issued instead, which does not count its draws (predicted from the r7 diff).
- In a single statement, a data-modifying CTE that inserts the reissue and a refund or application of it, the AFTER triggers fire at the statement's end. The reissue's check then sees its own draw.

**P1 (tally_app, executed).** K 20; K's refund of 20 comes back (K reads 20).
- One statement, reissue 20 plus a refund of 5 from it: **refused**, "it carries what came back (20.00) as far as it is what is left on the credit (15.00 before it)".
- One statement, reissue **15** plus a refund of 5: **admitted**. The returned 20 is carried as 15. K is active, so its 5 is not stranded; on an escheated credit the deferred settlement check would refuse it at commit (predicted).
- Two statements, reissue 20, then the refund of 5: admitted; R reads 15.

**Fix.** Read the reissue's own *issued* side: its amount less its share as recorded. That is the r7 term without the cover. Add P1 to the battery.

### S2. The pins do not protect the 999-deep line in the statistics state autovacuum leaves (executed)

**Two statistics states, both found on my clone:**
- After a manual `VACUUM` of the emptied tables: 0 pages, 0 rows. The planner assumes a small table of rows, and the battery runs in 21–24 s (executed, three runs).
- After autovacuum runs between rolled-back batteries: 48–78 pages, 0 rows estimated (seen at 18:38 UTC). The planner believes the tables are empty. In that state my mutation-B run sat in Z6 for over 9 minutes before I cancelled it.

**Reproduced deliberately (executed).** Inside the battery's rolled-back transaction I set `reltuples = 0, relpages = 60` on `payments`, `customer_credits` and `account_ledger`. I first locked the three tables against autovacuum: my first try deadlocked with autovacuum on the pg_class rows, an artifact of the method.
- The battery up to Z6 then took **1,444 s**, against 23 s. Z6 alone (the 999th make plus a refund of 1) took **23 min 24 s**. All 366 checks to that point passed.
- Self-time by function:

| Function | Pinned? | Calls | Self-time |
|---|---|---|---|
| `overpayment_family` | yes | 15,873 | 754 s |
| `cash_source_draws` | yes | 9,299 | 329 s |
| `customer_credit_draws_as_of` | **no** | 2,904 | 323 s |

- `is_platform_admin` and `get_user_tenant_id` were each called about 7.9 million times (15 s and 12 s): row security is evaluated per row read.
- So turning off sequential scans, hash joins and merge joins does not save the walks when the planner believes the tables are empty. The likely cause (predicted) is index scans that read everything and filter row security per row. `customer_credit_draws_as_of` is on the path and not pinned.

**Why it matters.** Real tables are not empty, and real lines are 1–3 deep, so production is not at risk (predicted). But r8's claim (brief item 5, R21: "the depth no longer depends on the statistics") is not true. CI or the mutation runner can hit this state whenever autovacuum runs on an emptied table between runs. That is what happened to Fable in r7, and to me here.

**Fix.**
- Make the runner's and CI's vacuum produce the good state *immediately before* each run. The runner already vacuums; ci.sh should too.
- Correct R21's sentence.
- Optionally pin `customer_credit_draws_as_of`. Look at the row-security cost inside `overpayment_family` before claiming depth is independent of statistics.
- Not blocking on its own.

### S3. Comments

- `enforce_customer_credit_immutable`'s COMMENT does not mention r8's lock on the escheat move. It still lists the payment's lock for the void only (read).
- R17 says "both readings are consistent". J shows they are not, once a decision (an escheat) is taken between them.

---

## Notes

- **N1 (predicted). Lock order with the escheat move's new lock.**
  - A status move takes its own row first (the UPDATE locks it before the BEFORE trigger runs), then the payment's advisory lock, then the credit's.
  - The draws, the give-back, the take-back, the bounce, the return and the reissue take the payment first and lock no credit row.
  - So among single acts I found no cycle (CR25 and CR26 executed).
  - The one cycle is between two status moves of the same family credits in multi-act transactions. Example: A remits and escheats K and then K2 in one transaction, while B escheats or voids K2 alone. B holds K2's row and waits on the payment; A holds the payment and waits on K2's row.
  - The void had this since r7, and the header's "one act per transaction" rule covers it. Moving the same credit two ways at once fails anyway.
- **N2 (predicted). The own-side helper reads what the per-side cap reads.**
  - Both use the amount, the shares as recorded and the same draw sets: applications, refunds pending or posted, reissues not voided, donations, and remittances.
  - The helper reads at the last date and now; the cap reads every date from the draw's on.
  - Nothing legitimate is refused that I found. Q4a admits a give-back that only cancels a deficit (executed). Z4f admits the escheat of a credit that truly holds nothing (executed in the battery). A bank return of an escheated credit's refund is carried to a reissue (Q5b, executed).
  - In the one-statement shape, the reissue's size refuses the right figure (S1).
- **N3. Can the reissue carry more than the credit's own money, or strand any?**
  - It cannot carry more: the figure is the credit's own side before it (predicted).
  - In two statements it strands nothing (Q5b executed).
  - In one statement it can carry less (S1, executed). On an active credit the rest stays drawable on the credit.
- **N4. Residuals.**
  - R17 is blocking as worded (B1).
  - R22, R23 and R24 are fair. R24's money is right, and AC-44 tells the core how to read it.
  - R1–R16 and R18–R21 are unchanged and not blocking.
- **N5. Mutations N220–N226 read.** Each new leg has its mutation at a check that sees it. N223's relabelling to Z4a is right: every escheated check reads one function. The runner's vacuum now covers `payments` and `customer_credits`. B2's two mutations are the gap.
- **N6. Roles and isolation.** r8 adds a STABLE helper granted to tally_app and tally_core, and one lock. Every new read runs inside guards already pinned to READ COMMITTED. J needs no role or isolation trick: every writer was tally_app at READ COMMITTED.

## Probe record (executed)

- **Battery** 390/390 in 21 s and 23 s. **Races** 40 PASS in 91 s.
- **mA, mB:** 390/390 each. Shape S as in the table.
- **J:** setup 0/0/15; after S's two acts 0/0/0 with R escheated, share on R; after T's commit 0/10/10, R escheated, own 10, share on K. Refunds: K 10 admitted, 10.01 refused; R 0.01 refused (escheated); payment 0.01 refused.
- **P1:** one statement 20 refused ("15.00 before it"), one statement 15 admitted, two statements 20 admitted.
- **Statistics:** with 0 pages and 0 rows, the whole battery took 21–24 s. With 60 pages and 0 rows estimated, the battery to Z6 took 1,444 s, and Z6 took 18:57:11 to 19:20:35 UTC. Function times as in S2.
