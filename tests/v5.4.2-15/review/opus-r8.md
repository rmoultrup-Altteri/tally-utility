# Review round 8: v5.4.2-15 (rewrite), Opus

**Verdict: READY.** S1 is closed. I could not get a due row recorded beside a return that had already started, by any route. Every legitimate flow I tried passes, with one exception that fails closed: a single statement that also writes a refund payment without citing the due row is refused. That is recorded as N1 below; it does not block.

## What I checked

- **Hashes match.** The patch is `2dc8f61cda3bc6958ca42737d317a629` and the battery is `8a0c6c4548ab0560ffb0698c13b4da96`.
- **Clone.** I made a fresh clone, `opus18`, from `tally` and revoked TEMP from PUBLIC, tally_app and tally_core. The patch applied strictly (`search_path=''`, `check_function_bodies=on`, ON_ERROR_STOP). The battery passed **356/356**. The clone is dropped.
- **The delta.** `diff r7 r8` shows one new function and its trigger, `z_enforce_deposit_return_due_not_started`, and nothing else. It is a plain AFTER INSERT FOR EACH ROW trigger, set to ENABLE ALWAYS.
  - It is not a constraint trigger, so it cannot be deferred.
  - It fires once the whole statement has run, including any writable WITH parts, so it sees every event the statement wrote. V28b and V28c confirm this in both orders.
  - It returns NULL, which an AFTER trigger ignores, so that is fine.
- **Probes.** They ran after V28d in the battery's own transaction, as tally_app, and were rolled back. The file is `opus-r8-probes/probes-r8.sql`.

## Probes

| # | Case | Result |
|---|---|---|
| P2 | One statement: a due row, a notice citing it, and a refunded citing it | Accepted (legitimate) |
| P3 | One statement: a due row and a refunded citing it, with no notice | Accepted (legitimate) |
| P4 | Separate statements: a due row, then a notice citing it, then a refunded that cites nothing | Accepted (legitimate) |
| P5 | One statement: withdraw a due row, write the row that supersedes it, and a notice citing the new row | Accepted (legitimate correction path) |
| P6 | Slip: one statement with two due rows and a notice citing the first | Refused by the BEFORE "already has a live due row" check. The new trigger would also refuse the second row. |
| P7 | Slip: after a notice citing row A, withdraw A and supersede it with B | Refused: "already refund_pending". In one statement with the notice, the new trigger refuses it, because the notice cites A and not B. |
| V28b / V28c | Slip: an uncited notice and a due row in one statement, either order | Refused (battery) |

The other legitimate paths do not depend on this trigger:
- **A partial return** (`principal_returned`) is not in the trigger's list, so a partial due row settled by its return is unaffected. The battery's Q-group passes.
- **The refund that settles a due row in a later statement** is not affected either. The trigger fires only when a due row is inserted, and V27 and P4 pass.

## N1 (note, not blocking): one statement is refused where two statements are accepted

**P1** is the same record as P4 written in one statement: a due row, a notice citing it, and a `refunded` that cites nothing. It is **refused** with "has a refunded … that does not cite this due row". In P4, written in separate statements, it is accepted.

This fails closed. The workaround is for the payment to cite the due row too, which P2 shows is accepted. If you want the two forms to agree, the rule could become "refuse when a refund-type event exists and **none** of them cites NEW.id". That would accept P1 and still refuse V28b and V28c. Taking this is optional.
