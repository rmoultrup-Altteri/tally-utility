'use client'

import { useMemo, useState, type ReactNode } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { useRouter, useSearchParams } from 'next/navigation'
import { PageHeader } from '@/components/shell/PageHeader'
import { Button, Panel, PanelHeader } from '@/components/ui/Panel'
import { Chip } from '@/components/ui/Chip'
import { ExportCsv } from '@/components/reports/ReportActions'
import { ReportTable } from '@/components/reports/ReportTable'
import { customers, locations, meters, serviceLinks } from '@/fixtures/accounts'
import type { ReportRow } from '@/fixtures/reports'
import { useImported } from '@/lib/imports-store'
import { useEdits, type Edits } from '@/lib/edits-store'
import { useAddedPayments } from '@/lib/payments-store'
import {
  deleteCustomReport,
  newReportId,
  saveCustomReport,
  useCustomReports,
  useStoreReady,
} from '@/lib/custom-reports-store'
import {
  OPS,
  SOURCES,
  SOURCE_KEYS,
  accountRows,
  blankReport,
  familyOf,
  meterRows,
  needsValue,
  paymentRows,
  runReport,
  valuesOf,
  type CustomReport,
  type Field,
  type Filter,
  type Lookups,
  type SourceKey,
  type SourceRows,
} from '@/lib/report-builder'
import { count, date } from '@/lib/format'
import { customerName } from '@/schemas/models'

const INPUT = 'h-7 rounded-sm border border-rule-solid bg-surface-raised px-2 text-data text-ink-primary placeholder:text-ink-muted'

/**
 * Picks which report to open from `?id=`. A saved report lives in this
 * browser's storage, which the server cannot see — so nothing is decided
 * until the store has hydrated, or every saved report would flash "not
 * found" on its way in.
 */
export function ReportBuilder({ data }: { data: SourceRows }) {
  const id = useSearchParams().get('id')
  const ready = useStoreReady()
  const saved = useCustomReports()
  const existing = id ? saved.find((r) => r.id === id) : undefined

  if (!ready) return <PageHeader back={{ href: '/reports', label: 'Reports' }} title="Custom report" meta="Loading…" />
  if (id && !existing) {
    return (
      <>
        <PageHeader back={{ href: '/reports', label: 'Reports' }} title="Report not found" />
        <div className="flex-1 overflow-auto">
          <div className="px-5 py-5">
            <Panel>
              <div className="px-4 py-6 text-center">
                <p className="text-data text-ink-primary">No saved report with this link in this browser.</p>
                <p className="text-micro text-ink-tertiary mt-1">
                  Custom reports are kept per browser until the API exists, and this one may have been deleted.
                </p>
                <p className="mt-3">
                  <Link href={'/reports/builder' as Route} className="text-data text-accent-text hover:underline">
                    Create a new report
                  </Link>
                </p>
              </div>
            </Panel>
          </div>
        </div>
      </>
    )
  }
  /* Keyed so that opening another report, or starting a new one, starts from its own definition. */
  return <Builder key={existing?.id ?? 'new'} data={data} initial={existing} />
}

/* ---- Rows: fixtures plus this browser --------------------------------- */

/**
 * The server's fixture rows, with what this browser knows laid over them:
 * accounts and meters imported or created through the assistant, payments
 * taken at the counter, and edits — a renamed account, an inactivated meter,
 * a re-dated draft bill. Custom reports must agree with the lists.
 */
function useSourceRows(data: SourceRows): SourceRows {
  const imported = useImported()
  const edits = useEdits()
  const added = useAddedPayments()
  return useMemo(() => {
    const lk: Lookups = {
      customerById: new Map(
        [...customers, ...imported.customers].map((c) => [c.id, edits.customers[c.id] ? { ...c, ...edits.customers[c.id] } : c]),
      ),
      locationById: new Map([...locations, ...imported.locations].map((l) => [l.id, l])),
      meterById: new Map(
        [...meters, ...imported.meters].map((m) => [m.id, edits.meters[m.id] ? { ...m, ...edits.meters[m.id] } : m]),
      ),
      links: [...serviceLinks, ...imported.links],
    }
    const edited = (r: ReportRow) =>
      (typeof r._customer === 'string' && !!edits.customers[r._customer]) ||
      (typeof r._meter === 'string' && !!edits.meters[r._meter])

    const accounts = data.accounts.map((r) => {
      const c = edited(r) ? lk.customerById.get(String(r._customer)) : undefined
      return c ? accountRows([c], lk)[0] : r
    })
    const metersOut = data.meters.map((r) => {
      const m = edited(r) ? lk.meterById.get(String(r._meter)) : undefined
      /* Read and test dates come from records only the server has; keep them. */
      return m ? { ...meterRows([m], lk)[0], last_read: r.last_read, next_test: r.next_test } : r
    })
    return {
      accounts: [...accounts, ...accountRows(imported.customers, lk)],
      bills: data.bills.map((r) => overlayBill(renamed(r, lk, edits), edits)),
      payments: [...data.payments.map((r) => renamed(r, lk, edits)), ...paymentRows(added, lk)],
      meters: [...metersOut, ...meterRows(imported.meters, lk)],
      reads: data.reads.map((r) => renamed(r, lk, edits)),
      exceptions: data.exceptions.map((r) => renamed(r, lk, edits)),
    }
  }, [data, imported, edits, added])
}

/** An account renamed in this browser shows its new name on every row that names it. */
function renamed(r: ReportRow, lk: Lookups, edits: Edits): ReportRow {
  const id = r._customer
  if (typeof id !== 'string' || !edits.customers[id]) return r
  const c = lk.customerById.get(id)
  return c ? { ...r, customer: customerName(c) } : r
}

function overlayBill(r: ReportRow, edits: Edits): ReportRow {
  const e = typeof r._invoice === 'string' ? edits.invoices[r._invoice] : undefined
  if (!e) return r
  return {
    ...r,
    ...(e.invoice_date !== undefined ? { invoice_date: e.invoice_date } : {}),
    ...(e.due_date !== undefined ? { due_date: e.due_date } : {}),
    ...(e.hold_reason !== undefined ? { hold_reason: e.hold_reason } : {}),
  }
}

/* ---- The builder ------------------------------------------------------ */

type Draft = Omit<CustomReport, 'id' | 'updatedAt'>

/** Two drafts are the same report when they would save the same definition. */
const sameDraft = (a: Draft, b: Draft) =>
  JSON.stringify({ ...a, title: a.title.trim(), columns: [...a.columns].sort() }) ===
  JSON.stringify({ ...b, title: b.title.trim(), columns: [...b.columns].sort() })

const slug = (s: string) =>
  s
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')

function Builder({ data, initial }: { data: SourceRows; initial?: CustomReport }) {
  const router = useRouter()
  const all = useSourceRows(data)
  const start: Draft = initial
    ? { title: initial.title, source: initial.source, columns: initial.columns, filters: initial.filters, groupBy: initial.groupBy, sort: initial.sort }
    : blankReport('accounts')
  const [draft, setDraft] = useState<Draft>(start)
  const set = <K extends keyof Draft>(k: K, v: Draft[K]) => setDraft((d) => ({ ...d, [k]: v }))

  const src = SOURCES[draft.source]
  const rows = all[draft.source]
  /* Records imported, created or taken in this browser rather than in the sample data. */
  const local = rows.length - data[draft.source].length
  const result = useMemo(() => runReport(draft, rows), [draft, rows])
  const dirty = !initial || !sameDraft(draft, start)
  const title = draft.title.trim() || `${src.label} report`

  function pickSource(source: SourceKey) {
    if (source === draft.source) return
    /* A filter or grouping names one source's fields; none of them carry over. */
    setDraft((d) => ({ ...blankReport(source), title: d.title }))
  }

  function toggleColumn(key: string) {
    set('columns', draft.columns.includes(key) ? draft.columns.filter((k) => k !== key) : [...draft.columns, key])
  }

  function save() {
    const id = initial?.id ?? newReportId()
    saveCustomReport({ id, ...draft, title })
    setDraft((d) => ({ ...d, title }))
    if (!initial) router.replace(`/reports/builder?id=${id}` as Route)
  }

  function remove() {
    if (!initial) return
    if (!window.confirm(`Delete “${initial.title}”? This removes the saved report from this browser.`)) return
    router.push('/reports' as Route)
    deleteCustomReport(initial.id)
  }

  const [noun, nouns] = src.noun
  const sortable = result.columns
  const sortKey = draft.sort && sortable.some((c) => c.key === draft.sort!.key) ? draft.sort.key : ''

  return (
    <>
      <PageHeader
        back={{ href: '/reports', label: 'Reports' }}
        title={title}
        meta={
          <>
            Custom report · {src.label} ·{' '}
            {initial ? (dirty ? 'unsaved changes' : `saved ${date(initial.updatedAt)} in this browser`) : 'not saved yet'}
          </>
        }
        actions={
          <>
            {initial ? (
              <Button variant="danger" onClick={remove}>
                Delete
              </Button>
            ) : null}
            <ExportCsv
              filename={slug(title) || `custom-${draft.source}`}
              header={result.columns.map((c) => c.label)}
              rows={result.rows.map((r) => result.columns.map((c) => r[c.key] ?? null))}
            />
            <Button
              variant="primary"
              onClick={save}
              disabled={!draft.columns.length || (!!initial && !dirty)}
              title={!draft.columns.length ? 'Pick at least one column' : undefined}
            >
              {initial ? 'Save changes' : 'Save report'}
            </Button>
          </>
        }
      />

      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5 grid grid-cols-1 lg:grid-cols-[20rem_minmax(0,1fr)] gap-5 items-start">
          <Panel>
            <Step label="Title" htmlFor="report-title">
              <input
                id="report-title"
                value={draft.title}
                onChange={(e) => set('title', e.target.value)}
                placeholder={`${src.label} report`}
                className={`${INPUT} w-full`}
              />
            </Step>

            <Step label="Source">
              <div className="flex flex-wrap gap-1.5">
                {SOURCE_KEYS.map((k) => (
                  <Chip key={k} on={draft.source === k} onClick={() => pickSource(k)}>
                    {SOURCES[k].label}
                  </Chip>
                ))}
              </div>
              <p className="text-micro text-ink-tertiary mt-1.5">
                {src.description} {count(rows.length)} {rows.length === 1 ? noun : nouns}.
              </p>
            </Step>

            <Step
              label="Columns"
              aside={
                <span className="flex gap-2 text-micro">
                  <button type="button" className="text-accent-text hover:underline" onClick={() => set('columns', [...src.defaults])}>
                    Defaults
                  </button>
                  <button type="button" className="text-accent-text hover:underline" onClick={() => set('columns', src.fields.map((f) => f.key))}>
                    All
                  </button>
                  <button type="button" className="text-accent-text hover:underline" onClick={() => set('columns', [])}>
                    None
                  </button>
                </span>
              }
            >
              <div className="grid grid-cols-2 gap-x-3 gap-y-1">
                {src.fields.map((f) => (
                  <label key={f.key} className="flex items-center gap-1.5 text-data text-ink-primary min-w-0">
                    <input type="checkbox" checked={draft.columns.includes(f.key)} onChange={() => toggleColumn(f.key)} />
                    <span className="truncate">{f.label}</span>
                  </label>
                ))}
              </div>
            </Step>

            <Step label="Filters">
              {draft.filters.length ? (
                <ul className="space-y-2.5">
                  {draft.filters.map((flt, i) => (
                    <FilterRow
                      key={i}
                      index={i}
                      filter={flt}
                      fields={src.fields}
                      rows={rows}
                      onChange={(next) => set('filters', draft.filters.map((x, j) => (j === i ? next : x)))}
                      onRemove={() => set('filters', draft.filters.filter((_, j) => j !== i))}
                    />
                  ))}
                </ul>
              ) : (
                <p className="text-micro text-ink-tertiary">Every {noun} in the source.</p>
              )}
              <div className="mt-2">
                <Button
                  variant="quiet"
                  onClick={() => {
                    const f = src.fields[0]
                    set('filters', [...draft.filters, { field: f.key, op: OPS[familyOf(f)][0].op, value: '' }])
                  }}
                >
                  + Add filter
                </Button>
              </div>
            </Step>

            <Step label="Group by" htmlFor="report-group">
              <select
                id="report-group"
                value={draft.groupBy ?? ''}
                onChange={(e) => set('groupBy', e.target.value || null)}
                className={`${INPUT} w-full`}
              >
                <option value="">No grouping — one row per {noun}</option>
                {src.fields
                  .filter((f) => familyOf(f) !== 'ordered' || f.kind === 'date')
                  .map((f) => (
                    <option key={f.key} value={f.key}>
                      {f.label}
                    </option>
                  ))}
              </select>
              {draft.groupBy ? (
                <p className="text-micro text-ink-tertiary mt-1.5">
                  One row per value, with a count and the sum of each money and number column picked.
                </p>
              ) : null}
            </Step>

            <Step label="Sort" htmlFor="report-sort" last>
              <div className="flex gap-2">
                <select
                  id="report-sort"
                  value={sortKey}
                  onChange={(e) => set('sort', e.target.value ? { key: e.target.value, dir: draft.sort?.dir ?? 'asc' } : null)}
                  className={`${INPUT} min-w-0 flex-1`}
                >
                  <option value="">{draft.groupBy ? 'Group order' : 'Source order'}</option>
                  {sortable.map((c) => (
                    <option key={c.key} value={c.key}>
                      {c.label}
                    </option>
                  ))}
                </select>
                <select
                  aria-label="Sort direction"
                  value={draft.sort?.dir ?? 'asc'}
                  disabled={!sortKey}
                  onChange={(e) => sortKey && set('sort', { key: sortKey, dir: e.target.value as 'asc' | 'desc' })}
                  className={`${INPUT} disabled:opacity-45`}
                >
                  <option value="asc">Ascending</option>
                  <option value="desc">Descending</option>
                </select>
              </div>
            </Step>
          </Panel>

          <Panel>
            <PanelHeader title={title} meta={src.label} />
            {result.columns.length ? (
              <>
                <ReportTable caption={title} columns={result.columns} rows={result.rows} />
                {result.rows.length === 0 ? (
                  <p className="px-4 py-6 text-center text-data text-ink-tertiary">No {nouns} match these filters.</p>
                ) : null}
              </>
            ) : (
              <p className="px-4 py-6 text-center text-data text-ink-tertiary">Pick at least one column.</p>
            )}
            <div className="border-t border-rule-hair px-4 py-2 text-micro text-ink-tertiary">
              {result.grouped ? (
                <>
                  {count(result.rows.length)} {result.rows.length === 1 ? 'group' : 'groups'} · {count(result.matched)} of{' '}
                  {count(rows.length)} {nouns}
                </>
              ) : (
                <>
                  {count(result.rows.length)} of {count(rows.length)} {nouns}
                </>
              )}
              {local ? ` · ${count(local)} added in this browser` : ''} · sample data
            </div>
          </Panel>
        </div>
      </div>
    </>
  )
}

/** One step of the definition, in the left-hand column. */
function Step({
  label,
  htmlFor,
  aside,
  last = false,
  children,
}: {
  label: string
  htmlFor?: string
  aside?: ReactNode
  last?: boolean
  children: ReactNode
}) {
  return (
    <div className={`px-4 py-3 ${last ? '' : 'border-b border-rule-hair'}`}>
      <div className="flex items-baseline justify-between gap-2 mb-1.5">
        {htmlFor ? (
          <label htmlFor={htmlFor} className="field-label">
            {label}
          </label>
        ) : (
          <p className="field-label">{label}</p>
        )}
        {aside}
      </div>
      {children}
    </div>
  )
}

/**
 * One filter: field, operator, value. The operators follow the field's kind,
 * and a status or other short list offers the values actually present, so a
 * filter can never be spelled into matching nothing.
 */
function FilterRow({
  index,
  filter,
  fields,
  rows,
  onChange,
  onRemove,
}: {
  index: number
  filter: Filter
  fields: Field[]
  rows: ReportRow[]
  onChange: (f: Filter) => void
  onRemove: () => void
}) {
  const field = fields.find((f) => f.key === filter.field) ?? fields[0]
  const family = familyOf(field)
  const ops = OPS[family]
  const values = family === 'enum' ? valuesOf(rows, field.key) : []
  const id = `filter-${index}`

  return (
    <li className="space-y-1.5">
      <div className="flex gap-1.5">
        <select
          id={id}
          aria-label={`Filter ${index + 1} field`}
          value={field.key}
          onChange={(e) => {
            const next = fields.find((f) => f.key === e.target.value) ?? field
            onChange({ field: next.key, op: OPS[familyOf(next)][0].op, value: '' })
          }}
          className={`${INPUT} min-w-0 flex-1`}
        >
          {fields.map((f) => (
            <option key={f.key} value={f.key}>
              {f.label}
            </option>
          ))}
        </select>
        <button
          type="button"
          onClick={onRemove}
          aria-label={`Remove filter ${index + 1}`}
          title="Remove this filter"
          className="h-7 w-7 shrink-0 rounded-sm text-ink-tertiary hover:bg-surface-sunken hover:text-ink-primary"
        >
          ×
        </button>
      </div>
      <div className="flex gap-1.5">
        <select
          aria-label={`Filter ${index + 1} operator`}
          value={ops.some((o) => o.op === filter.op) ? filter.op : ops[0].op}
          onChange={(e) => onChange({ ...filter, op: e.target.value as Filter['op'] })}
          className={`${INPUT} w-28 shrink-0`}
        >
          {ops.map((o) => (
            <option key={o.op} value={o.op}>
              {o.label}
            </option>
          ))}
        </select>
        {!needsValue(filter.op) ? null : family === 'enum' ? (
          <select
            aria-label={`Filter ${index + 1} value`}
            value={filter.value}
            onChange={(e) => onChange({ ...filter, value: e.target.value })}
            className={`${INPUT} min-w-0 flex-1`}
          >
            <option value="">Any</option>
            {values.map((v) => (
              <option key={v} value={v}>
                {v}
              </option>
            ))}
          </select>
        ) : (
          <input
            aria-label={`Filter ${index + 1} value`}
            type={field.kind === 'date' ? 'date' : family === 'ordered' ? 'number' : 'text'}
            step={family === 'ordered' && field.kind !== 'date' ? 'any' : undefined}
            inputMode={family === 'ordered' && field.kind !== 'date' ? 'decimal' : undefined}
            value={filter.value}
            onChange={(e) => onChange({ ...filter, value: e.target.value })}
            placeholder={field.kind === 'percent' ? 'Percent' : field.kind === 'money' ? 'Dollars' : 'Value'}
            className={`${INPUT} min-w-0 flex-1`}
          />
        )}
      </div>
    </li>
  )
}
