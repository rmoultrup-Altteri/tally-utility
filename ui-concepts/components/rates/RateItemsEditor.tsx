'use client'

import { Fragment, useState } from 'react'
import { Button, Panel, PanelHeader } from '@/components/ui/Panel'
import { Chip, Group } from '@/components/ui/Chip'
import { StateBlock, humanize } from '@/components/ui/State'
import { HeadRow, Row, Td, Th } from '@/components/table/Table'
import type { CalculationType, DisplayGroup, RateUnit } from '@/schemas/enums'
import { date, stamp } from '@/lib/format'
import { rateUnitLabel } from '@/lib/vocabulary'
import { RateHistory } from '@/components/rates/RateHistory'
import { matchesSearch } from '@/lib/search'
import {
  applyDraft,
  checkDraft,
  describeChange,
  formatRate,
  monthEnd,
  monthStart,
  scheduled,
  standing,
  type BilledRates,
  type CatalogItem,
  type Coordinate,
  type Draft,
} from '@/lib/rate-changes'

const GROUPS: DisplayGroup[] = ['base_charges', 'usage_charges', 'adjustments', 'riders', 'taxes_fees', 'other']
const CALCULATIONS: CalculationType[] = ['fixed_monthly', 'per_unit_usage', 'usage_modifier', 'tiered_usage', 'percentage_of_charges', 'percentage_of_bill']
const UNITS: RateUnit[] = ['per_month', 'per_therm', 'per_ccf', 'per_mcf', 'percent', 'flat']

/** The unit a calculation is almost always quoted in, so picking one sets the other. */
const UNIT_FOR: Partial<Record<CalculationType, RateUnit>> = {
  fixed_monthly: 'per_month',
  per_unit_usage: 'per_therm',
  usage_modifier: 'per_therm',
  tiered_usage: 'per_therm',
  percentage_of_charges: 'percent',
  percentage_of_bill: 'percent',
}

const input =
  'h-6 rounded-xs border border-rule-solid bg-surface-raised px-1.5 text-micro text-ink-primary placeholder:text-ink-muted disabled:opacity-50'

/**
 * Every item that prices a bill, with its standing rate and a field to change it.
 *
 * Typing a rate does not overwrite anything. Each change becomes a new version
 * that starts on a date, closes the one before it, and carries the reason it
 * was made — which is why the fields collect a date and the review asks why.
 */
export function RateItemsEditor({
  catalog,
  schedules,
  billed,
  at,
  by,
}: {
  catalog: CatalogItem[]
  schedules: string[]
  billed: BilledRates
  at: Coordinate
  by: string
}) {
  const [items, setItems] = useState(catalog)
  const [drafts, setDrafts] = useState<Record<string, Draft>>({})
  const [unrecorded, setUnrecorded] = useState<string[]>([])
  const [defaultFrom, setDefaultFrom] = useState(monthStart(at.validAt, 1))
  const [query, setQuery] = useState('')
  const [reason, setReason] = useState('')
  const [citation, setCitation] = useState('')
  const [seq, setSeq] = useState(1)
  const [recorded, setRecorded] = useState<{ lines: string[]; backdated: boolean } | null>(null)

  const thisMonth = monthStart(at.validAt)
  const nextMonth = monthStart(at.validAt, 1)
  const isNew = (key: string) => unrecorded.includes(key)
  const byKey = new Map(items.map((i) => [i.key, i]))

  const setDraft = (key: string, patch: Partial<Draft>) =>
    setDrafts((d) => {
      const next = { ...(d[key] ?? { rate: '', from: defaultFrom, to: '' }), ...patch }
      /* An existing row cleared back to untouched is no longer a change. */
      if (!isNew(key) && !next.rate.trim() && !next.to && next.from === defaultFrom) {
        const { [key]: _, ...rest } = d
        return rest
      }
      return { ...d, [key]: next }
    })
  const clearDraft = (key: string) => {
    setDrafts(({ [key]: _, ...rest }) => rest)
    if (isNew(key)) {
      setUnrecorded((u) => u.filter((k) => k !== key))
      setItems((xs) => xs.filter((x) => x.key !== key))
    }
  }
  const updateItem = (key: string, patch: Partial<CatalogItem>) =>
    setItems((xs) => xs.map((x) => (x.key === key ? { ...x, ...patch } : x)))

  const addItem = () => {
    const key = `new-${seq}`
    setSeq((n) => n + 1)
    setItems((xs) => [
      ...xs,
      {
        key,
        code: '',
        name: '',
        group: 'riders',
        calculation: 'fixed_monthly',
        unit: 'per_month',
        schedules: schedules.filter((s) => s !== 'G-2'),
        versions: [],
      },
    ])
    setUnrecorded((u) => [...u, key])
    setDrafts((d) => ({ ...d, [key]: { rate: '', from: defaultFrom, to: '' } }))
    setQuery('')
  }

  const pending = Object.entries(drafts).map(([key, draft]) => {
    const item = byKey.get(key)!
    return { key, item, draft, checks: checkDraft(item, draft, at, isNew(key)) }
  })
  const errors = pending.reduce((n, p) => n + p.checks.filter((c) => c.level === 'error').length, 0)
  const codes = items.map((i) => i.code)
  const duplicate = pending.some((p) => isNew(p.key) && p.item.code && codes.filter((c) => c === p.item.code).length > 1)

  const record = () => {
    let n = seq
    const lines: string[] = []
    let backdated = false
    const next = items.map((item) => {
      const draft = drafts[item.key]
      if (!draft) return item
      lines.push(`${item.name} (${item.code}) — ${describeChange(item, draft, at)}`)
      if (draft.from <= at.validAt) backdated = true
      return {
        ...item,
        key: item.code,
        versions: applyDraft(item, draft, at, { reason: reason.trim(), citation: citation.trim(), by, seq: n++ }),
      }
    })
    setSeq(n)
    setItems(next)
    setDrafts({})
    setUnrecorded([])
    setReason('')
    setCitation('')
    setRecorded({ lines, backdated })
  }

  const visible = items.filter((i) => isNew(i.key) || matchesSearch(query, [i.name, i.code]))

  return (
    <>
      <Panel>
        <PanelHeader
          title="Billed rate items"
          meta={`Every item that prices a bill, at its standing rate on ${date(at.validAt)}`}
          actions={<Button onClick={addItem}>+ Add rate item</Button>}
        />

        <div className="flex flex-wrap items-center gap-x-5 gap-y-2 border-b border-rule-hair bg-surface px-cell-x py-2">
          <Group label="New rates take effect">
            <Chip on={defaultFrom === thisMonth} onClick={() => setDefaultFrom(thisMonth)}>
              Start of this month · {date(thisMonth)}
            </Chip>
            <Chip on={defaultFrom === nextMonth} onClick={() => setDefaultFrom(nextMonth)}>
              Start of next month · {date(nextMonth)}
            </Chip>
            <label htmlFor="default-from" className="sr-only">
              Default effective date
            </label>
            <input
              id="default-from"
              type="date"
              value={defaultFrom}
              onChange={(e) => e.target.value && setDefaultFrom(e.target.value)}
              className={input}
            />
          </Group>
          <div className="flex items-center gap-1.5">
            <label htmlFor="rate-search" className="label-caps">
              Find
            </label>
            <input
              id="rate-search"
              type="search"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Item name or code…"
              className={`${input} w-56`}
            />
          </div>
          <p className="ml-auto text-micro text-ink-tertiary">
            Type a new rate on any row. Nothing changes until it is reviewed and recorded below.
          </p>
        </div>

        {recorded ? (
          <StateBlock tone="approved" className="border-b border-rule-hair">
            <p className="text-data text-ink-primary">
              <strong className="font-semibold">
                Recorded {recorded.lines.length} rate {recorded.lines.length === 1 ? 'version' : 'versions'}
              </strong>{' '}
              at {stamp(at.recordedAt)} by {by}.
              {recorded.backdated
                ? ' At least one is backdated — re-rate the open run before it posts.'
                : ' The next billing run prices with them from their start dates.'}
            </p>
            <ul className="mt-1.5 space-y-0.5">
              {recorded.lines.map((l) => (
                <li key={l} className="text-micro text-ink-secondary">
                  {l}
                </li>
              ))}
            </ul>
            <p className="mt-1.5 text-micro text-ink-tertiary">
              Prototype: these versions live in this page until the API lands. Reloading discards them.
            </p>
            <button
              type="button"
              onClick={() => setRecorded(null)}
              className="mt-1 text-micro text-ink-secondary underline hover:text-ink-primary"
            >
              Dismiss
            </button>
          </StateBlock>
        ) : null}

        <div className="overflow-x-auto">
          <table className="w-full text-data">
            <caption className="sr-only">Billed rate items with their standing and scheduled rates</caption>
            <thead>
              <HeadRow>
                <Th>Item</Th>
                <Th width="6rem">Applies to</Th>
                <Th align="right" width="9rem">Current rate</Th>
                <Th align="right" width="9rem">Next scheduled</Th>
                <Th width="10.5rem">New rate</Th>
                <Th width="8.5rem">Takes effect</Th>
                <Th width="10rem">Ends</Th>
                <Th width="3.5rem"> </Th>
              </HeadRow>
            </thead>
            <tbody>
              {GROUPS.map((group) => {
                const inGroup = visible
                  .filter((i) => i.group === group)
                  .sort((a, b) => Number(isNew(a.key)) - Number(isNew(b.key)) || a.name.localeCompare(b.name))
                if (inGroup.length === 0) return null
                return (
                  <Fragment key={group}>
                    <tr>
                      <td colSpan={8} className="label-caps border-y border-rule-solid bg-surface-sunken px-cell-x py-1">
                        {humanize(group)}
                      </td>
                    </tr>
                    {inGroup.map((item) => (
                      <ItemRow
                        key={item.key}
                        item={item}
                        draft={drafts[item.key]}
                        isNew={isNew(item.key)}
                        at={at}
                        schedules={schedules}
                        checks={pending.find((p) => p.key === item.key)?.checks ?? []}
                        onDraft={(patch) => setDraft(item.key, patch)}
                        onItem={(patch) => updateItem(item.key, patch)}
                        onClear={() => clearDraft(item.key)}
                      />
                    ))}
                  </Fragment>
                )
              })}
              {visible.length === 0 ? (
                <tr>
                  <td colSpan={8} className="px-cell-x py-6 text-center text-ink-tertiary">
                    No rate item matches “{query.trim()}”.
                  </td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </div>

        {pending.length > 0 ? (
          <div className="border-t border-rule-heavy bg-surface px-4 py-3 space-y-3">
            <div className="flex items-baseline justify-between gap-4">
              <p className="text-h3 text-ink-primary">
                Review {pending.length} {pending.length === 1 ? 'change' : 'changes'}
              </p>
              <button
                type="button"
                onClick={() => {
                  pending.forEach((p) => clearDraft(p.key))
                }}
                className="text-micro text-ink-secondary underline hover:text-ink-primary"
              >
                Discard all
              </button>
            </div>
            <ul className="space-y-1">
              {pending.map(({ key, item, draft, checks }) => {
                const bad = checks.some((c) => c.level === 'error')
                return (
                  <li key={key} className="flex items-baseline gap-2 text-data">
                    <span className={`ident ${bad ? 'text-exception-critical-text' : 'text-ink-primary'}`}>
                      {item.code || 'NEW ITEM'}
                    </span>
                    <span className="text-ink-secondary">
                      {bad ? 'Needs attention — see the row above' : describeChange(item, draft, at)}
                    </span>
                  </li>
                )
              })}
            </ul>
            <div className="grid grid-cols-1 gap-3 md:grid-cols-[1fr_16rem]">
              <div>
                <label htmlFor="change-reason" className="label-caps">
                  Reason for change <span className="text-exception-critical-text">*</span>
                </label>
                <textarea
                  id="change-reason"
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  rows={2}
                  placeholder="e.g. March PGA filing; annual pipeline safety fee; WNA recalculated for February"
                  className="mt-0.5 w-full rounded-xs border border-rule-solid bg-surface-raised px-2 py-1 text-data text-ink-primary placeholder:text-ink-muted"
                />
                <p className="text-micro text-ink-tertiary">Recorded on every version. It is what an auditor or the RRC reads.</p>
              </div>
              <div>
                <label htmlFor="change-citation" className="label-caps">
                  Regulatory citation
                </label>
                <input
                  id="change-citation"
                  value={citation}
                  onChange={(e) => setCitation(e.target.value)}
                  placeholder="e.g. RRC GUD-10928 PGA filing"
                  className="mt-0.5 h-8 w-full rounded-xs border border-rule-solid bg-surface-raised px-2 text-data text-ink-primary placeholder:text-ink-muted"
                />
              </div>
            </div>
            <div className="flex items-center justify-end gap-3">
              {errors > 0 || duplicate ? (
                <span className="text-micro text-exception-critical-text">
                  {duplicate ? 'Two items share a code. ' : ''}
                  {errors > 0 ? `${errors} ${errors === 1 ? 'problem' : 'problems'} to fix first.` : ''}
                </span>
              ) : !reason.trim() ? (
                <span className="text-micro text-ink-tertiary">A reason is required.</span>
              ) : null}
              <Button variant="primary" disabled={errors > 0 || duplicate || !reason.trim()} onClick={record}>
                Record {pending.length} rate {pending.length === 1 ? 'version' : 'versions'}
              </Button>
            </div>
          </div>
        ) : null}
      </Panel>

      <RateHistory items={items} billed={billed} at={at} />
    </>
  )
}

function ItemRow({
  item,
  draft,
  isNew,
  at,
  schedules,
  checks,
  onDraft,
  onItem,
  onClear,
}: {
  item: CatalogItem
  draft: Draft | undefined
  isNew: boolean
  at: Coordinate
  schedules: string[]
  checks: ReturnType<typeof checkDraft>
  onDraft: (patch: Partial<Draft>) => void
  onItem: (patch: Partial<CatalogItem>) => void
  onClear: () => void
}) {
  const current = standing(item, at)
  const next = scheduled(item, at)[0]
  const id = `rate-${item.key}`
  const percent = item.unit === 'percent'

  return (
    <>
      <Row selected={draft !== undefined}>
        <Td>
          {isNew ? (
            <div className="flex flex-wrap gap-1.5">
              <label htmlFor={`${id}-name`} className="sr-only">
                Item name
              </label>
              <input
                id={`${id}-name`}
                value={item.name}
                onChange={(e) => onItem({ name: e.target.value })}
                placeholder="Name as it prints on the bill"
                className={`${input} w-56`}
              />
              <label htmlFor={`${id}-code`} className="sr-only">
                Item code
              </label>
              <input
                id={`${id}-code`}
                value={item.code}
                onChange={(e) => onItem({ code: e.target.value.toUpperCase().replace(/\s+/g, '-') })}
                placeholder="CODE"
                className={`${input} ident w-28`}
              />
            </div>
          ) : (
            <>
              <p className="text-data text-ink-primary">{item.name}</p>
              <p className="ident text-ink-tertiary" title={humanize(item.calculation)}>
                {item.code}
              </p>
            </>
          )}
        </Td>
        <Td>
          <span className="ident text-ink-secondary">{item.schedules.join(' ') || '—'}</span>
        </Td>
        <Td align="right">
          {current ? (
            <>
              <span className="figures text-ink-primary">{formatRate(current.rate, item.unit)}</span>
              <span className="block text-micro text-ink-tertiary">
                {current.effective_to ? `through ${date(current.effective_to)}` : `since ${date(current.effective_from)}`}
              </span>
            </>
          ) : (
            <span className="text-micro text-ink-tertiary">{isNew ? 'New item' : 'Not billed today'}</span>
          )}
        </Td>
        <Td align="right">
          {next ? (
            <>
              <span className="figures text-ink-secondary">{formatRate(next.rate, item.unit)}</span>
              <span className="block text-micro text-ink-tertiary">from {date(next.effective_from)}</span>
            </>
          ) : (
            <span className="text-ink-tertiary">—</span>
          )}
        </Td>
        <Td>
          <label htmlFor={`${id}-rate`} className="sr-only">
            New rate for {item.name || 'new item'}
          </label>
          <div className="flex items-center gap-1">
            {percent ? null : <span className="text-micro text-ink-tertiary">$</span>}
            <input
              id={`${id}-rate`}
              inputMode="decimal"
              value={draft?.rate ?? ''}
              onChange={(e) => onDraft({ rate: e.target.value })}
              placeholder={current ? String(Number(percent ? Number(current.rate) * 100 : current.rate)) : '0.00'}
              className={`${input} figures w-24 text-right`}
            />
            <span className="text-micro text-ink-tertiary">{percent ? '%' : rateUnitLabel(item.unit)}</span>
          </div>
        </Td>
        <Td>
          {draft ? (
            <>
              <label htmlFor={`${id}-from`} className="sr-only">
                Takes effect
              </label>
              <input
                id={`${id}-from`}
                type="date"
                value={draft.from}
                onChange={(e) => onDraft({ from: e.target.value })}
                className={input}
              />
            </>
          ) : (
            <span className="text-ink-tertiary">—</span>
          )}
        </Td>
        <Td>
          {draft ? (
          <div className="flex items-center gap-1">
            <label htmlFor={`${id}-to`} className="sr-only">
              Ends
            </label>
            <input
              id={`${id}-to`}
              type="date"
              value={draft.to}
              min={draft.from}
              onChange={(e) => onDraft({ to: e.target.value })}
              className={input}
            />
            <button
              type="button"
              disabled={!draft.from}
              onClick={() => onDraft({ to: monthEnd(draft.from) })}
              title="End on the last day of the start month — for a one-month charge"
              className="text-micro text-accent-text hover:underline disabled:opacity-40 disabled:no-underline"
            >
              1 mo
            </button>
          </div>
          ) : (
            <span className="text-ink-tertiary">—</span>
          )}
        </Td>
        <Td align="right">
          {draft ? (
            <button type="button" onClick={onClear} className="text-micro text-ink-secondary underline hover:text-ink-primary">
              {isNew ? 'Remove' : 'Undo'}
            </button>
          ) : null}
        </Td>
      </Row>
      {isNew || checks.length > 0 ? (
        <tr className="border-b border-rule-hair bg-accent-wash">
          <td colSpan={8} className="px-cell-x pb-2 pt-0.5">
            {isNew ? (
              <div className="flex flex-wrap items-center gap-x-4 gap-y-1.5 py-1 text-micro text-ink-secondary">
                <label className="flex items-center gap-1">
                  Bill section
                  <select value={item.group} onChange={(e) => onItem({ group: e.target.value as DisplayGroup })} className={input}>
                    {GROUPS.map((g) => (
                      <option key={g} value={g}>
                        {humanize(g)}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="flex items-center gap-1">
                  Calculation
                  <select
                    value={item.calculation}
                    onChange={(e) => {
                      const calculation = e.target.value as CalculationType
                      onItem({ calculation, unit: UNIT_FOR[calculation] ?? item.unit })
                    }}
                    className={input}
                  >
                    {CALCULATIONS.map((c) => (
                      <option key={c} value={c}>
                        {humanize(c)}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="flex items-center gap-1">
                  Unit
                  <select value={item.unit} onChange={(e) => onItem({ unit: e.target.value as RateUnit })} className={input}>
                    {UNITS.map((u) => (
                      <option key={u} value={u}>
                        {humanize(u)}
                      </option>
                    ))}
                  </select>
                </label>
                <span className="flex items-center gap-2">
                  Applies to
                  {schedules.map((s) => (
                    <label key={s} className="flex items-center gap-0.5">
                      <input
                        type="checkbox"
                        checked={item.schedules.includes(s)}
                        onChange={() =>
                          onItem({
                            schedules: item.schedules.includes(s)
                              ? item.schedules.filter((x) => x !== s)
                              : [...item.schedules, s],
                          })
                        }
                      />
                      <span className="ident">{s}</span>
                    </label>
                  ))}
                </span>
              </div>
            ) : null}
            {checks.map((c) => (
              <p
                key={c.text}
                className={`text-micro ${c.level === 'error' ? 'text-exception-critical-text' : 'text-exception-warning-text'}`}
              >
                {c.level === 'error' ? '✕ ' : '! '}
                {c.text}
              </p>
            ))}
          </td>
        </tr>
      ) : null}
    </>
  )
}
