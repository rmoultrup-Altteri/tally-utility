'use client'

import Link from 'next/link'
import type { Route } from 'next'
import { Button } from '@/components/ui/Panel'
import { Diff } from '@/components/communications/TemplateEditor'
import { CHANNEL_LABEL, LANG_LABEL } from '@/fixtures/templates'
import type { TemplateProposal } from '@/lib/assistant/protocol'

export type TemplateProposalState = { proposal: TemplateProposal; status: 'staged' | 'applied' | 'discarded' }

/**
 * A template edit the assistant drafted, waiting on the operator. Same trust
 * boundary as a staged import: the model writes the words, only this card
 * saves them, and the saved version says it was made with the assistant.
 */
export function TemplateEditCard({
  state,
  canApply,
  onApply,
  onDiscard,
}: {
  state: TemplateProposalState
  canApply: boolean
  onApply: () => void
  onDiscard: () => void
}) {
  const { proposal: p, status } = state
  return (
    <section
      className="overflow-clip rounded-md border border-rule-hair bg-surface-raised text-data shadow-panel"
      aria-label={`Template edit: ${p.templateName}`}
    >
      <header className="flex items-baseline justify-between gap-2 border-b border-rule-hair bg-surface-sunken px-2.5 py-1.5">
        <span className="field-label">Template edit</span>
        <span className="truncate text-micro text-ink-tertiary">
          {CHANNEL_LABEL[p.channel]} · {LANG_LABEL[p.lang]}
        </span>
      </header>
      <div className="space-y-1.5 px-2.5 py-2">
        <p className="text-ink-primary">
          <Link href={`/communications/${p.templateId}` as Route} className="font-medium text-accent-text hover:underline">
            {p.templateName}
          </Link>
          {p.before ? null : <span className="text-micro text-ink-tertiary"> · new {LANG_LABEL[p.lang]} version</span>}
        </p>
        <p className="text-micro text-ink-secondary">“{p.reason}”</p>
        <div className="max-h-56 overflow-y-auto">
          <Diff before={p.before} after={p.after} />
        </div>
        {p.warnings.map((w) => (
          <p key={w} className="text-micro text-exception-warning-text">
            {w}
          </p>
        ))}
      </div>
      <footer className="flex items-center justify-between gap-2 border-t border-rule-hair px-2.5 py-1.5">
        {status === 'staged' ? (
          <>
            <span className="text-micro text-ink-tertiary">Saved as a new version</span>
            <span className="flex shrink-0 gap-1.5 whitespace-nowrap">
              <Button variant="quiet" onClick={onDiscard}>
                Discard
              </Button>
              <Button
                variant="primary"
                disabled={!canApply}
                title={canApply ? undefined : 'Your role cannot edit communications'}
                onClick={onApply}
              >
                Apply edit
              </Button>
            </span>
          </>
        ) : status === 'applied' ? (
          <>
            <span className="text-micro text-exception-cleared-text">Applied — a new version is live</span>
            <Link href={`/communications/${p.templateId}` as Route} className="text-micro text-accent-text hover:underline">
              Open template
            </Link>
          </>
        ) : (
          <span className="text-micro text-ink-tertiary">Discarded</span>
        )}
      </footer>
    </section>
  )
}
