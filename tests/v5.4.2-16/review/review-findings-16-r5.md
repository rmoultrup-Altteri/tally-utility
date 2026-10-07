# v5.4.2-16 review round 5: findings and dispositions

**Frozen:** patch `24757cfc`, battery `3add58b7`. Brief: `review-brief-16-r5.md`. Reviews: `review-r5-{opus,fable,codex}.md`.
**Verdicts:** **all three "ready"**, with no blocking item. Every round-4 fix held: Opus and Fable attacked them live (Fable ran about 60 probes plus 5 extra two-session legs), and Codex reviewed them statically. Opus's review shows `__HARNESS__` where its own mutation tally would go; its run stopped before finishing. Its ten hand mutations are reported in full.

There was no further review round. This revision folds the should-fixes and one modelling decision by Ryan. The only guard changes are the profile's uniqueness rule and lookup (Ryan's decision) and two refusal messages. Everything else is tests, wording and residuals.

| # | Finding | Who | Disposition (deciding rule) |
|---|---|---|---|
| **SF1** | One system kind per tenant, service and state: a utility running a gas distribution system and a piped-propane system in one state cannot record both. Reproduced by Opus and Fable. | Opus (settle now), Fable (state as a residual) | **Ryan, 2026-10-07: settle now** (Opus's option). The reviewers differed on the migration cost, so it went to Ryan. `system_kind` joins the profile exclusion, and `utility_service_profile_as_of` takes the system kind (the old 4-argument signature is dropped). Which system serves a premise is **residual R21**, a service-point fact added later. Cases V1–V2; mutations M148–M150. |
| S-own′ | "Municipal" is defined as "owned **or operated**", while LA 45:850 turns on "owned by". A nonprofit appointed by cities is municipally owned (TX 101.003(8)). The special-district text invites a public trust or gas association to be a place. Jointly owned systems have no shape. | Codex, Opus | **Wording plus a residual.** Owner type means ownership, not operation. A nonprofit or public trust acting for a city is `municipal`, with the city as owning place (TX 101.003(8); OK 60 O.S. 176). Special districts are those with territory of their own. **Residual R22:** one owning place even for joint ownership; operator-only or leased-out systems (AR 23-4-201(b)), NM gas associations, IL public institutions of higher education and KS townships each become a vocabulary row when a customer has one. |
| T | Untested round-4 surfaces: a limited-purpose area on the tax axis (Opus X1, Fable X14, Codex); a limited-purpose area beside a zoned city (Fable X6); the system-kind vocabulary's REVOKE and immutability (Opus X2/X4, Codex); piped propane for a non-gas service (Opus X7); a profile accepted on a two-row state's successor (Fable X17); no city-owned profile in the state-lock races (Fable X16). | all three | Cases V3–V6; race **R21** (a city-owned profile racing its governing state's close); mutations M151–M156 and M158. |
| T-attr′ | The harness still credited a target when a fixture statement between checks failed, or on an empty or connection-refused run (reproduced by Codex in Python). The race script did not check its setup or session A's exit. | Codex | **Checks narrower than their claim.** A battery catch now needs the target's own FAIL, or the run's first ERROR on a line **inside the target's own DO blocks** with every earlier check passed. Codex's three false positives are now rejected. The race script exits `SETUP FAIL` on a fixture error, and a leg whose session A failed is a FAIL that counts as no catch. |
| — | A jurisdiction pointer at an unknown place was refused as "a state, has a close date, or has not begun". | Fable | Refused by name. Case V7; mutation M157. |

**Not separately testable (recorded):**
- **A `system_kind` NULL** is refused by the trigger's service check before the NOT NULL constraint is reached. The constraint stays as defence in depth. V4 pins the refusal, and no mutation can isolate the NOT NULL (Opus X5).
- **TRUNCATE of `utility_system_kinds`** is refused first by the foreign key from profiles, or, with CASCADE, by the profiles table's own no-truncate guard. Its own no-truncate trigger is defence in depth (Opus X3).

**Notes (comment only, or no change):**
- **Fact keys** admit Unicode look-alikes and a doubled or trailing `§` (Opus, Fable). Folded into R20: loaders write ASCII.
- **Deadlocks:** two migrations closing two places in opposite orders, or one closing an owning place and its state together against a profile insert, can deadlock (Opus N4, Fable). Folded into R18 with the close order: state, then owning place.
- **The state guard's message** printed nothing for a NULL state (Fable). It now prints `NULL`.
- **Two ETJ rows for one city at once** are accepted (Fable). By design, each ETJ is its own place, and memberships are exclusive per premise. No change.
- **A Kansas township** has no place kind (Opus N3). Now named in R22.
- **Over-long header lines** (Opus N5). Cosmetic; the header was rewritten for round 5.

## Final revision (r6)

**Verified on patch `eec3f3a6`, battery `0b7e7174`** (frozen as `*-frozen-r6.sql`; clones with TEMP revoked):
- strict apply ×2;
- battery-16 **97/97** (group V covers round 5);
- races **R1–R21** (20 legs; R15 is the 25000 check inside R3–R6 and R8), each two-session leg with the second session itself observed waiting and session A checked;
- mutations **157/157**, each caught at its named check under the line-span attribution (M148–M158 for round 5; M53, M92 and M110 re-anchored);
- regressions 28/58/41/116/3/99/6, and -13's X1.
