import type { ReactNode } from 'react'

/**
 * A bill-to-bill bridge, drawn horizontally.
 *
 * The comparison bill at the top, each cause as a bar that starts where the
 * last one ended, this bill at the bottom. Rows rather than columns, so the
 * labels are words a customer can read rather than rotated ticks, and so it
 * fits a 400px phone or the side of a CSR's screen without changing shape.
 *
 * The axis starts at zero. Cutting it would make a $6 rider look like the
 * whole story, which is precisely the impression this chart exists to undo.
 * Increases and decreases are told apart by a sign in the figure as well as
 * the colour, because colour alone fails a share of every audience.
 */

export type Step = { label: ReactNode; cents: number; note?: ReactNode }

const usd = (c: number) =>
  `$${(Math.abs(c) / 100).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

export function Waterfall({
  start,
  steps,
  end,
  compact = false,
}: {
  start: { label: ReactNode; cents: number }
  steps: Step[]
  end: { label: ReactNode; cents: number }
  compact?: boolean
}) {
  let running = start.cents
  const rows = steps.map((s) => {
    const from = running
    running += s.cents
    return { ...s, from, to: running }
  })
  const max = Math.max(start.cents, end.cents, ...rows.map((r) => Math.max(r.from, r.to)), 1)
  const pct = (c: number) => `${(Math.max(c, 0) / max) * 100}%`
  const labelW = compact ? 'w-28' : 'w-40'
  const h = compact ? 'h-4' : 'h-5'

  const Total = ({ label, cents }: { label: ReactNode; cents: number }) => (
    <li className="flex items-center gap-3">
      <span className={`${labelW} shrink-0 text-data font-medium text-ink-primary`}>{label}</span>
      <span className={`relative flex-1 ${h} rounded-xs bg-surface-inset`}>
        <span className="absolute inset-y-0 left-0 rounded-xs bg-rule-heavy" style={{ width: pct(cents) }} />
      </span>
      <span className="w-20 shrink-0 text-right figures text-data font-medium text-ink-primary">{usd(cents)}</span>
    </li>
  )

  return (
    <ol className="space-y-1.5" aria-label="How the bill moved from the comparison bill to this one">
      <Total label={start.label} cents={start.cents} />
      {rows.map((r, i) => {
        const up = r.cents > 0
        const lo = Math.min(r.from, r.to)
        return (
          <li key={i} className="flex items-start gap-3">
            <span className={`${labelW} shrink-0 text-data text-ink-secondary pt-px`}>
              {r.label}
              {r.note ? <span className="block text-micro text-ink-tertiary">{r.note}</span> : null}
            </span>
            <span className={`relative flex-1 ${h} rounded-xs bg-surface-inset/60`}>
              {r.cents !== 0 ? (
                <span
                  className={`absolute inset-y-0 rounded-xs ${up ? 'bg-exception-warning-rail' : 'bg-exception-cleared-rail'}`}
                  style={{ left: pct(lo), width: `max(2px, ${pct(Math.abs(r.cents))})` }}
                />
              ) : null}
            </span>
            <span
              className={`w-20 shrink-0 text-right figures text-data ${
                r.cents === 0 ? 'text-ink-tertiary' : up ? 'text-exception-warning-text' : 'text-money-credit'
              }`}
            >
              {r.cents === 0 ? '—' : `${up ? '+' : '−'}${usd(r.cents)}`}
            </span>
          </li>
        )
      })}
      <Total label={end.label} cents={end.cents} />
    </ol>
  )
}
