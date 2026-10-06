'use client'

import { addFavorite, removeFavorite, useFavorites } from '@/lib/favorites-store'
import { reportFavoriteId, type ReportKey } from '@/lib/views'
import { Button } from '@/components/ui/Panel'

/** The star on a report header — the `report` favorite variant. */
export function ReportStar({ report }: { report: ReportKey }) {
  const favorites = useFavorites()
  const id = reportFavoriteId(report)
  const on = favorites.some((f) => f.id === id)
  return (
    <button
      type="button"
      onClick={() => (on ? removeFavorite(id) : addFavorite({ id, kind: 'report', report }))}
      aria-pressed={on}
      title={on ? 'Remove this report from favorites' : 'Add this report to favorites'}
      className={`inline-flex h-7 items-center gap-1.5 rounded-sm border px-2 text-data transition-colors duration-fast ${
        on
          ? 'border-rule-solid bg-accent-wash text-ink-primary'
          : 'border-rule-solid bg-surface-raised text-ink-secondary hover:bg-surface-sunken hover:text-ink-primary'
      }`}
    >
      <span aria-hidden>{on ? '★' : '☆'}</span>
      {on ? 'Favorited' : 'Favorite'}
    </button>
  )
}

/** Downloads the report table as CSV, raw values rather than display formatting. */
export function ExportCsv({
  filename,
  header,
  rows,
}: {
  filename: string
  header: string[]
  rows: (string | number | null)[][]
}) {
  function download() {
    const esc = (v: string | number | null) => {
      const s = v === null ? '' : String(v)
      return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
    }
    const csv = [header, ...rows].map((r) => r.map(esc).join(',')).join('\n')
    const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv' }))
    const a = document.createElement('a')
    a.href = url
    a.download = `${filename}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }
  return <Button onClick={download}>Export CSV</Button>
}
