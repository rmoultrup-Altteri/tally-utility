# v5.4.2-16 review round 4: findings and dispositions

**Frozen:** patch `a0b43c01`, battery `15eea127`. Brief: `review-brief-16-r4.md`. Reviews: `review-r4-{opus,fable,codex}.md`.
**Verdicts:** **Opus "ready", Fable "ready", Codex "not yet"** (one blocking item, B1). Every round-3 fix held under all three. Opus and Fable attacked each one live: Opus tested a state with two rows, and Fable ran 90 probes and 17 extra mutations. Codex reviewed statically.

B1 was **reproduced on a clone** (`main16r4`, frozen r4 patch, TEMP revoked) before being accepted.

| # | Finding | Who | Disposition (deciding rule) |
|---|---|---|---|
| **B1** | A profile locks the state rows it saw, then checks containment against *any* row. A successor row committed while it waited is trusted unlocked. A later close of that successor does not wait for the profile, so the profile outlives every state row. Reproduced: S1 closed and S2 inserted in one transaction, the profile waits, S2 then closed while the profile is uncommitted; the profile commits open from 2021 against a state that ended in 2025. | Codex | **Integrity** (round 3's handshake held only for a fixed set of rows). The profile selects the row that covers it, share-locks **that row**, and re-reads **that same row**. If it no longer covers, the profile is refused ("closed while this waited"; the hint says to record it again). Races **R19** (successor committed meanwhile) and **R20** (a state of two rows, the covering one not first by id; Fable's XS); mutations M134–M135. |
| **S-own** | Owner type mixes who owns a system with what it distributes. `propane_piped` and `master_meter` are not owners, and a city-owned piped-propane system can be recorded only as one or the other. | Opus | **Frame shapes by migration cost:** law rows will key on owner type, so this is additive now and meaning-changing later. Sources in hand: NM 62-3-3(G)(2) takes in piped LPG while (E) still excludes a city's system; OH 4905.90(K) master-meter operator not a public utility; OH 5117.01(D); TX 121.211(d) "gas master meter operator" beside "operator of a gas distribution system". Owner types are now five. A new vocabulary, **`utility_system_kinds`** (distribution / piped_propane_distribution / master_meter, each listing the services it applies to), and a required **`utility_service_profiles.system_kind`**, checked against the profile's service. Case U6; mutations M141–M142. (This corrects inventory A1's "seven kinds of ownership": two are system kinds.) |
| **S-tax** | "In no city" has no place on the tax axis. For a premise in a city's ETJ, the only positive tax-axis record is Unincorporated Texas, whose meaning is "outside any ETJ", so the same row would mean two things depending on the axis. | Opus | **One meaning per row.** Extraterritorial and limited-purpose areas take the **tax axis too**. What each means for a tax is that tax's rule; Texas LGC 43.130 bars city taxes in a limited-purpose area, a tax-relevant fact. Case U7; mutation M143. |
| S-key | A key needs no letter or digit (a bare `§` passes); `§ 7.45` and `§7.45`, or `ILCS` and `ilcs`, are distinct keys; the en dash is refused. | Codex, Opus, Fable | **Shape enforced, spelling the loader's.** A key needs at least one letter or digit and takes no space after `§`. Canonical spelling, letter case, and an ASCII hyphen for a range are recorded as **residual R20**. Case U8; mutations M144–M145. |
| T | Test gaps. Codex: no negative distance; the "agreeing duplicates" case never queried its premise; no two-place agreement. Opus: mutations survive for a governed profile *with an end date* running past the close, the state row read on any date, and agreeing zones counted twice. Fable: M6b masked by the group exclusion (within and outside one place, XO); the state-lock loop over every row (XS); a no-op update of a place untested. | all three | Cases U1–U5, U9 and U10, each built so only its guard can refuse (U4 and U5 also check the refusing guard's message). Mutations M136–M140 and M146–M147. |
| T-attr | The mutation harness counted any `ERROR` without the target's `PASS` as caught, even an error from an earlier check, and ignored setup return codes. | Codex | **Checks narrower than their claim.** A battery catch now needs the target's own FAIL line, or the run stopping inside the target with every earlier check passed. A race catch needs its own `FAIL Rn` line. Setup failures are reported as SETUP-ERROR (a miss). |
| — | A membership of a place that does not exist was refused with a garbled message ("a  takes ;"). | Fable | Refused by name (`foreign_key_violation`, "place … not found"). Case U9. |
| — | M04, M31, M85, M94, M100 and M128 were anchored on code this revision changed. | (author) | Re-anchored to the same behaviour (M128 now widens both the selection and the re-read). |

**Notes (comment only, or no change):**
- **Within a place on one axis and outside it on the other, over the same days, is accepted** (Fable). This follows from D1. Now said in the memberships table comment.
- **A city's zone hides a county conflict under it** (Opus). By design: the refusals apply only at the answering level. Now said in the lookup's comment.
- **`jurisdictions.place_id` is a second "which city" answer, not reconciled with memberships** (Opus). Residual R3 covers it: it is the utility's own rate-area settings, not a premise fact.
- **The fictional-state fixture in rule-terms §9 is not seeded** (Opus). That belongs to rule-terms step 2 (CI golden scenarios), not to this patch.
- **Memberships are not checked against each other's parents** (Fable). By design; each is its own evidenced fact.
- **The loader should not write city time zones in Texas** (Fable). That is a loader rule. R2 already covers Texas loading.
- **Advisory locks can be probed or held by the app role** (Opus). Residual R13.

## Revision for round 5

Every item above is folded or recorded (residual R20).

The stricter attribution found two mis-aimed tests, both fixed before freezing: M98 is caught at J1 (J1b, a pointer at a closed place), not N9; and U10 used a place with an open citation, so the close floor refused before the edit rule could. It now uses a place with no citations.

**Verified on patch `24757cfc`, battery `3add58b7`** (frozen as `*-frozen-r5.sql`; clones with TEMP revoked):
- strict apply ×2;
- battery-16 **90/90** (group U covers round 4);
- races **R1–R20** (19 legs; R15 is the 25000 check inside R3–R6 and R8), each two-session leg with the second session itself observed waiting;
- mutations **146/146**, each caught **at its named check under the stricter attribution** (M134–M147 for round 4);
- regressions 28/58/41/116/3/99/6, and -13's X1.
