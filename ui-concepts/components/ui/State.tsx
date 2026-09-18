import type { ReactNode } from 'react'

/**
 * Lifecycle and severity presentation.
 *
 * Every status is carried by a word AND a colour — never colour alone. The
 * 3px left rail replaces a status column entirely, which buys back a full
 * column of horizontal budget on tables that badly need it.
 *
 * Class strings are spelled out rather than composed, because Tailwind cannot
 * see a class name that only exists at runtime.
 */

export type Tone =
  | 'draft'
  | 'pending'
  | 'approved'
  | 'posted'
  | 'failed'
  | 'held'
  | 'void'
  | 'superseded'
  | 'dryrun'
  | 'critical'
  | 'warning'
  | 'info'
  | 'cleared'
  | 'snoozed'

const RAIL: Record<Tone, string> = {
  draft: 'bg-state-draft-rail',
  pending: 'bg-state-pending-rail',
  approved: 'bg-state-approved-rail',
  posted: 'bg-state-posted-rail',
  failed: 'bg-state-failed-rail',
  held: 'bg-state-held-rail',
  void: 'bg-state-void-rail',
  superseded: 'bg-state-superseded-rail',
  dryrun: 'bg-state-dryrun-rail',
  critical: 'bg-exception-critical-rail',
  warning: 'bg-exception-warning-rail',
  info: 'bg-exception-info-rail',
  cleared: 'bg-exception-cleared-rail',
  snoozed: 'bg-exception-snoozed-rail',
}

const TEXT: Record<Tone, string> = {
  draft: 'text-state-draft-text',
  pending: 'text-state-pending-text',
  approved: 'text-state-approved-text',
  posted: 'text-state-posted-text',
  failed: 'text-state-failed-text',
  held: 'text-state-held-text',
  void: 'text-state-void-text',
  superseded: 'text-state-superseded-text',
  dryrun: 'text-state-dryrun-text',
  critical: 'text-exception-critical-text',
  warning: 'text-exception-warning-text',
  info: 'text-exception-info-text',
  cleared: 'text-exception-cleared-text',
  snoozed: 'text-exception-snoozed-text',
}

const WASH: Record<Tone, string> = {
  draft: 'bg-surface-raised',
  pending: 'bg-exception-info-wash',
  approved: 'bg-exception-cleared-wash',
  posted: 'bg-exception-cleared-wash',
  failed: 'bg-exception-critical-wash',
  held: 'bg-state-held-wash',
  void: 'bg-surface-inset',
  superseded: 'bg-surface-inset',
  dryrun: 'bg-state-dryrun-wash',
  critical: 'bg-exception-critical-wash',
  warning: 'bg-exception-warning-wash',
  info: 'bg-exception-info-wash',
  cleared: 'bg-exception-cleared-wash',
  snoozed: 'bg-exception-snoozed-wash',
}

/** Map a persisted status value onto a presentation tone. */
export function invoiceTone(status: string): Tone {
  switch (status) {
    case 'draft':
      return 'draft'
    case 'held':
      return 'held'
    case 'void':
      return 'void'
    case 'paid':
      return 'posted'
    case 'sent':
    case 'pending':
      return 'pending'
    case 'overdue':
    case 'write_off':
      return 'failed'
    default:
      return 'draft'
  }
}

export function runTone(status: string, isDryRun: boolean): Tone {
  if (isDryRun) return 'dryrun'
  switch (status) {
    case 'posted':
      return 'posted'
    case 'approved':
      return 'approved'
    case 'failed':
      return 'failed'
    case 'cancelled':
      return 'void'
    case 'pending':
    case 'in_progress':
    case 'review':
      return 'pending'
    default:
      return 'draft'
  }
}

export function severityTone(severity: string, status?: string): Tone {
  if (status === 'snoozed') return 'snoozed'
  if (status === 'resolved' || status === 'false_positive') return 'cleared'
  switch (severity) {
    case 'critical':
      return 'critical'
    case 'high':
      return 'warning'
    case 'medium':
      return 'info'
    default:
      return 'snoozed'
  }
}

/**
 * Human label for a snake_case persisted value, respecting industry acronyms
 * so `amr` reads as AMR rather than Amr.
 */
export { label as humanize } from '@/lib/vocabulary'

/** The 3px left edge that carries row state in place of a status column. */
export function Rail({ tone }: { tone: Tone }) {
  return <span aria-hidden className={`block h-full w-rail ${RAIL[tone]}`} />
}

/**
 * A status word. Not a pill — a letterform flag with a leading rule, which
 * stays legible at 11px and does not eat the padding a pill demands.
 */
export function StateFlag({
  tone,
  children,
  title,
}: {
  tone: Tone
  children: ReactNode
  title?: string
}) {
  return (
    <span
      title={title}
      className={`inline-flex items-center gap-1.5 whitespace-nowrap text-label uppercase tracking-[0.06em] font-semibold ${TEXT[tone]}`}
    >
      <span aria-hidden className={`inline-block h-2.5 w-rail ${RAIL[tone]}`} />
      {children}
    </span>
  )
}

/** A tinted block for callouts that need to read as a state, not a note. */
export function StateBlock({
  tone,
  children,
  className = '',
}: {
  tone: Tone
  children: ReactNode
  className?: string
}) {
  return (
    <div className={`border-l-[3px] ${RAIL[tone]} ${className}`}>
      <div className={`${WASH[tone]} px-4 py-3`}>{children}</div>
    </div>
  )
}

export const toneText = (tone: Tone) => TEXT[tone]
export const toneWash = (tone: Tone) => WASH[tone]
export const toneRail = (tone: Tone) => RAIL[tone]
