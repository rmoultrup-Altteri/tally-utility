# v5.4.2-16 review round 3: findings and dispositions

**Frozen:** patch `c49b1ec5`, battery `af1013f9`. Brief: `review-brief-16-r3.md`. Reviews: `review-r3-{opus,fable,codex}.md`.
**Verdicts:** all three "not yet". They converge on the same blocking item, a distance of `NaN`. Codex also blocks on the state close, which Opus and Fable rate should-fix. Every round-2 fix otherwise held. Opus and Fable attacked each one live, and Codex reviewed each statically.

Every finding below was **reproduced on a clone** (`main16r3`, frozen r3 patch, TEMP revoked) before being accepted. The exception is the mutation gaps, which the new mutations re-prove.

| # | Finding | Who | Disposition (deciding rule) |
|---|---|---|---|
| **B** | `distance_miles = 'NaN'` passes `> 0` (NaN sorts above every number), is stored, and is returned; `NaN > 3` is true. Round 2 settled "distance must be finite", but the fix never landed. | **all three** | **Integrity** (a lookup answers instead of refusing). `AND distance_miles <> 'NaN'` in the outside leg. Cases T1a–c, mutations M112–M113. |
| **S-d′** | A state place closes under the profiles it governs: the close floor counts profiles by owning place only, and the profile insert takes no lock on its state. Afterwards the profile lookup answers for a state that has ended. | Codex (blocking), Opus, Fable | **Integrity** (round 2's rule held only at insert). The close floor gains a leg for a state's own profiles (unvoided, running past the close). The profile insert share-locks every place of its state, then re-reads the range. Lock order: state place, then owning place. Cases T2a–c, T10; races R13–R14; mutations M114–M117, M128. **Residual R19:** a state place is not succeeded under its profiles; a profile lies within one state row. |
| **S-tz** | The time-zone conflict check sees only places that carry a zone. El Paso County (Mountain) on one axis plus Harris County (no zone loaded) on the other answers `America/Denver`. | Opus (Fable tried the case with and without facts and found it held; reproduced here: it does not) | **Integrity** (a partial load must refuse, not answer). Every place the premise is within whose kind can carry a zone is a candidate. The answering level is the most specific one where some candidate has a zone. At that level, a candidate with no zone refuses (`no_data_found`), and two zones refuse (`cardinality_violation`). A level with no zone at all falls through, so a city with no zone answers by its county. Cases T3a–d (including Codex's two-city annexation window and its clearing by a void); mutations M118–M119. |
| **S-key** | `fact_key` is checked with `btrim`, which strips U+0020 only. Tab, newline, no-break space and doubled interior spaces all make distinct keys. | all three | **Integrity**, by the standing rule *blank checks whitelist alnum*. A key is citation-shaped: it starts with a letter, digit or §; then letters, digits, `. , : ; ( ) / ' _ - §`, and single spaces each followed by a non-space. Cases T4a–d; mutation M120 (M103 re-anchored). |
| **S-err** | `assert_place_read_committed` raises `40001 serialization_failure`. Drivers retry that automatically, at the same isolation, and so would loop forever. | Fable | **House pattern.** `tu.sql`'s four READ COMMITTED guards raise `invalid_transaction_state` (25000); this one now does the same. Races R3–R6 and R8 require SQLSTATE 25000; mutation M121. (The draft -15 has the same flaw and is being rewritten.) |
| S-uninc | "One unincorporated area per state" (round-2 disposition S-c) is not enforced: a second Texas area is accepted. | Opus, Codex (notes) | **The disposition claimed it**, so it is enforced: `places_one_unincorporated` (an exclusion on state and range). Case T5; mutation M122. |
| T | Mutations surviving the battery: voided owning profile counted by the close (X1); rate `<=` its upper bound (X3); pointer at a place not yet begun (X4); `no_repeat` counting voided rows (X9; the commonest void, the same place with a corrected date, was untested); state range `&&` for `@>` (X15); evidence dated today refused (X19); distance `>= 0`; `evidence_date` nullable. Codex: no NaN or whitespace case; no exclusion races; the race harness's wait check counted *any* waiting session. | all three | Cases T6–T12, one per gap, each built so only its guard can refuse. Mutations M123–M133. Races **R16** (two counties racing the exclusion), **R17** (two overlapping profiles) and **R18** (a profile racing its owning place's close). Every leg's wait check now watches **the second session itself** (`application_name = 'race16_b'`). |
| — | M54, M57, M82, M83 and M103 anchored on code this revision rewrote. | (author) | Re-anchored to the same behaviour in the new code. |

**Notes (no change, or a comment only):**
- **A city's zone outranks its county's** (Opus, Fable). Kept: the more specific place answers by design. This is now said in the lookup's comment.
- **Void after close is accepted** (Fable N1). Kept: a row wrong from its first day is wrong whether or not it has ended. Said in `place_citation_close_or_void`'s comment.
- **An ORM echoing the whole row trips the close rule** (Fable N2). Said in the same comment. For the core: update only the closing column.
- **"Today" for evidence follows the session's time zone** (Opus). `CURRENT_DATE`, as every -1x guard uses it. No change.
- **Evidence dated year 1; population 3.5 or 1e400** (Opus, Fable N4). The harmless side; no source bounds them. No change.
- **Texas is seeded from 1900, so a county dated from its creation is refused** (Fable N5). Added to residual R2: the loader dates places from 1900.
- **A pointer at Unincorporated Texas is accepted** (Fable N6). Round-2 N1 stands: a kind list arrives when R3 is done.
- **`closed_by` / `voided_by` are not checked against the tenant** (Fable N7). RLS makes it moot for `tally_app`; this is -05's convention.
- **`US/Central` is refused** (Fable N8). The build lacks the backward link. Loaders write canonical ids.
- **Codex's S-c note**, that "one per state" was a convention only, is now enforced (above).

## Revision for round 4

Every item above is folded or recorded (residual R19).

**Verified on patch `a0b43c01`, battery `15eea127`** (frozen as `*-frozen-r4.sql`; clones with TEMP revoked):
- strict apply ×2;
- battery-16 **80/80** (group T covers round 3);
- races **R1–R18**, each two-session leg with the **second session itself** observed waiting; R15 is the 25000 check inside R3–R6 and R8;
- mutations **132/132**, each caught at its named check (M112–M133 for round 3; M54, M57, M82, M83, M103 re-anchored);
- regressions 28/58/41/116/3/99/6, and -13's X1.
