# Review round 5: v5.4.2-15 (rewrite), Opus

**Verdict: READY**, unchanged from round 4. The delta does what it says and introduces nothing new. One residual is noted below; it is not blocking.

## What I checked

- **Hashes.** Both match:
  - patch `patch-15r-frozen-r5.sql`: md5 `fb44ecc041cb2f6004171dd3723962bb`
  - battery `battery-15r-frozen-r5.sql`: md5 `1c93db1658445380739edd198b0e3543`
- **Application and battery.** On clone `opus15`, the patch applies under strict settings (`search_path=''`, `check_function_bodies=on`). The battery passes 334/334.
- **The delta.** `diff r4 r5` shows one guard in `enforce_deposit` (patch:4150-4158) and changes to two comments and to R7. Nothing else changed.
- **Probes.** These ran after the battery's fixtures, in one transaction that ends in ROLLBACK. The scratch file is `probes-r5.sql`. Clone `opus15` has been dropped.

## The delta

**r4 S1 is fixed.** I re-ran my round-4 reproduction (Z7): a deposit of 200 in category `res_f`, where a flat-150 tariff is in force on the posting date, without `tariff_id`. It is now **refused**: "the tariff row … is in force for category res_f on 2026-01-15; the deposit cites it". The guard uses the same `rule_tariff_row_as_of` lookup as the existing check on a cited tariff row, so a row that is not in force does not trigger it.

**The R7 wording is accurate** against the code on three points:
- A months tariff under a law cap in highest bills or a seasonal average is neither compared nor held.
- A stricter combined condition is refused as incomparable.
- A longer notice period is refused as incomparable.

## NOTE (not blocking)

**N1. A deposit can still skip the tariff by recording no category.** `tariff_category` is nullable. A deposit can stay out of every category, and then no tariff can apply to it.

- **Reproduction (Z7c).** T2's residential deposit of 200 under the statutory cap with `tariff_category` NULL is **accepted**, while T2 has a residential category `res_f` with a flat-150 tariff in force.
- **Is the law still held?** Yes. The statutory cap is recorded and bounds the deposit.
- **Why it stays a note.** Which category an account belongs to is the core's call. A NULL category is a deliberate option, the same way a rate may be for every category (decision 1).
- **If it is closed later.** Require a category when the utility has defined any category for the deposit's state, service and class. Alternatively, R7 could say that a deposit with no category cites no tariff.
