import type { ReactNode } from 'react'
import { StateFlag } from '@/components/ui/State'

/** A solved design within this many dollars of its target is balanced — the residue of printing rates to four decimals. */
export const TOLERANCE = 1000

export const usd0 = (v: number) => `${v < 0 ? '−' : ''}$${Math.abs(Math.round(v)).toLocaleString('en-US')}`
export const usd2 = (v: number) => `$${v.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

/** A check and its finding, the same shape the old sandbox used — including the checks that found nothing. */
export function CheckRow({
  tone,
  title,
  finding,
}: {
  tone: 'cleared' | 'warning' | 'critical' | 'info'
  title: string
  finding: ReactNode
}) {
  return (
    <div className="px-4 py-3 flex items-start gap-4">
      <span className="w-52 shrink-0">
        <StateFlag tone={tone}>{title}</StateFlag>
      </span>
      <p className="text-data text-ink-secondary">{finding}</p>
    </div>
  )
}
