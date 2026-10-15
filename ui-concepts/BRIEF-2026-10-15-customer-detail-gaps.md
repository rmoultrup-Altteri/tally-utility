# Build brief: customer detail page gaps (2026-10-15)

For Claude Code, working in `ui-concepts`. Read `AGENTS.md` first and follow it, and match the patterns already in the codebase: `components/accounts/AccountDetail.tsx`, `lib/edits-store.ts`, `components/ui/StatusChange.tsx`, `components/ui/Dialog.tsx`, `fixtures/exceptions.ts`. Data stays in the browser until the API exists, as everywhere else in the prototype.

Source of the decisions: `tally-utility-memory/application/kyle-decisions-2026-10-15-waves-1-to-7-and-texas-first.md` (R-08, R-09).

Kyle checked the customer detail page and it has none of the three things below. The page (`app/customers/[customerId]/page.tsx`) shows the account fields, the meter, usage against weather, open exceptions and bills. `AccountFields` has no rate schedule. The status dialog has only active, inactive and collections-style states, with no deceased state.

## 1. Rate assignment history

Show which rate schedule a customer was on, and when. This is separate from the existing Rate History tab (`components/rates/RateHistory.tsx`), which shows each rate item's tariff rate by month. That tab stays as is.

- Add a "Rate schedule" field to the Account panel showing the current schedule code, linked to its rate page where one exists.
- Add a "Rate schedule history" panel on the customer page. Columns: schedule, start date, end date (blank on the current row), reason, recorded when and by whom.
- The history is add-only. A change adds a new row and closes the previous row's end date. A row is never edited or deleted. A correction is a new row with a reason.
- No two rows for one customer may overlap in dates. Block the save with a clear message if a new start date would overlap.
- Highlight the current row.
- Seed fixture rows for the existing customers from what the fixtures already know (for example `cus-0007` is on G-1). Derive start dates from the account's move-in date. Do not invent history that contradicts the existing bills.
- Connect the existing exception `exc-0007` (`rate_schedule_mismatch`): its suggested action "Propose reclassification to G-2" should add a pending history row for the next cycle, not change any issued bill.

## 2. Deceased account status and hold

Death is a customer status with a date, not a protective program.

- Add a "Record death" action on the account page (next to Inactivate and Edit) that opens a dialog following the `StatusChange` pattern. Fields: date of death, notes.
- Proof checklist on the account, each item recorded with the date received: death certificate, obituary, and will, conservatorship, or spouse documentation. Items are recorded independently.
- While the account is deceased, show a prominent alert in `AccountAlerts` (use the `critical` or `held` tone already in the file): no shutoff and no collections activity until the account is changed over to a family member. Collections and disconnect actions on this account must be blocked, with the reason shown. Check `app/collections/page.tsx` and the transfer flow for where those actions live.
- Add a "Transfer to family member" action. It is available only once all three proof types are recorded. It records the new account holder and ends the hold. If the existing new-customer form or transfer form can be reused, reuse it. Do not build a new customer-creation flow beyond what exists.
- Record who did each step and when, with the same "edited by / reason" pattern the page already uses.

## 3. One-month review exception

If no update has been received on a deceased account for one month, raise an exception so the account does not sit frozen.

- Add an exception to the queue with `anomaly_type: 'deceased_account_review'`, `severity: 'medium'`, `entity_type: 'customer'`, `blocks_delivery: false`, description along the lines of "Deceased account with no update in one month", and a `suggested_action` that opens the account.
- The one-month clock starts when death is recorded. Any update on the account (a proof item received, a note, a transfer step) restarts it.
- The exception resolves when the account is transferred to a family member.
- It must appear on the customer page under "Open exceptions" and in the main exception queue, ranked by the existing `byConsequence` ordering.
- Add one fixture example: a deceased customer whose one-month clock has run out, so the exception shows in the queue.

## Not in this brief

- Rounding is rule data in the backend (nearest cent, rates carried to four decimals). No new screen is needed. While in the code, confirm that `Money` shows cents and that `formatRate` shows four decimals, and report anything that doesn't.
- Do not change the Rate History tab, the payment form or the transfer form.

## Done when

- The three items above work on at least one fixture customer each.
- The project's type check and build pass.
- The three decisions' wording matches the decision file; flag anything in the existing code that makes that difficult instead of quietly working around it.
