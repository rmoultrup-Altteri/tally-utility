# Wave 2 source inventory — finance-released structures and cash handling (2026-10-15)

**Authority:** Ryan, 2026-10-15: "yes, start wave 2". The wave's content is `application/step1-sequencing-2026-10-13.md` (wave 2), widened by the rulings of 2026-10-15.

**Status:** inventory. Q1 answered by Ryan 2026-10-15 (default (a)); nothing open. Everything else is settled by a ruling or a standing rule, and each settlement names it. -22 drafting started 2026-10-15.

## Sources

| Tag | Source | What it settles |
|---|---|---|
| D-2 | GBM `kyle-decisions-2026-08-18-coda-items.md` Part 2 | The platform is a customer-receivables subledger that exports, not a GL. Accounting periods are freeze boundaries, not a reporting grain. A close snapshot. A `transaction_date` range index. GL code mapping lives in tenant configuration. An AR aging view. CI-110: the accrual is never a row. |
| D-3 | same file, Part 3 | The AR aging view carries the customer's status, so a former occupant's balance reads as a former occupant's. |
| D7-1 | GBM `wu5-wu6-kyle-decisions-2026-07-10.md` | Unrestricted payments follow the posting order. An agency/pledge payment's restriction is stored on the payment and wins. |
| 10-14 | GBM `kyle-decisions-2026-10-14-…` (DECISION-LOG 2026-10-14) | Gas cost: billing side only. CI-036 is out of scope. |
| R-02 | GBM `kyle-decisions-2026-10-15-…` | Every reversal names its entry. The total of reversals against an entry is capped at the original amount. |
| R-05 | same | Payments, credits and one-off charges are add-only. A correction is a reversal plus a new row. |
| R-06 | same; `ui-concepts/components/payments/PaymentForm.tsx` | Oldest bill first, and each bill capped at its open balance. A leftover is either not taken, or held as a credit with the customer's approval. The approval is an add-only record (amount, who, when). The payment-to-bill application is stored as the screen shows it. Within a bill, the amount is split by the jurisdiction's rule order. |
| K-05 | same | A payment is designated as a deposit or as a bill. A bill payment goes oldest first. The order within a bill is jurisdiction rule data, confirmed from the tenant's tariff at setup. |
| CI | GBM register: CI-013, 017, 048, 049, 050, 053, 056, 076, 110 | The invariants' statements (the grades are frozen; see the parity measurement). |
| A | GBM register Appendix A-10, A-12, A-13 | The shapes sketched for the matrix, the suspense ledger and the posting-order configuration. |
| LIVE | `tally` (-21 build) | Table definitions below. |

## What exists (LIVE)

- **`payments`.** Mutable counters `applied_amount` and `unapplied_amount`, written by the application; no database function maintains them. A `status` lifecycle (`pending|posted|nsf|reversed|refunded|voided`) and a `reversed_*` stamp. `is_deposit` and `deposit_status`. Identity is frozen once posted (`enforce_payment_immutable`).
- **`customer_credits`.** Mutable `applied_amount` and `remaining_amount`, with a CHECK that `applied + remaining = original`. A `status` lifecycle, plus `escheat_status`. Identity frozen (`enforce_customer_credit_immutable`).
- **`adhoc_charges`.** A `status` lifecycle (`pending|billed|void|waived|void_pending_rebill`). `reason` (nullable), `void_reason`, `waive_reason`. `regulatory_class` is NOT NULL (D7-2).
- **`invoice_applications`.** Per bill, not per charge. `source_type` is `payment|credit`; `amount > 0`. Write-once-reversible: a mistaken application is stamped `reversed_*` in place. Nothing caps the applications against the bill's open balance or against the payment's amount.
- **`account_ledger`.** Insert-only. `reverses_ledger_entry_id` is generic: only a `void_reversal` must name an entry, at most once (-21). There is no sign rule and no cap. `transaction_type` has `write_off` and no recovery type.
- **`tenants`.** `payment_allocation_strategy` (`oldest_first|newest_first|largest_first|manual_only`), `overpayment_handling` (`hold_as_credit|refund_automatically|apply_to_specific_invoices`), `credit_application_timing`. Their history is in `tenant_configuration_history`.
- **Absent.** Accounting periods, a close snapshot, GL code mapping, an AR aging view, a suspense ledger, agency pledges, and an allocation-rule table.

## Proposed split: two patches

The wave is L-sized. One patch would put about 1,500 lines of meaning-changing money code and the additive reporting structures in front of reviewers together. Split by migration cost (memory `frame-shapes-by-migration-cost`):

- **v5.4.2-22, periods and reporting (additive; no ruling needed).** P, S, G and W below. It goes first: the period freeze is what every later money write respects, and it changes no existing meaning.
- **v5.4.2-23, cash (meaning-changing).** M, X, A, C, U and L below. Q1 is answered (a).

## v5.4.2-22 — periods and reporting

### P: accounting periods (D-2; CI-110)

- **P1.** `accounting_periods`: tenant, the period's first and last day (no gaps or overlaps within a tenant: EXCLUDE), and `status` `open|closed`. Every value must be producible (D-2's warning). `closed_at` and `closed_by` are stamped by the database at close. A closed period never reopens: a correction posts into an open period.
- **P2.** A money row dated inside a closed period is refused: `account_ledger.transaction_date`, and the posting dates of `payments` and `customer_credits`. Rows dated where no period is defined are accepted (onboarding precedes the first period). Settled by D-2, "the period is a freeze boundary".
- **P3.** The close is one function: it checks that the period is open and the previous period is closed, writes the snapshot (S), and flips the status in one transaction. Race: the close and a posting dated in the period serialise on the period row (memory `count-guards-need-lock-handshake`).

### S: the close snapshot (D-2; CI-110)

- **S1.** `accounting_period_snapshots`: one row per closed period, append-only, with the database's time. The figures as reported: opening balance, charges, payments, credits, adjustments, write-offs, closing balance, and the receivables aging buckets at close. The unbilled-revenue figure is a reported number here and never a ledger row (D-2, clarification 1).
- **S2.** The snapshot's figures are computed by the close function from the ledger, not passed in. The bucket edges are the tenant's configuration (W2), read at close and stored with the snapshot.

### G: GL code mapping (D-2; CI-048, Appendix A-10)

- **G1.** The mapping is tenant configuration, date-effective (bitemporal like the rate tables, A-1 pattern). The key is (charge type, customer class, service territory, tax jurisdiction), all four nullable as wildcards with a stated precedence. The values are the GL account, subaccount, USOA code and cost centre.
- **G2.** Fail-fast is the core's: the export refuses a line with no mapping (CI-048's "posting cannot proceed"). There is no posting table, because D-2 says there is no GL. The schema's part is that the mapping exists as data, is dated, and cannot be edited in place.
- **G3.** Service territory and tax jurisdiction are places (Kyle 2026-10-14, -16 places). The key references places, not text.

### W: receivables aging and write-off recovery (D-2, D-3; CI-076)

- **W1.** `receivables_aging_as_of(tenant, on, recorded)`: per customer, the open balance in age buckets, with the customer's status (D-3) and the location of the last service. It is a function with explicit coordinates, not a live view (memory `temporal-helper-no-live-fallback`).
- **W2.** The bucket edges are a tenant setting (default 30/60/90/120), recorded in `tenant_configuration_history`.
- **W3.** `write_off_recovery`, a new ledger type, must name the `write_off` entry it recovers (R-02 lineage), and the cap applies (X2). The aging threshold that triggers a write-off is core logic over a tenant setting; the schema records the setting only.
- **W4.** The `transaction_date` range index exists (`idx_ledger_tenant_date`). Nothing to add.

## v5.4.2-23 — cash

### M: add-only money (R-05; CI-013)

- **M1.** The counters go: `payments.applied_amount` and `unapplied_amount`, and `customer_credits.applied_amount` and `remaining_amount`. Each becomes a sum over the add-only application rows (A), read through an as-of function. Settled by standing rule (derive, do not store; the -19 precedent for `running_balance`, Ryan 2026-10-13).
- **M2.** Amounts and identity are write-once on all three tables from insert, not from posting (R-05).
- **M3.** `status` stays a column, moves forward only, and each move names the add-only row that caused it (Q1 (a), Ryan 2026-10-15).

### X: reversals (R-02; CI-017)

- **X1.** Every reversal names its entry. A ledger row is a reversal if and only if it names an entry. The types that are reversals by nature (`void_reversal`, `nsf`, `write_off_recovery`, and `refund` of a payment) must name one; the others may not.
- **X2.** A reversal has the opposite sign to the entry it reverses. The sum of reversals against an entry never exceeds the entry in absolute value. Race: reversers lock the original entry's row (`FOR UPDATE` on an immutable row is a pure mutex) and refuse a non-READ COMMITTED snapshot (the void's precedent).
- **X3.** The void reverses what is left of the charge entry after earlier reversals, not `-(amount_due)` (-21 R1, the cap). A charge already fully reversed voids with no ledger row.
- **X4.** -21's "one void reversal per entry" stays as a special case of X2 (the void takes all that is left).

### A: payment application (R-06, K-05, D7-1; CI-049, CI-050)

- **A1.** Application is stored per bill, and within the bill per charge (R-06, "split within a bill by the jurisdiction's rule order"). This closes CI-050's "per invoice, not per charge".
- **A2.** An application row is add-only. A mistaken one is undone by a negative application that names it, capped at it (X2's pattern), not by stamping `reversed_*`.
- **A3.** Caps: a payment's applications never exceed the payment, and a charge's applications never exceed what it owes. Both use the row-mutex handshake.
- **A4.** Across bills the order is oldest first (K-05). The application records how it was chosen: `oldest_first`, or `operator_override` with a reason and the user (CI-049; the screen lets the operator change any line). The tenant column's `newest_first`, `largest_first` and `manual_only` conflict with K-05 and are retired. Settled by the ruling, which is newer and more specific than the 2026-05 schema.
- **A5.** Within a bill, the order is a jurisdiction rule row under the rule-terms convention (K-05: "jurisdiction rule data"; memory `rule-terms-convention-adopted`). Regulated before unregulated is a fixed term of every such rule (CI-050's floor). The tenant confirms its order at setup (K-07: no assumed defaults).
- **A6.** Designation: a payment is `bill` or `deposit` (K-05), which is `is_deposit` today. An agency or pledge payment stores its restriction (D7-1 b).

### C: credits from overpayment (R-06)

- **C1.** `customer_credit_approvals`: an add-only record of the approved amount, the approving user, the time (stamped by the database), and the payment it came from. A credit of origin `overpayment` must cite its approval, and its amount equals the approved amount.
- **C2.** `tenants.overpayment_handling = 'apply_to_specific_invoices'` conflicts with K-05 (no designation of a bill) and is retired. `refund_automatically` is not ruled out by R-06 and stays.

### U: unapplied cash / suspense (CI-053, Appendix A-12)

- **U1.** `suspense_receipts`: money received that cannot be matched to a customer. It records the amount, channel, intake evidence, the time received (stamped by the database), and candidate accounts. It is add-only.
- **U2.** It is resolved by a payment that names the receipt (at most the receipt's amount in total, with the cap pattern), or by a refund. A resolution records its reason and user. Nothing is applied to a guessed account by the database.
- **U3.** The retention period is a tenant setting. Ageing and escalation are the core's.

### L: agency pledges (CI-056, D7-1 b)

- **L1.** `agency_pledges`: agency, customer, amount, pledged-at, received-at, and the program it falls under (`program_types`). It is add-only. A pledge is settled by a payment that names it, and the payment carries the pledge's restriction.
- **L2.** The SLA duration is rule data per program and jurisdiction (R-11's direction). Fail-loud ageing and the disconnect pause are the core's, reading the pledge and the rule.

## Settled by rule (reported, not asked)

1. **Counters are derived, not stored** (M1): the standing rule plus the -19 precedent.
2. **K-05 beats the 2026-05 tenant enum values** (A4, C2): a ruling outranks the schema it rules on.
3. **The within-bill order is a law/tariff row** (A5): the rule-terms convention.
4. **The void reverses what is left** (X3): R-02's cap plus memory `rules-bind-every-displacing-path`.
5. **Periods go first, as their own patch**: additive before meaning-changing, and the freeze is what the cash patch must respect.
6. **No GL posting table** (G2): D-2.

## Q1 (answered 2026-10-15: (a)): R-05 and the status columns

R-05 says payments, credits and one-off charges are add-only. The money part is clear (M1, M2). The status columns are not: a payment goes `posted → nsf`, a credit goes `active → refunded`, and a charge goes `pending → billed → void`. Each of those is an in-place edit today.

- **Default (a).** A status may only move forward, and each move must name the add-only row that caused it. An NSF names its reversing ledger entry; a refund its refund row; a charge's void its reversal. The status stays a column the app reads, but it can never change without a new money row behind it. This is the CI-012 precedent (an issued bill keeps a writable lifecycle).
- **(b).** No status column: status is derived from the add-only rows on demand. This is purer, but every reader computes it, and the app's existing status reads all change.

Either is cheap now (the tables are empty). Changing from (a) to (b) later is a meaning change: every reader is rewritten.

**Answer.** Ryan, 2026-10-15: "yes, go with the default". (a): the status stays a column; it only moves forward; every move names the add-only row behind it (an NSF its reversing ledger entry, a refund its refund row, a charge's void its reversal). -23 builds M3 this way.
