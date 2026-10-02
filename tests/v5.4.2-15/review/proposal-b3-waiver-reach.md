# Proposal for independent review: B3 — which waivers reach which deposits

You are one of three independent reviewers (Opus, Fable, Codex) of a schema proposal. **Read only: do not edit anything or write to any database.** Give your own view; finding what is wrong is more useful than agreeing.

## Context

Repository: `/Users/ryanscomputer/code/tally-utility`, a PostgreSQL schema for a multi-state utility billing platform (Texas launches first). The owner's ground rules:
- **The schema represents; the C# calculation core evaluates.** Law is stored as platform-held, dated, cited rows. Triggers protect record integrity only and never decide law.
- **A Texas-only launch is not a Texas-only architecture.** Another state's law must fit as rows.
- **Nothing is live.** There is no code and no data, so every design is permanent. Never propose a stopgap.

Read:
- `sql/v5.4.2-15-deposits-law-to-core.sql` (draft patch): §2 (the vocabularies, including `deposit_waiver_classes`), §3 (`deposit_rules` and its `waivable` column), §6 (`deposit_waiver_determinations`).
- `application/deposits-parity-rescope-2026-09-30.md` §3.
- `tests/v5.4.2-15/review/review-findings-15-r1.md` row B3: the finding this answers.
- The source decision tables in `/Users/ryanscomputer/code/gas-billing-memory/application/configurable-rules/decision-tables/`:
  - `deposit-eligibility-and-waiver.md` (#53: ranks 0–9; rank 0 family violence "outranks every basis including a §366 assurance demand"; rank 3 a tariff "may extend but never narrow" ranks 0–2; rank 4 fail-open);
  - `deposit-alternatives-and-triggers.md` (#55 rule 8: a waiver is re-checked when an additional-deposit trigger fires).

## Today (the draft)

- `deposit_waiver_classes(state_code, service_type, class_code, requires_certification, …)`: the grounds for waiving a deposit. Texas gas has four: `family_violence_certified`, `age_65_no_balance`, `good_payment_history` and `tariff`.
- `deposit_waiver_determinations`: a customer qualified for a class, on a date, with a certification reference and expiry where one is needed. Append-only.
- `deposit_rules(state, service, customer_class, basis, dated) … waivable boolean`: if the deposit's rule is waivable and the customer holds ANY waiver in force, no deposit may be required.
  - Texas seed: the six §7.45 rules (residential and non_residential × credit_evaluation, additional_trigger, tariff) are waivable.
  - The two §366 bankruptcy rules are not waivable (copying v5.4.2-06; Kyle question K2 asks whether family violence beats §366).

The problem: one boolean per rule can't say "class X reaches this rule, class Y doesn't".

## The proposal

Replace `deposit_rules.waivable` with a reach table:

```sql
CREATE TABLE public.deposit_rule_waiver_reach (
    rule_id         uuid NOT NULL,   -- the deposit_rules row (state, service, class, basis, dates)
    state_code      text NOT NULL,   -- copied from the rule
    service_type    text NOT NULL,
    waiver_class    text NOT NULL,   -- a deposit_waiver_classes row of that state and service
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (rule_id, waiver_class),
    FOREIGN KEY (rule_id) REFERENCES public.deposit_rules(id),
    FOREIGN KEY (state_code, service_type, waiver_class)
        REFERENCES public.deposit_waiver_classes(state_code, service_type, class_code)
);
```

- **Meaning of a row:** a waiver of this class, in force, excuses a deposit governed by this rule.
- **Treatment, as the other law tables:**
  - platform-held, and the application only reads it;
  - never edited or deleted;
  - written in its rule's own transaction;
  - a guard checks that the row's state and service equal its rule's.
- **A change in reach** is a close of the rule row plus a successor rule with the new list, so a deposit's citation of its rule also fixes the list that applied.
- **The core's evaluation:**
  1. resolve the rule (premise state, service, customer class, basis, date);
  2. read its reach list;
  3. read the customer's in-force determinations for that state and service;
  4. if they intersect, no deposit.
- **There is no ranking.** The outcome is binary, and #53's ranks are read as "the waivers come before the requirements".
- **Texas seed:** the four classes on each of the six §7.45 rules (24 rows) and none on the two §366 rules. If Kyle rules family violence beats §366, add (§366 rule, family_violence_certified) for each of the two §366 rules.

Alternatives the author considered:
- (a) keep the boolean;
- (b) `waivable_classes text[]` on the rule row;
- (c) a `reaches_bases` array on the waiver class.

## What to answer

1. **Verdict:** adopt as is, adopt with changes (say which), or a different shape (give it).
2. Does it represent #53 and #55 faithfully? In particular:
   - the ranking;
   - rank 3's "may extend but never narrow";
   - rank 4's fail-open (an unevaluable waiver input means no deposit);
   - #55 rule 8 (re-check on a trigger).
   Does anything in those tables need precedence, or a non-binary outcome (a waiver that reduces rather than removes a deposit), that this can't hold?
3. **Plausible law in another state that does NOT fit:** reach by additional-deposit trigger (e.g. NSF vs disconnection), by instrument, by customer class within a rule, a time-limited or partial waiver, a waiver that only defers.
4. **Holes:**
   - Is `state_code`/`service_type` duplication the right way to enforce same-state?
   - Does the close-and-successor treatment make sense for reach?
   - Should the tariff waiver class (the utility's own) be platform-held at all, given the owner's ruling that a value the utility answers for stays the utility's (R-D1)?
5. **Anything simpler** that holds the same shapes.

Keep your answer under ~3,000 characters, plain language, headed by your one-line verdict.
