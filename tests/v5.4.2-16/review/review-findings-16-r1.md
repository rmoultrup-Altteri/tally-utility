# v5.4.2-16 review round 1: findings and dispositions

**Frozen:** patch `a87f2e9f`, battery `3c1d2f05`. Brief: `review-brief-16-r1.md`. Full reviews: `review-r1-{opus,fable,codex}.md`.
**Verdicts:** all three "not yet".

The main session reproduced B1–B3 on a fresh clone. B4 was reproduced by Fable with a NOBYPASSRLS role; it follows from RLS, and v5.4.2-13 carries the same guard.

Each item is settled by a standing rule (memory `source-inventory-first-triage-by-rule`):
- **integrity** — fix;
- **source** — a real source needs the shape, so build it;
- **none** — no source, so record it as a residual;
- **existing** — follow the nearest existing code.

## Blocking

| # | Finding | Who | Disposition |
|---|---|---|---|
| B1 | A membership or profile inserted under REPEATABLE READ reads the place from a snapshot taken before a close committed. Reproduced: an open membership was committed in a place closed in 2024. | all three | **Integrity.** Both insert paths run only under READ COMMITTED (the rate pattern, applied to both sides). The membership leg of each lookup also requires the place to be in force on the date. New race legs for both insert paths. |
| B2 | The premise's state is checked only when a membership is inserted. Reproduced: an El Paso County premise changed to OK reads America/Denver. | all three | **Integrity.** Changing a premise's normalised state is refused while it has a membership of another state's place. That change runs only under READ COMMITTED. A membership insert share-locks the premise row. The lookups drop memberships whose place is not of the premise's state. |
| B3 | The time zone guesses. Reproduced: an El Paso premise with no county recorded gets America/Chicago. A county recorded on the tax axis only is ignored. | Codex, Opus (Fable S5) | **Integrity.** A state carries `time_zone_uniform`; Texas is false. Where only the state's zone would answer and the state is not uniform, the lookup refuses. The time zone reads both axes. |
| B4 | A close by a role that RLS narrows sees none of the memberships, so it passes. | Fable | **Existing.** v5.4.2-13's `v_sees_all` guard is ported to `enforce_place`. |
| B5 | Inventory requirements with no disposition: P7 rate history, P10 distance, A5 enforcing body, A6 customer attributes. | Codex (Opus, Fable) | **Source** for P7 and P10. P7: a `sales_tax_rate` fact kind. P10: a membership's `relation` (within or outside), with an optional distance. **Residuals** for A5 (an attribute of each law row's rule set) and A6 (customer and meter facts mapped as each law area is rebuilt). |

## Should-fix

| # | Finding | Who | Disposition |
|---|---|---|---|
| S1 | A missing city membership cannot be told from "outside the city". | all three | **Source** (TX §103.053; KS 66-104f; NM 3-25-3). An explicit `outside` membership, with an optional distance; absence means unknown. |
| S2 | City, limited-purpose and extraterritorial memberships can coexist on one premise and axis. | Opus, Fable | **Integrity** (LGC ch. 42–43: they are exclusive). Kinds get an exclusivity group in place of a per-kind flag. |
| S3 | An owner type does not limit the owning place's kind. A city system cannot own service in a second state. | all three | **Integrity:** `owning_place_kinds` per owner type. **Source/none:** the owning place's state is no longer forced to equal the profile's state (Texarkana-style border cities). |
| S4 | `local_adoption` allows one adopted law per place at a time. | all three | **Integrity.** Keyed fact kinds: `fact_key`, required exactly for keyed kinds, and part of the exclusion. |
| S5 | The lookups accept a NULL or unknown axis, a NULL date, or an invisible premise. | all three | **Integrity.** They refuse. |
| S6 | `jurisdictions.place_id` can point at a state, can be repointed, and is not counted when a place closes. | Opus, Fable, Codex | **Integrity.** It may not point at a state. It takes the place lock and runs under READ COMMITTED. A place does not close while a jurisdiction points at it. |
| S7 | `created_by` is not stamped. | Opus | **Existing** (the closed_by pattern). Stamped from the session. |
| S8 | A place's parent kind is unchecked. | Opus, Fable | **Integrity.** `parent_kinds` per kind. |
| S9 | Membership evidence has no date. | Codex, Opus | **Source** (inventory D2: "ordinance number and date"). `evidence_date` is required on memberships and profiles. |
| S10 | No TRUNCATE guard on the platform tables. | Opus | **Existing.** `no_truncate`. |
| S11 | Any session can hold an advisory lock on a place's key and stall writers indefinitely. | Opus | **None** (it applies to every advisory protocol, -15's rate lock included). Stated as a residual. |
| S12 | A membership or profile can be closed with a past end date. | Opus | **None yet.** Nothing cites a membership. When law decisions do, they record their inputs, and a floor follows (residual). |
| S13 | Commission jurisdiction can depend on the premise (KS 3 miles). | Opus | A law row's predicate over `relation` and distance. Residual, for when law rows key on it. |
| S14 | Time zones like "Factory" are accepted. | Opus | **Integrity, cheap.** The name must contain "/" or be "UTC". |

## Tests

| Finding | Who | Disposition |
|---|---|---|
| Opus ran 11 mutations; 9 were missed (close boundary `>` vs `>=`, the `created_at` stamp, `assert_same_tenant_user`, the lookup's date boundary, …) | Opus | Cases added so each is caught at a named check; mutations added. |
| Success assertions with `<>` accept NULL | Codex | `IS DISTINCT FROM` throughout. |
| G3 accepts two error codes | Opus | Split, so each code is caught by its own guard. |
| No race tests for insert-side isolation or state changes | all three | R4–R7. |
| The profile close stamp is not asserted | Fable | Added. |
| The harness reads working files, and can count an unrelated error | Codex | Working files are the revision under test, by design. The harness prints the first failure; any catch outside its named check is reviewed by hand, as before. |

## Revision for round 2

Every item above is folded or recorded as a residual (R10–R15 in the patch). In building it, two more guards proved implied by others, so they were folded in rather than kept uncatchable:
- the place lookup's "premise not found" refusal: an invisible premise has no state, so the state check refuses it;
- the early return for a respelled state: it is visible only under REPEATABLE READ, so it is tested as race leg R9.

**Verified on patch `24998853`, battery `ef1c7da0`** (clones with TEMP revoked):
- strict apply ×2;
- battery-16 **50/50**;
- races **R1–R9**;
- mutations **79/79**, each caught at its named check, including those Opus ran by hand;
- regressions 28/58/41/116/3/99/6, and -13's X1.
