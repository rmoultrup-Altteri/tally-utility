/**
 * Jump-to-record quick-find (T8-1, locked).
 *
 * One input, typeahead, no mode switch and no criteria builder. "Find this
 * customer, they're on the phone" is the dominant operator search, and it is
 * fully served by jumping to a record.
 *
 * It matches five fields and only five: customer name, account number, meter
 * number or serial, service address, invoice number. Multi-match lands the
 * operator on the relevant record list with the term pre-applied — that is the
 * only connection between this and the filtering surfaces, which live on the
 * record lists as column filters. There is no advanced-search screen in v1.
 */

import { Key } from '@/components/ui/Panel'

const MATCH_FIELDS = [
  'customer name',
  'account number',
  'meter number',
  'service address',
  'invoice number',
]

export function QuickFind() {
  return (
    <div className="relative flex items-center">
      <label htmlFor="quickfind" className="sr-only">
        Find a customer, account, meter, address or invoice
      </label>
      <input
        id="quickfind"
        type="search"
        placeholder="Jump to record…"
        title={`Matches ${MATCH_FIELDS.join(', ')}`}
        className="h-6 w-72 rounded-xs border border-rule-solid bg-surface-raised pl-2 pr-14 text-data text-ink-primary placeholder:text-ink-muted"
      />
      <span className="pointer-events-none absolute right-1.5 flex items-center gap-0.5">
        <Key>⌘</Key>
        <Key>K</Key>
      </span>
    </div>
  )
}
