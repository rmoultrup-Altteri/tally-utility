# Review Brief — v5.4.2-10, ROUND 4 (confirmation): lineage-wide uniqueness

**File:** `sql/v5.4.2-10-snapshot-coordinate-binding.sql` — **     935 lines, md5 `2d0ece3cc83c1fd936984a39987a8c8e` — FROZEN.** Round 3 was `2530daf7…` (889 lines; both verdicts "sound enough to mirror" with one shared finding).

## The one change since round 3
Both reviewers found the same gap independently (Fable LOW-1, Codex MEDIUM-HIGH): "one live correction per replaced bill" was scoped per HOP, so with A void, B (corrects A) void, C corrects B live, a D correcting A directly still landed. Now: **one live snapshotted correction per LINEAGE** — new `invoice_lineage_root(uuid)` walks `replaces_invoice_id` to the bill that replaces nothing (bounded at 64 hops; invoker rights, RLS applies); the check runs a recursive CTE over every descendant of that root at any hop and refuses if any other non-void correction carries a snapshot. The **lineage root's row is the mutex** (validator UPDATEs its `updated_at` first, then the replaced bill when it is not the root). Lock order is now invoice → lineage root → replaced bill → target → run, and the header states Fable's LOW-2 rule (a transaction touching a void bill and its targets edits the bill first). Nothing else changed.

Battery **56 green** (new F30a/b/c: correction of a void correction lands; correcting the root while that stands is refused with the lineage message; root walk c211 → c209 → c001) on clean and pre-seeded applies; all nine live shapes re-run green (`races/*-r4.out`).

## Attack this (confirmation)
1. Your chain repro against the new hash (Fable `r3-02-chain.sql`, Codex's A/B/C/D) — D must be refused; and the legal continuation (void C → D lands) must work.
2. Sideways lineages: two corrections of A where the first is void and the second live, then a correction of the void first (grand-child of A via a dead branch) — refused? Should it be? (Author's intent: yes, one live bill per lineage, whichever branch.)
3. Root-walk edge cases: a `replaces_invoice_id` pointing at another tenant's bill mid-chain (RLS ends the walk early — is the resulting root the right mutex?), a non-correction with `replaces_invoice_id` set (credit memo reversing a bill) inside the chain — does it count, should it?
4. The root mutex vs the replaced-bill mutex: deadlock shapes when the root ≠ replaced bill (two writers on different hops of one lineage), and the operator order rule.

Same DBs and paths as before (`s10c` pristine with revision 4; `s10` race fixtures; `s10b` pre-seeded). Report: hash; findings with repro; verdict. Keep it under 4000 characters.
