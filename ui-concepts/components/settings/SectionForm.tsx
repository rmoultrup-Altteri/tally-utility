'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Panel, PanelHeader } from '@/components/ui/Panel'
import { sectionByKey, type SectionKey, type SettingDef } from '@/fixtures/settings'
import { asOf } from '@/fixtures/tenant'
import { dateShort } from '@/lib/format'
import { saveSettings, useSettings, type SettingValue } from '@/lib/settings-store'
import { Badges, FieldControl, changeLines, validate, type ChangeLine } from './fields'
import { SaveBar } from './SaveFlow'

const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b)

/**
 * One settings section as a form. Values in force are the catalog defaults
 * overlaid with anything saved in this browser; the draft holds only what
 * the operator has touched, so a save elsewhere never gets clobbered by a
 * stale copy of the whole section.
 */
export function SectionForm({ sectionKey }: { sectionKey: SectionKey }) {
  const section = sectionByKey.get(sectionKey)!
  const store = useSettings()
  const [draft, setDraft] = useState<Record<string, SettingValue>>({})

  const defs = useMemo(() => section.groups.flatMap((g) => g.settings), [section])

  const inForce = useMemo(() => {
    const v: Record<string, SettingValue> = {}
    for (const d of defs) v[d.key] = d.key in store.values ? store.values[d.key] : (d.default as SettingValue)
    return v
  }, [defs, store.values])

  const value = (k: string) => (k in draft ? draft[k] : inForce[k])
  const visible = (d: SettingDef) => !d.showWhen || value(d.showWhen.key) === d.showWhen.equals

  /** A future-dated save is shown beside the setting it will change. */
  const scheduled = useMemo(() => {
    const out: Record<string, string> = {}
    for (const e of store.log) if (e.effectiveFrom > asOf.validAt) out[e.key] = e.effectiveFrom
    return out
  }, [store.log])

  const changed = defs.filter((d) => d.key in draft && !same(draft[d.key], inForce[d.key]))
  const lines: ChangeLine[] = changed.flatMap((d) => changeLines(d, inForce[d.key], draft[d.key]))
  const errors = Object.fromEntries(defs.filter(visible).map((d) => [d.key, validate(d, value(d.key))]))
  const firstError = changed.map((d) => (visible(d) ? errors[d.key] : null)).find(Boolean) ?? null
  /* A field revealed by a change (the donation fund name) must be valid too. */
  const revealedError = defs.filter((d) => d.showWhen && visible(d) && errors[d.key]).map((d) => errors[d.key])[0] ?? null
  const blocked = firstError || revealedError ? 'Fix the highlighted settings first.' : null

  function save(effectiveFrom: string, reason: string) {
    const next: Record<string, SettingValue> = {}
    for (const d of changed) next[d.key] = draft[d.key]
    for (const d of defs) if (d.showWhen && visible(d) && d.key in draft) next[d.key] = draft[d.key]
    saveSettings(inForce, next, effectiveFrom, reason)
    setDraft({})
  }

  return (
    <>
      <div className="space-y-5">
        {section.groups.map((g) => (
          <Panel key={g.title}>
            <PanelHeader
              title={g.title}
              actions={
                g.link ? (
                  <Link href={g.link.href as Route} className="text-micro font-medium text-accent-text hover:text-accent-text-hover">
                    {g.link.label} →
                  </Link>
                ) : null
              }
            />
            {g.note ? <p className="px-4 pt-3 text-micro text-ink-secondary">{g.note}</p> : null}
            <div className="divide-y divide-rule-hair">
              {g.settings.filter(visible).map((d) => {
                const id = `s-${d.key.replace(/\./g, '-')}`
                const err = errors[d.key] ?? null
                const showErr = err && (d.key in draft || (d.showWhen && visible(d))) ? err : null
                const wide = d.kind === 'rows' || d.kind === 'months' || d.kind === 'multi'
                const dirty = changed.includes(d)
                return (
                  <div key={d.key} className={`px-4 py-3 ${wide ? '' : 'sm:grid sm:grid-cols-[minmax(0,1fr)_minmax(0,1.1fr)] sm:gap-6'}`}>
                    <div className="min-w-0">
                      <div className="flex flex-wrap items-center gap-1.5">
                        <label htmlFor={id} className="text-data font-medium text-ink-primary">
                          {d.label}
                        </label>
                        {dirty ? <span aria-label="changed" className="h-1.5 w-1.5 rounded-full bg-accent" /> : null}
                        <Badges def={d} />
                        {scheduled[d.key] ? (
                          <span className="rounded-full bg-accent-wash px-2 text-label leading-5 text-accent-text">
                            New value from {dateShort(scheduled[d.key])}
                          </span>
                        ) : null}
                      </div>
                      {d.hint || d.regulated || d.open || d.citation || (d.kind === 'number' && d.nullable && value(d.key) == null) ? (
                        <div className="mt-0.5 space-y-0.5 text-micro text-ink-tertiary">
                          {d.hint ? <p>{d.hint}</p> : null}
                          {d.regulated ? <p>{d.regulated}</p> : null}
                          {d.open ? <p className="text-exception-warning-text">{d.open}</p> : null}
                          {d.kind === 'number' && d.nullable && value(d.key) == null ? (
                            <p className="text-exception-warning-text">{d.nullable}</p>
                          ) : null}
                          {d.citation ? <p className="ident">{d.citation}</p> : null}
                        </div>
                      ) : null}
                    </div>
                    <div className={wide ? 'mt-2' : 'mt-2 sm:mt-0'}>
                      <FieldControl
                        def={d}
                        id={id}
                        value={value(d.key)}
                        error={showErr}
                        onChange={(v) => setDraft((x) => ({ ...x, [d.key]: v }))}
                      />
                      {showErr ? <p className="mt-1 text-micro text-exception-critical-text">{showErr}</p> : null}
                    </div>
                  </div>
                )
              })}
            </div>
            {g.fixed?.length ? (
              <div className="border-t border-rule-hair bg-surface px-4 py-3">
                <p className="field-label mb-1 flex items-center gap-1.5">
                  <svg width="10" height="10" viewBox="0 0 12 12" fill="none" aria-hidden>
                    <rect x="2" y="5.5" width="8" height="5.5" rx="1" stroke="currentColor" strokeWidth="1.3" />
                    <path d="M4 5.5V4a2 2 0 014 0v1.5" stroke="currentColor" strokeWidth="1.3" />
                  </svg>
                  Not settings — always true
                </p>
                <ul className="list-disc space-y-0.5 pl-4 text-micro text-ink-secondary">
                  {g.fixed.map((f) => (
                    <li key={f}>{f}</li>
                  ))}
                </ul>
              </div>
            ) : null}
          </Panel>
        ))}
      </div>
      <SaveBar
        lines={lines}
        blocked={blocked}
        mode={section.personal ? 'personal' : 'dated'}
        onDiscard={() => setDraft({})}
        onSave={(r) => save(r.effectiveFrom, r.reason)}
      />
    </>
  )
}
