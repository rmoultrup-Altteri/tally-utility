'use client'

import { useEffect, useState, type ReactNode } from 'react'
import { fieldClass } from '@/components/ui/Dialog'
import { Chip } from '@/components/ui/Chip'
import { StateBlock } from '@/components/ui/State'
import { ThemeControl } from '@/components/shell/ThemeControl'
import { MONTHS, type Column, type Row, type SettingDef } from '@/fixtures/settings'
import { money } from '@/lib/format'
import type { SettingValue } from '@/lib/settings-store'

/**
 * One setting's control, its plain-language reading, and its validation.
 * The catalog in `fixtures/settings.ts` is data; everything that turns a
 * definition into a form lives here.
 */

/** The shared input look, sized by the caller rather than filling its row. */
export const controlClass = fieldClass.replace('mt-1 ', '').replace(' w-full', '')

const MONEY = /^\d+(\.\d{1,2})?$/
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/

/* ---- Reading a value back in words ------------------------------------ */

function cell(col: Column, v: unknown): string {
  switch (col.kind) {
    case 'percent':
      return `${v}%`
    case 'money':
      return money(String(v))
    case 'toggle':
      return v ? 'Yes' : 'No'
    case 'select':
      return col.options.find((o) => o.value === v)?.label ?? String(v)
    case 'number':
      return `${v}${col.unit ? ` ${col.unit}` : ''}`
    default:
      return v === '' || v == null ? '—' : String(v)
  }
}

export function describe(def: SettingDef, v: SettingValue): string {
  switch (def.kind) {
    case 'number':
      return v == null ? (def.nullable ? 'None' : '—') : `${v}${def.unit ? ` ${def.unit}` : ''}`
    case 'percent':
      return `${v}%`
    case 'money':
      return money(String(v))
    case 'toggle':
      return v ? 'On' : 'Off'
    case 'select':
      return def.options.find((o) => o.value === v)?.label ?? String(v)
    case 'multi': {
      const list = (v as string[]) ?? []
      return list.length ? list.map((x) => def.options.find((o) => o.value === x)?.label ?? x).join(', ') : 'None'
    }
    case 'months': {
      const list = (v as string[]) ?? []
      if (list.length === 12) return 'Every month'
      return list.length ? MONTHS.filter((m) => list.includes(m.value)).map((m) => m.label).join(', ') : 'Never'
    }
    case 'list':
      return `${((v as number[]) ?? []).join(', ')} ${def.unit}`
    case 'rows':
      return `${((v as Row[]) ?? []).length} rows`
    default:
      return v === '' || v == null ? '—' : String(v)
  }
}

export type ChangeLine = { key: string; label: string; from: string; to: string; tariff: boolean }

/** What changed, one line per value — a row table reads cell by cell. */
export function changeLines(def: SettingDef, from: SettingValue, to: SettingValue): ChangeLine[] {
  const tariff = Boolean(def.tariff)
  if (def.kind !== 'rows') return [{ key: def.key, label: def.label, from: describe(def, from), to: describe(def, to), tariff }]
  const a = (from as Row[]) ?? []
  const b = (to as Row[]) ?? []
  const first = def.columns[0]
  const name = (r: Row) => String(r[first.key] || 'new row')
  const lines: ChangeLine[] = []
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const was = a[i]
    const now = b[i]
    if (!now) lines.push({ key: def.key, label: `${def.label} · ${name(was)}`, from: 'Present', to: 'Removed', tariff })
    else if (!was) lines.push({ key: def.key, label: `${def.label} · ${name(now)}`, from: '—', to: 'Added', tariff })
    else
      for (const col of def.columns)
        if (was[col.key] !== now[col.key])
          lines.push({ key: def.key, label: `${def.label} · ${name(now)} · ${col.label}`, from: cell(col, was[col.key]), to: cell(col, now[col.key]), tariff })
  }
  return lines
}

/* ---- Validation ------------------------------------------------------- */

function validateCell(col: Column, v: unknown): string | null {
  switch (col.kind) {
    case 'text':
      return !col.readOnly && !col.optional && !String(v ?? '').trim() ? `${col.label} is required` : null
    case 'date':
      return ISO_DATE.test(String(v ?? '')) ? null : `${col.label} needs a date`
    case 'money':
      return MONEY.test(String(v ?? '')) ? null : `${col.label} needs an amount`
    case 'number':
    case 'percent': {
      const n = Number(v)
      if (v === '' || v == null || !Number.isFinite(n)) return `${col.label} is required`
      if (col.min != null && n < col.min) return `${col.label} is at least ${col.min}`
      if (col.max != null && n > col.max) return `${col.label} is at most ${col.max}`
      return null
    }
    default:
      return null
  }
}

export function validate(def: SettingDef, v: SettingValue): string | null {
  if (def.regulated) return null
  switch (def.kind) {
    case 'number': {
      if (v == null) return def.nullable ? null : 'Required.'
      if (typeof v !== 'number' || !Number.isFinite(v)) return 'Enter a number.'
      if (def.min != null && v < def.min) return def.minNote ?? `At least ${def.min}.`
      if (def.max != null && v > def.max) return def.maxNote ?? `At most ${def.max}.`
      return null
    }
    case 'percent': {
      if (typeof v !== 'number' || !Number.isFinite(v)) return 'Enter a percentage.'
      if (v < (def.min ?? 0)) return `At least ${def.min ?? 0}%.`
      if (def.max != null && v > def.max) return `At most ${def.max}%.`
      return null
    }
    case 'money':
      if (!MONEY.test(String(v ?? ''))) return 'Enter dollars and cents, like 25.00.'
      if (def.min != null && Number(v) < def.min) return `At least ${money(def.min)}.`
      return null
    case 'text':
      return def.required && !String(v ?? '').trim() ? 'Required.' : null
    case 'list': {
      const list = v as number[]
      return Array.isArray(list) && list.length && list.every((n) => Number.isFinite(n) && n > 0) ? null : 'Enter one or more positive numbers, separated by commas.'
    }
    case 'rows': {
      for (const r of (v as Row[]) ?? []) for (const col of def.columns) {
        const e = validateCell(col, r[col.key])
        if (e) return `${e}.`
      }
      return null
    }
    default:
      return null
  }
}

/* ---- Badges ----------------------------------------------------------- */

function Badge({ children, title, tone }: { children: ReactNode; title: string; tone: 'lock' | 'tariff' | 'gap' | 'open' }) {
  const cls = {
    lock: 'border-rule-solid bg-surface-sunken text-ink-secondary',
    tariff: 'border-exception-info-rail/40 bg-exception-info-wash text-exception-info-text',
    gap: 'border-state-dryrun-rail/40 bg-state-dryrun-wash text-state-dryrun-text',
    open: 'border-exception-warning-rail/50 bg-exception-warning-wash text-exception-warning-text',
  }[tone]
  return (
    <span title={title} className={`inline-flex h-5 items-center gap-1 whitespace-nowrap rounded-full border px-2 text-label ${cls}`}>
      {tone === 'lock' ? (
        <svg width="9" height="9" viewBox="0 0 12 12" fill="none" aria-hidden>
          <rect x="2" y="5.5" width="8" height="5.5" rx="1" stroke="currentColor" strokeWidth="1.3" />
          <path d="M4 5.5V4a2 2 0 014 0v1.5" stroke="currentColor" strokeWidth="1.3" />
        </svg>
      ) : null}
      {children}
    </span>
  )
}

export function Badges({ def }: { def: SettingDef }) {
  return (
    <>
      {def.regulated ? <Badge tone="lock" title={def.regulated}>Fixed</Badge> : null}
      {def.tariff ? <Badge tone="tariff" title="Editable, but must match the filed tariff or ordinance">Tariff-bound</Badge> : null}
      {def.open ? <Badge tone="open" title={def.open}>Open question</Badge> : null}
      {def.gap ? <Badge tone="gap" title="Ruled configurable; the schema has no column for it yet">Not in schema yet</Badge> : null}
    </>
  )
}

/** The legend for the badges, shown once per page. */
export function BadgeLegend() {
  return (
    <div className="flex flex-wrap items-center gap-x-4 gap-y-1.5 text-micro text-ink-tertiary">
      <span className="flex items-center gap-1.5"><Badge tone="lock" title="">Fixed</Badge> statute or platform rule, shown not set</span>
      <span className="flex items-center gap-1.5"><Badge tone="tariff" title="">Tariff-bound</Badge> must match the filing</span>
      <span className="flex items-center gap-1.5"><Badge tone="open" title="">Open question</Badge> not yet ruled</span>
      <span className="flex items-center gap-1.5"><Badge tone="gap" title="">Not in schema yet</Badge> built to the spec</span>
    </div>
  )
}

/* ---- Controls --------------------------------------------------------- */

export function Switch({ on, onChange, label, disabled }: { on: boolean; onChange: (v: boolean) => void; label: string; disabled?: boolean }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={on}
      aria-label={label}
      disabled={disabled}
      onClick={() => onChange(!on)}
      className={`relative inline-flex h-5 w-9 shrink-0 items-center rounded-full border transition-colors duration-fast disabled:cursor-not-allowed disabled:opacity-60 ${
        on ? 'border-accent bg-accent' : 'border-rule-solid bg-surface-sunken'
      }`}
    >
      <span
        aria-hidden
        className={`inline-block h-3.5 w-3.5 rounded-full bg-surface-raised shadow-panel transition-transform duration-fast ${on ? 'translate-x-[18px]' : 'translate-x-[2px]'}`}
      />
    </button>
  )
}

function Suffixed({ unit, children }: { unit?: string; children: ReactNode }) {
  return (
    <div className="flex items-center gap-2">
      {children}
      {unit ? <span className="mt-1 text-micro text-ink-tertiary whitespace-nowrap">{unit}</span> : null}
    </div>
  )
}

const num = (s: string) => (s.trim() === '' ? null : Number(s))

/** A comma-separated list of numbers, edited as text so a half-typed list never jumps. */
function ListInput({ id, value, onChange, invalid }: { id: string; value: number[]; onChange: (v: number[]) => void; invalid: boolean }) {
  const [text, setText] = useState(value.join(', '))
  useEffect(() => {
    setText((t) => (t.split(',').map((x) => Number(x.trim())).join(',') === value.join(',') ? t : value.join(', ')))
  }, [value])
  return (
    <input
      id={id}
      className={`${controlClass} w-40`}
      aria-invalid={invalid || undefined}
      value={text}
      onChange={(e) => {
        setText(e.target.value)
        onChange(e.target.value.split(',').map((x) => x.trim()).filter(Boolean).map(Number))
      }}
    />
  )
}

function RowsEditor({ def, value, onChange }: { def: Extract<SettingDef, { kind: 'rows' }>; value: Row[]; onChange: (v: Row[]) => void }) {
  const set = (i: number, k: string, v: string | number | boolean) => onChange(value.map((r, j) => (j === i ? { ...r, [k]: v } : r)))
  const small = 'h-7 w-full rounded-sm border border-rule-solid bg-surface-raised px-2 text-data text-ink-primary placeholder:text-ink-muted aria-invalid:border-exception-critical-rail'
  return (
    <div className="overflow-x-auto rounded-sm border border-rule-hair">
      <table className="w-full text-data">
        <thead className="bg-surface-sunken">
          <tr>
            {def.columns.map((c) => (
              <th key={c.key} scope="col" className="px-2 py-1.5 text-left text-label font-medium text-ink-tertiary whitespace-nowrap">
                {c.label}
                {c.kind === 'number' && c.unit ? <span className="font-normal"> ({c.unit})</span> : null}
                {c.kind === 'percent' ? <span className="font-normal"> (%)</span> : null}
              </th>
            ))}
            {def.fixedRows ? null : <th className="w-8" aria-label="Remove" />}
          </tr>
        </thead>
        <tbody className="divide-y divide-rule-hair">
          {value.map((r, i) => (
            <tr key={i}>
              {def.columns.map((c) => {
                const v = r[c.key]
                const label = `${c.label}, row ${i + 1}`
                const bad = validateCell(c, v) !== null
                return (
                  <td key={c.key} className="px-2 py-1 align-middle">
                    {c.kind === 'text' && c.readOnly ? (
                      <span className="text-ink-primary whitespace-nowrap">{String(v)}</span>
                    ) : c.kind === 'toggle' ? (
                      <Switch on={Boolean(v)} onChange={(x) => set(i, c.key, x)} label={label} />
                    ) : c.kind === 'select' ? (
                      <select aria-label={label} className={small} value={String(v)} onChange={(e) => set(i, c.key, e.target.value)}>
                        {c.options.map((o) => (
                          <option key={o.value} value={o.value}>{o.label}</option>
                        ))}
                      </select>
                    ) : c.kind === 'number' || c.kind === 'percent' ? (
                      <input
                        aria-label={label}
                        type="number"
                        className={`${small} min-w-16 text-right figures`}
                        aria-invalid={bad || undefined}
                        min={c.min}
                        max={c.max}
                        step={c.kind === 'percent' ? 0.01 : 1}
                        value={v === '' || v == null ? '' : Number(v)}
                        onChange={(e) => set(i, c.key, e.target.value === '' ? '' : Number(e.target.value))}
                      />
                    ) : c.kind === 'date' ? (
                      <input aria-label={label} type="date" className={small} aria-invalid={bad || undefined} value={String(v)} onChange={(e) => set(i, c.key, e.target.value)} />
                    ) : (
                      <input
                        aria-label={label}
                        className={`${small} ${c.kind === 'money' ? 'min-w-20 text-right figures' : 'min-w-24'}`}
                        aria-invalid={bad || undefined}
                        placeholder={c.kind === 'text' ? c.placeholder : '0.00'}
                        inputMode={c.kind === 'money' ? 'decimal' : undefined}
                        value={String(v ?? '')}
                        onChange={(e) => set(i, c.key, e.target.value)}
                      />
                    )}
                  </td>
                )
              })}
              {def.fixedRows ? null : (
                <td className="px-1 py-1 text-right">
                  <button
                    type="button"
                    aria-label={`Remove row ${i + 1}`}
                    onClick={() => onChange(value.filter((_, j) => j !== i))}
                    className="flex h-6 w-6 items-center justify-center rounded-full text-ink-tertiary hover:bg-surface-sunken hover:text-exception-critical-text"
                  >
                    <svg width="10" height="10" viewBox="0 0 12 12" aria-hidden>
                      <path d="M2 2l8 8M10 2l-8 8" stroke="currentColor" strokeWidth="1.5" />
                    </svg>
                  </button>
                </td>
              )}
            </tr>
          ))}
        </tbody>
      </table>
      {def.fixedRows ? null : (
        <div className="border-t border-rule-hair bg-surface px-2 py-1.5">
          <button
            type="button"
            onClick={() => onChange([...value, { ...(def.newRow ?? {}) }])}
            className="text-micro font-medium text-accent-text hover:text-accent-text-hover"
          >
            + {def.addLabel ?? 'Add row'}
          </button>
        </div>
      )}
    </div>
  )
}

export function FieldControl({
  def,
  id,
  value,
  onChange,
  error,
}: {
  def: SettingDef
  id: string
  value: SettingValue
  onChange: (v: SettingValue) => void
  error: string | null
}) {
  const invalid = error !== null

  if (def.regulated) {
    return (
      <p className="text-data text-ink-primary">
        {def.kind === 'toggle' ? (value ? 'Always on' : 'Always off') : describe(def, value)}
      </p>
    )
  }

  switch (def.kind) {
    case 'appearance':
      return <ThemeControl bare />
    case 'toggle':
      return (
        <div className="flex items-center gap-2">
          <Switch on={Boolean(value)} onChange={onChange} label={def.label} />
          <span className="text-micro text-ink-secondary">{value ? 'On' : 'Off'}</span>
        </div>
      )
    case 'select':
      return (
        <>
          <select id={id} className={`${controlClass} w-full max-w-sm`} value={String(value)} onChange={(e) => onChange(e.target.value)}>
            {def.options.map((o) => (
              <option key={o.value} value={o.value}>
                {o.label}
              </option>
            ))}
          </select>
          {def.caution?.[String(value)] ? (
            <StateBlock tone="warning" className="mt-2 !px-3 !py-2">
              <p className="text-micro text-exception-warning-text">{def.caution[String(value)]}</p>
            </StateBlock>
          ) : null}
        </>
      )
    case 'number':
      return (
        <Suffixed unit={def.unit}>
          <input
            id={id}
            type="number"
            className={`${controlClass} w-28 text-right figures`}
            aria-invalid={invalid || undefined}
            min={def.min}
            max={def.max}
            step={def.step ?? 1}
            placeholder={def.nullable ? 'None' : undefined}
            value={value == null ? '' : Number(value)}
            onChange={(e) => onChange(num(e.target.value))}
          />
        </Suffixed>
      )
    case 'percent':
      return (
        <Suffixed unit="%">
          <input
            id={id}
            type="number"
            className={`${controlClass} w-28 text-right figures`}
            aria-invalid={invalid || undefined}
            min={def.min ?? 0}
            max={def.max}
            step={def.step ?? 1}
            value={value == null ? '' : Number(value)}
            onChange={(e) => onChange(num(e.target.value))}
          />
        </Suffixed>
      )
    case 'money':
      return (
        <div className="relative w-32">
          <span aria-hidden className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-data text-ink-tertiary">$</span>
          <input
            id={id}
            inputMode="decimal"
            className={`${controlClass} pl-5 text-right figures`}
            aria-invalid={invalid || undefined}
            value={String(value ?? '')}
            onChange={(e) => onChange(e.target.value)}
          />
        </div>
      )
    case 'text':
      return (
        <input
          id={id}
          className={`${controlClass} w-full max-w-sm`}
          aria-invalid={invalid || undefined}
          placeholder={def.placeholder}
          value={String(value ?? '')}
          onChange={(e) => onChange(e.target.value)}
        />
      )
    case 'time':
      return <input id={id} type="time" className={`${controlClass} w-32`} value={String(value)} onChange={(e) => onChange(e.target.value)} />
    case 'list':
      return (
        <Suffixed unit={def.unit}>
          <ListInput id={id} value={(value as number[]) ?? []} onChange={onChange} invalid={invalid} />
        </Suffixed>
      )
    case 'months':
    case 'multi': {
      const opts = def.kind === 'months' ? MONTHS : def.options
      const list = (value as string[]) ?? []
      return (
        <div className="flex flex-wrap gap-1.5">
          {opts.map((o) => (
            <Chip
              key={o.value}
              on={list.includes(o.value)}
              onClick={() => onChange(list.includes(o.value) ? list.filter((x) => x !== o.value) : [...list, o.value])}
            >
              {o.label}
            </Chip>
          ))}
        </div>
      )
    }
    case 'rows':
      return <RowsEditor def={def} value={(value as Row[]) ?? []} onChange={onChange} />
  }
}
