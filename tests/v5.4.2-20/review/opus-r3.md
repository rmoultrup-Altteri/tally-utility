# v5.4.2-20 r3 review: Opus (diff-scoped)

**Date:** 2026-10-14. **Scratch DB:** `rv20opus` (dropped at the end).

**Hashes (executed):** the brief `90548f46…` matches its `.md5`. All four frozen files match the brief.

**Reproduced (executed):**
- Strict apply, twice: the first run applies, the second is skipped by its marker.
- `battery-20`: 80 PASS, ends "complete".
- `seal-20.sh` on a fresh clone: 19 PASS (RC1–RC6, RC5b, RC3b, T1–T7c).
- Not run: `ci.sh`, and `mutations-20.py` (the brief forbids it).

## Verdict: ready

No blocking items. Each new check catches what it claims, and none refused a correct state I could build.

## The new checks (all executed, each misconfiguration in a rolled-back transaction)

**The CHECK assertion.**
- `pg_get_constraintdef` renders the same string under `search_path = pg_catalog` as under the default.
- The invariant passes with the session's `search_path = ''`, because the function pins its own path.
- Dropping the constraint and re-adding it `NOT VALID` with the same expression is refused ("missing, changed or not validated").

**The grant-option strings.**
- `GRANT USAGE ON SCHEMA public TO tally_seal WITH GRANT OPTION` is refused. The error names it as extra and the plain grant as missing.
- The live grants all render without the option, so the clean state passes.

**The narrowed temp exclusion.**
- An invoker-rights temp function granted to `tally_void` is still excluded. That is the battery's pattern, and G1 and G8 pass.
- A temp SECURITY DEFINER granted to `tally_void` is now refused ("extra function pg_temp_3.hd() EXECUTE").

**The PUBLIC clause.**
- Nothing in the clean state trips it: there are no PUBLIC table or column grants, and `sql/tu.sql` grants no table to PUBLIC.
- The 382 public-schema functions with PUBLIC EXECUTE are outside the clause, as its wording says.

## Should fix (optional)

**S1. The PUBLIC clause covers more than "table or column" (executed).** It scans every `pg_class` row in `public`, so a PUBLIC grant on a sequence or a view is refused too. `GRANT USAGE ON SEQUENCE … TO PUBLIC` raised "PUBLIC holds a table or column privilege on s_pub". Keeping the broader scope is right, because the seal roles would inherit those grants too. Say "relation" in the message and comment. Also note for later patches that a world-readable lookup table or view must be granted to named roles, not to PUBLIC.

**S2. The constraint and trigger strings come from the deparser (predicted).** A major-version upgrade that changes `pg_get_constraintdef` or `pg_get_triggerdef` output would make the invariant raise. That fails closed, but it would read as drift. Record in the patch header that the strings belong to PG 16 and must be re-captured after an upgrade.
