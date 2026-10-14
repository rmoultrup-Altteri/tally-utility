# Codex review r3 — v5.4.2-19

**Verdict: not yet. One blocking finding: the new payment-lineage check does not protect the referenced payment's customer/tenant from later changes.** The refund-dedup blocker from r2 is closed. The other r3 changes examined below are consistent with their stated contracts.

This is a **source-only review**. Docker was unavailable and was not used. I did not connect to any database, apply SQL, run the battery, execute races or CI, or run mutation tests. Strict application twice, 159/159 checks, C1–C7, 25 CI steps, and the four supplied mutation outcomes are **reported results I read, not results I reproduced**. SQL below is an unexecuted reproduction derived from source. I changed only this report.

References: `patch` = `tests/v5.4.2-19/review/patch-19-frozen-r3.sql`; `battery` = `tests/v5.4.2-19/review/battery-19-frozen-r3.sql`; `schema` = `sql/tu.sql`; `race` = `tests/v5.4.2-19/races/cycle-19.sh`. Line numbers refer to those files.

## Artifact verification

I computed all four MD5s; **none differs** from the brief.

| File | Observed MD5 |
|---|---|
| patch | `4ef0d4d078acd2b624d3527d2c06703d` |
| battery | `32ecc5a70c319650a2539a86dd69b93f` |
| race | `91f2817513fc9079fb04648b37f03446` |
| tests/ci.sh | `a5e640c0a0ae45e04a0e21fc04e9bc51` |

`wc -l` confirms 1,519 patch lines. A source count of refusal calls and literal PASS notices, excluding the two helper bodies, yields 159 test sites; that is not 159 executed passes. I compared both r3 SQL files with r2, read the three requested r2 reviews and standing brief, and traced affected definitions through the append-only schema.

## Blocking

### B1 — A cited pending payment can move to another customer, invalidating existing lineage

**`patch:673–677,689`; `schema:13561–13565,10175,10199`.** The trigger examines only `NEW.refunds_payment_id` and `NEW.nsf_original_payment_id`. On an original payment with neither pointer, changing `customer_id` fires the trigger but skips both checks. The older identity guard permits that change while `OLD.status = 'pending'`. Neither existing single-column lineage FK includes customer or tenant.

Consequently, insert a pending original for C1, insert a posted refund for C1 citing it, then change the original to C2. Every statement satisfies the implemented checks, leaving a posted C1 refund citing a C2 payment. The same defect applies to NSF replacement lineage. This is within the new stated same-customer invariant, not a request for arithmetic or business-rule evaluation. R17's accepted pending-*amount* edits do not document or justify broken lineage ownership.

**Unexecuted reproduction:** insert this before the final ROLLBACK of a disposable copy of the battery, whose tenant/customer fixtures are at `battery:69–80`. It requires no additional fixtures or provider IDs.

```sql
SET ROLE tally_app;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000019b1';

INSERT INTO public.payments
  (id, tenant_id, payment_number, customer_id,
   payment_date, amount, payment_method, status)
VALUES
  ('00000000-0000-4000-8000-0000000019f8',
   '00000000-0000-4000-8000-0000000019a1', 'R3-PARENT',
   '00000000-0000-4000-8000-0000000019c1',
   DATE '2026-02-01', 20, 'check', 'pending');

INSERT INTO public.payments
  (tenant_id, payment_number, customer_id, payment_date, amount,
   payment_method, effective_date, effective_date_method, refunds_payment_id)
VALUES
  ('00000000-0000-4000-8000-0000000019a1', 'R3-REFUND',
   '00000000-0000-4000-8000-0000000019c1', DATE '2026-02-02', -5,
   'refund', DATE '2026-02-02', 'other',
   '00000000-0000-4000-8000-0000000019f8');

UPDATE public.payments
   SET customer_id = '00000000-0000-4000-8000-0000000019c2'
 WHERE id = '00000000-0000-4000-8000-0000000019f8';

SELECT child.payment_number, child.customer_id, parent.customer_id
  FROM public.payments child
  JOIN public.payments parent ON parent.id = child.refunds_payment_id
 WHERE child.payment_number = 'R3-REFUND';
-- Source prediction: one row, child C1, parent C2. No refusal.
```

The pending parent needs no effective date (`patch:624–625`); the posted child supplies one. Both customers are visible in T1 (`schema:11202`), so RLS does not stop the move. The parent has no deposit or other incoming composite references in this fixture.

The plain SELECT also provides no concurrency protection for this mutable parent identity (`patch:676`). A child insertion can observe the old customer while another transaction changes it. Existing FKs protect the ID, not its customer. Merely adding an unlocked reverse lookup would still leave a race.

**Fix:** bind both lineage edges using composite FKs `(pointer, tenant_id, customer_id)` to a unique `(id, tenant_id, customer_id)` key, with non-cascading parent-update behavior. Retain the visibility trigger if visible-parent semantics are desired. Alternatively implement a parent/child guard with demonstrated concurrency protection. Add sequential parent-move tests for both pointers and a two-session parent-edit/child-insert test. Do not fix this by disallowing legitimate intake edits on uncited payments.

## Should-fix

### S1 — Cover UPDATE and parent-side lineage boundaries, not only rejected INSERTs

**`battery:400–408`; `patch:689`.** P9/P9b establish only wrong-customer INSERT refusal. They cannot catch B1, removal of any `UPDATE OF` column, or checking only one pointer when both are supplied. Add pending-child pointer retargets; customer-only and tenant-only changes; a combined customer-and-pointer move to a valid new pair; both pointers present with one mismatched; hidden foreign-tenant and superuser-visible foreign-tenant parents. Include a valid same-customer UPDATE. The regression for B1 is required for closure; this broader matrix also protects the trigger's intended UPDATE contract.

### S2 — Complete the import-freeze boundary tests

**`battery:631–632`; `patch:1090–1099`.** J10/J10b sample URL and committed_rows on a complete job. Add size, a NULL transition in a count, partial/failed/cancelled terminal states, and a positive finalization that sets final counts/URL and terminal status in the same write. The implementation appears correct; these tests would distinguish its full contract from a guard that only handles the two existing examples.

## Round-2 closure

The table covers every blocking and numbered should-fix item in the three r2 reviews. Overlapping items are grouped, but each identifier is named.

| r2 item | r3 status | Evidence / judgment |
|---|---|---|
| Fable B1; Opus S4 refund idempotency | **Closed** | Negative unique index at `patch:655–659`; isolated P7c/P7e at `battery:385–399`. Index membership uses sign, not lineage or status. |
| Fable S1 unconsumed lock record | **Closed** for ordinary valid application rows | Fence at `patch:379–390`; RL1–4 at `battery:116–120`; first lock remains allowed at `battery:139–147`. Privileged inconsistent history is discussed below. |
| Fable S2; Opus S4's PR3 lineage subfinding | **Not closed as an invariant** | Child-side INSERT and relevant UPDATE checks exist at `patch:665–691`, but referenced pending rows remain movable: B1 above. |
| Opus S1; Codex S2; Fable S4 stale ledger/header descriptions | **Closed** | CI-055 `patch:82–89`, CI-118 `patch:116–122`, balance-helper comment `patch:1185–1186`, table comment `patch:1511–1512`. Supersession portion is the next row. |
| Opus S3 (including carried Opus r1 S8); Fable S3; Codex S2 supersession comment | **Accepted as residual; agree** | R16 `patch:217–219`, corrected comment `patch:821–822`. An inactive method can truthfully identify an already-initiated charge confirmed later. Selecting the account for a new charge belongs to the core; a blanket payment INSERT prohibition would discard valid history. |
| Opus S2 finished import URL/size/counts | **Closed** | All requested fields and four final statuses at `patch:1090–1099`; J10/J10b. See S2 for coverage. |
| Fable S5 index comment scope | **Closed**, with stated residual | Both index comments explicitly name the sign boundaries and zero at `patch:648–659`; R17 records cross-channel and pending-sign limitations (`patch:220–224`). |
| Codex S1 J2c isolation | **Closed** | `battery:608–613`: fresh explicit key and filename, same hash, different type, exact index name via refuses_at. |
| Codex S1 behavioral balance assertion | **Closed** | Real void call and expected 1.00/-30.00 at `battery:716–738`. This catches the supplied zero-sum mutation. |
| Codex S3 lock-order contract | **Closed as documentation** | `patch:546–553` states headers before edges, ascending header IDs, and whole-transaction retry for deadlock or serialization failure. It does not claim the trigger can acquire headers before a caller's UPDATE locks its edge. |

Neither Opus nor Codex had an r2 blocker. Their earlier blocking closures are not undone by the r3 diff examined here.

Additional r2 notes explicitly taken up in r3: Fable N6's alternate citation is at `battery:511–514`; N7's foreign schedule at `battery:279–282`; N8's three ALWAYS changes at `patch:482–485`; latest-void clarification at `patch:486–487`. Opus read-pointer/confirmation/status notes are now R15/R18 (`patch:211–216,225–229`).

## New-code audit

### Refund index and legitimate flows

`patch:645–659` allows one positive and one negative row for the same tenant/source/provider ID. Two partial refunds work with distinct refund event IDs (or the original ID once, then a distinct refund ID). Repeating either negative ID conflicts even without lineage; positive/negative status changes alone never free a slot. UPDATE into a conflicting negative key is checked by the index too.

A refund of an NSF'd payment is representable: the original remains positive, NSF is a status, and the lineage trigger imposes no parent-status condition. The battery actually uses that sequence: `battery:350` sets NSF before the refund at `:360–363`, and the additional refund at `:390–394`. Deciding whether paying that refund is financially appropriate remains the core's responsibility.

A reversal recorded by setting the original's `status='reversed'` does not change its positive amount (`schema:3857,3870–3872,13561–13566`); a negative refund can coexist. If a reversal is instead represented as another negative payment, it and a refund must have distinct event IDs in the same source. The second negative cannot reuse the original ID once the first occupies it. There is no separate event-kind component in this index. That matches the explicit **any money-out** contract, but intake must preserve each event's identity. A ledger reversal is outside this index entirely (`schema:12531`). I found no in-schema payment INSERT routine that the new index breaks.

P7d demonstrates distinct identities, not refund-total correctness: the fixture has already refunded -20 against +20 and then adds -5. This is acceptable for a uniqueness test, but not evidence of a financially valid two-part refund calculation. Use a separate +20/-5/-5 fixture if claiming that positive business scenario.

R17 is an acceptable explicit scope limit for this batch: source-specific keys, zero outside both indexes, pending amount editable. It is not global exactly-once delivery. Canonicalizing a refund's identity also matters: the schema cannot recognize one event presented once under the original ID and again under its own refund ID (`patch:650–659`). The producer must use a stable choice.

### Lineage UPDATE composition, RLS, and superuser

The `UPDATE OF` list is a union of four columns, not a requirement that all four be assigned (`patch:689`). Any one causes both non-null pointers to be checked against the final NEW tenant/customer. Thus changing only a child's customer cannot bypass the check; changing pointer and customer together to a consistent pair is valid during pending intake. A NULL pointer is intentionally skipped. Updates of unrelated fields need not recheck a genuinely invariant parent identity, but B1 shows that premise currently fails.

The function is invoker-security, with a pinned search_path, and uses positive existence plus explicit tenant/customer equality (`patch:665–677`). A hidden parent fails rather than being treated as “no mismatch.” Superusers bypass RLS but do not bypass these explicit equality tests; there is no rolsuper exemption. Existing posted-payment immutability further restricts child edits (`schema:13561–13579`). Existing other payment BEFORE triggers freeze fields or update timestamps; I found none assigning the four lineage/scope fields behind this trigger. **The missing protection is on the incoming-reference side**, as B1 describes.

### Unconsumed-read fence and stamping

Block 1 validates the transition, requires the run and lock flag, then stamps locked_at (`patch:320–363`). The new fence subsequently admits that stamp and simultaneous run/bill assignment because NEW is locked (`patch:379–390`). It always forbids changing voided_from on an unconsumed row. Consumption keeps the flag true, so a correction's release/re-lock remains governed by Block 3 (`patch:426–444`), not the new unconsumed fence. R1 and R8 supply existing positive boundaries (`battery:139–147,197–208`).

All four schema copies of void_invoice release only rows selected by invoice pointer and locked status (`schema:1229–1235,12647–12653,13837–13843,14144–14150`); the patch preserves that shape (`patch:1309–1315`). Earlier copies are overwritten, not independently callable overloads. No live billing-run function was found pre-staging lock pointers on unconsumed reads. The dry-run trigger only refuses (`schema:12027–12039`). The exception gate writes validated_at and meter counters, not these four fields (`schema:17223–17324`); location/validation backfills at `schema:12953,12960,16943,16951` precede this appended patch. No legitimate in-schema writer conflict was found.

The fence tests NEW status rather than explicitly OLD != locked. An application row cannot normally be locked with a false flag, because the birth guard and transition rule prevent it (`patch:351–356,460–475`). A superuser can deliberately load that inconsistent history; subsequent pointer edits with unchanged locked status then evade the “move” wording. That privileged history exception is not a normal-role bypass from valid rows. Migration fixtures should honor the state/flag relationship.

I accept R15 as an explicit existing limitation rather than a regression: first lock must supply run and bill together under the application contract. A missing bill pointer strands the read for void_invoice. This is a fragile contract worth retaining prominently (`patch:211–216`), not an enforced completeness guarantee. R18 is also honestly stated: status edits affect future previous-read selection (`patch:225–229,264–274`), while existing consumed evidence remains frozen. Confirmation/quality edits after consumption require a domain change, not an inferred exception to the whitelist.

### Import freeze and ALWAYS changes

The freeze checks OLD terminal status (`patch:1090`), so a single transition into complete/partial/failed/cancelled may supply final counts, URL and size. Later changes are refused, including NULL transitions through row-wise IS DISTINCT FROM. All seven schema count fields are included (`schema:3106–3112`; `patch:1097–1098`). `updated_at` remains editable by its generic trigger (`schema:8371`). The idempotency trigger is INSERT-only (`schema:12347`), and the schema's direct job backfill changes only idempotency_key before this patch (`schema:12354`). I found no live SQL routine updating a finished job's counts or URL. External import workers must finish these fields before or with terminal status; no runtime worker compatibility is established here.

The three ENABLE ALWAYS statements do not alter ordinary origin-session order or logic (`patch:483–485`). They do deliberately change replica-mode behavior: workflow validation, previous-read population and dry-run refusal now run there too. That can reject or transform replication/history-load writes that previously bypassed them. It is consistent with the requested alignment; I did not test replication. This is not a claim that every read-related trigger is now ALWAYS: the exception gate is separately created at `schema:17330–17331`.

## Test audit: what removal would show

These are static predictions, not executed mutations.

| New/changed case | Guard sensitivity and limits |
|---|---|
| refuses_at (`battery:48–68`) | Requires SQLSTATE and constraint name or message fragment. EXECUTE is in the exception sub-block; an accepted statement reaches explicit FAIL outside it. Correctly prevents J2c passing on another unique constraint. Fragment matching is deliberately weaker than an exact identity. |
| RL1–4 (`:116–120`) | Valid fixture run/invoices; removing the new fence permits each metadata edit. Specific message prevents a different refusal being credited. R1 tests that DB stamping still succeeds. |
| Q4i (`:279–282`) | Uses an existing T2 schedule with T1 items. Named message isolates the positive schedule-tenant check from a generic FK or cycle failure. Q4h itself is unchanged from r2. |
| P7c/P7e (`:385–399`) | Fresh payment numbers and otherwise valid rows isolate the negative unique index. Without it, both accept. P7e proves omitting lineage cannot evade uniqueness. |
| P7d (`:390–394`) | Positive compatibility test: continues to pass if the index is dropped, as expected; catches an overbroad key that prevents distinct refunds. It is not a removal detector. |
| P9/P9b (`:401–408`) | Parents exist and both customers are in T1; old single-column FKs accept these shapes. Removing the new trigger allows them. They do not cover parent changes, UPDATE composition, foreign tenants or owner behavior. |
| L7c (`:511–514`) | Alternate existing same-tenant citation removes the former NULL-CHECK interference. Without write-once, the pending charge can retarget. |
| J2c (`:608–613`) | Fresh filename/key excludes the independent idempotency constraint. Restoring the type-partitioned index permits the INSERT, producing FAIL. |
| J10/J10b (`:631–632`) | Valid URL / integer count edits; removing their new field guards permits them. See S2 for uncovered dimensions. |
| B5 (`:716–738`) | Calls void_invoice as tally_app, expects nonzero retained balance and reversal, compares the balance helper. A zero replacement fails; other-customer amounts make a globally unfiltered sum fail. |

B5 does **not independently isolate the tenant predicate**: its foreign-tenant ledger row also has a different customer (`battery:724–725`). Keeping only the customer predicate would still pass. The actual query has both predicates (`patch:1473–1476`); the fixture proves the tested result, not that every WHERE term is individually mutation-sensitive. Also B5 has no read attached to I4, so it does not replace the R6/R8 lock-release assertions.

Unchanged isolation caveats remain: RB1 may encounter a different-state FK failure without its guard (`battery:99–101`); RW3 uses invalid estimation_reason='x' (`:159`); I6 can still be refused by the old issued-invoice URL freeze (`:713`; `schema:14447`). These do not show new r3 false passes, and other cases exercise the corresponding guards, but should not be described as clean acceptance-with-guard-removed demonstrations.

The unchanged race script requires observing A in B's pg_blocking_pids before accepting the expected error (`race:53–60,86–95`); C5 still addresses inactive-predecessor versioning (`race:112–116`). These are graph/supersession races, **not** payment-lineage races. CI clone failure remains counted as failure (`tests/ci.sh:56–60`). I read those mechanisms but did not run them.

Finally, an extracted-body diff of the last schema void_invoice and r3 yields only the intended running_balance-to-tenant/customer-SUM change (`schema:14305–14307`; `patch:1467–1476`). The r3 comment corrections do not change that behavior. Runtime application, ownership/ACL preservation, lock behavior and all pass counts remain supplied evidence rather than independently verified facts.
