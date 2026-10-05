'use client'

import { useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Button } from '@/components/ui/Panel'
import { ENTITY_NOUN, type ImportProposal } from '@/lib/assistant/protocol'

export type ProposalState = { proposal: ImportProposal; status: 'staged' | 'applied' | 'discarded'; applied?: number }

const WHERE: Partial<Record<ImportProposal['entity'], { href: string; label: string }>> = {
  accounts: { href: '/customers', label: 'View accounts' },
  customers: { href: '/customers', label: 'View accounts' },
}

/**
 * A staged import, waiting on the operator. The model can propose; only this
 * card writes, and only when the operator says so.
 */
export function ImportCard({
  state,
  onApply,
  onDiscard,
}: {
  state: ProposalState
  onApply: () => void
  onDiscard: () => void
}) {
  const { proposal: p, status } = state
  const [allRows, setAllRows] = useState(false)
  const [allIssues, setAllIssues] = useState(false)
  const valid = p.preview.rows.length
  const total = primaryCount(p)
  const noun = ENTITY_NOUN[p.entity][total === 1 ? 0 : 1]
  const rows = allRows ? p.preview.rows : p.preview.rows.slice(0, 6)
  const issues = [...p.errors.map((e) => ({ ...e, level: 'error' as const })), ...p.warnings.map((w) => ({ ...w, level: 'warning' as const }))]
  const shownIssues = allIssues ? issues : issues.slice(0, 5)
  const where = WHERE[p.entity]

  return (
    <section className="overflow-clip rounded-md border border-rule-hair bg-surface-raised text-data shadow-panel" aria-label={`Staged import: ${p.summary}`}>
      <header className="flex items-baseline justify-between gap-2 border-b border-rule-hair bg-surface-sunken px-2.5 py-1.5">
        <span className="field-label">Staged import</span>
        <span className="truncate text-micro text-ink-tertiary">{p.source ?? 'from the chat'}</span>
      </header>

      <div className="space-y-2 px-2.5 py-2">
        <p className="text-ink-primary">{p.summary}</p>

        {valid > 0 ? (
          <div className="overflow-x-auto rounded-sm border border-rule-hair">
            <table className="w-full text-micro">
              <thead className="bg-surface-sunken">
                <tr>
                  {p.preview.columns.map((c) => (
                    <th key={c} className="px-1.5 py-1 text-left font-semibold text-ink-secondary whitespace-nowrap">
                      {c}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {rows.map((r, k) => (
                  <tr key={k} className="border-t border-rule-hair">
                    {r.map((c, j) => (
                      <td key={j} className={`px-1.5 py-1 align-top ${j === 0 ? 'ident text-ink-tertiary' : ''} ${j === 3 ? 'min-w-32' : 'whitespace-nowrap'}`}>
                        {c}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : null}
        {valid > 6 ? (
          <button type="button" onClick={() => setAllRows(!allRows)} className="text-micro text-accent-text hover:underline">
            {allRows ? 'Show fewer rows' : `Show all ${valid}${p.preview.rows.length < total ? ` of ${total}` : ''} rows`}
          </button>
        ) : null}

        {issues.length ? (
          <ul className="space-y-0.5 text-micro">
            {shownIssues.map((e, k) => (
              <li key={k} className={e.level === 'error' ? 'text-exception-critical-text' : 'text-exception-warning-text'}>
                <span className="ident">row {e.row}</span>
                {e.field ? <span className="text-ink-tertiary"> · {e.field}</span> : null} — {e.message}
              </li>
            ))}
            {issues.length > 5 ? (
              <li>
                <button type="button" onClick={() => setAllIssues(!allIssues)} className="text-accent-text hover:underline">
                  {allIssues ? 'Show fewer' : `Show all ${issues.length} issues`}
                </button>
              </li>
            ) : null}
          </ul>
        ) : null}
      </div>

      <footer className="flex items-center justify-between gap-2 border-t border-rule-hair px-2.5 py-1.5">
        {status === 'staged' ? (
          <>
            <span className="text-micro text-ink-tertiary" title="Imports are kept in this browser until the API exists">Kept in this browser</span>
            <span className="flex shrink-0 gap-1.5 whitespace-nowrap">
              <Button variant="quiet" onClick={onDiscard}>
                Discard
              </Button>
              <Button variant="primary" disabled={total === 0} onClick={onApply}>
                Import {total} {noun}
              </Button>
            </span>
          </>
        ) : status === 'applied' ? (
          <>
            <span className="text-micro text-exception-cleared-text">
              {state.applied ? `Imported ${state.applied} ${ENTITY_NOUN[p.entity][state.applied === 1 ? 0 : 1]}` : 'Nothing new to import — already on file'}
            </span>
            {where && state.applied ? (
              <Link href={where.href as Route} className="text-micro text-accent-text hover:underline">
                {where.label}
              </Link>
            ) : null}
          </>
        ) : (
          <span className="text-micro text-ink-tertiary">Discarded</span>
        )}
      </footer>
    </section>
  )
}

function primaryCount(p: ImportProposal): number {
  const r = p.records
  switch (p.entity) {
    case 'accounts':
    case 'customers':
      return r.customers.length
    case 'locations':
      return r.locations.length
    case 'meters':
      return r.meters.length
    case 'rate_items':
      return r.rateItems.length
  }
}
