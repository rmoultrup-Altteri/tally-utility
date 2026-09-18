/**
 * The flags column.
 *
 * Single monospace letters, the way legacy CIS screens coded them — analysts
 * coming off Cayenta and SEDC read these fluently, and they are roughly four
 * times denser than badge chips. Every glyph carries a title and a
 * screen-reader label; colour is never the only carrier.
 */

import type { MeterReading } from '@/schemas/models'

type Flag = { letter: string; label: string; tone: string }

const FLAGS = {
  estimated: { letter: 'E', label: 'Estimated read', tone: 'text-read-estimated-text' },
  tamper: { letter: 'T', label: 'Tamper counter changed', tone: 'text-read-tamper-rail' },
  disputed: { letter: 'D', label: 'Disputed by customer', tone: 'text-read-disputed-text' },
  locked: { letter: 'L', label: 'Locked to a billing period', tone: 'text-read-locked-text' },
  transition: { letter: 'S', label: 'Service transition read', tone: 'text-exception-info-text' },
  access: { letter: 'A', label: 'Access problem recorded', tone: 'text-exception-warning-text' },
} as const satisfies Record<string, Flag>

export function readFlags(read: MeterReading): Flag[] {
  const flags: Flag[] = []
  if (read.is_estimated) flags.push(FLAGS.estimated)
  if (read.tamper_count_1_changed_flag) flags.push(FLAGS.tamper)
  if (read.dispute_reason) flags.push(FLAGS.disputed)
  if (read.billing_period_locked) flags.push(FLAGS.locked)
  if (read.is_service_transition) flags.push(FLAGS.transition)
  if (read.access_status !== 'accessed') flags.push(FLAGS.access)
  return flags
}

export function Flags({ flags }: { flags: Flag[] }) {
  if (flags.length === 0) {
    return <span className="text-ink-muted">·</span>
  }
  return (
    <span className="ident inline-flex gap-0.5">
      {flags.map((f) => (
        <abbr
          key={f.letter}
          title={f.label}
          aria-label={f.label}
          className={`no-underline font-semibold ${f.tone}`}
        >
          {f.letter}
        </abbr>
      ))}
    </span>
  )
}

/**
 * Confidence as a five-segment bar rather than a printed percentage. A number
 * invites arguing with the model; a bar invites judgement.
 */
export function Confidence({ value }: { value: number | null }) {
  if (value === null) return <span className="text-ink-muted">—</span>
  const filled = Math.round(value * 5)
  return (
    <span
      className="inline-flex gap-0.5 align-middle"
      title={`Detector confidence ${(value * 100).toFixed(0)}%`}
      aria-label={`Detector confidence ${(value * 100).toFixed(0)} percent`}
    >
      {[0, 1, 2, 3, 4].map((i) => (
        <span
          key={i}
          className={`block h-3 w-1 ${i < filled ? 'bg-ink-secondary' : 'bg-surface-inset'}`}
        />
      ))}
    </span>
  )
}
