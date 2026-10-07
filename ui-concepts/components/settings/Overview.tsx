'use client'

import Link from 'next/link'
import type { Route } from 'next'
import { Panel, PanelHeader } from '@/components/ui/Panel'
import { StateFlag } from '@/components/ui/State'
import { DEFAULT_DUNNING, PRESETS, type DunningConfig } from '@/fixtures/dunning'
import { settingByKey } from '@/fixtures/settings'
import { asOf } from '@/fixtures/tenant'
import { date, stamp } from '@/lib/format'
import { useSettings } from '@/lib/settings-store'
import { describe } from './fields'

/** The dunning call to action at the top of the overview — the thing most worth setting up. */
export function DunningCard() {
  const { values } = useSettings()
  const c: DunningConfig = { ...DEFAULT_DUNNING, ...((values.dunning as Partial<DunningConfig>) ?? {}) }
  const preset = PRESETS.find((p) => p.key === c.preset)?.title ?? 'Custom'
  const state =
    c.mode === 'on'
      ? { tone: 'approved' as const, word: 'Running', body: `${preset} schedule, every morning at ${c.runTime}.` }
      : c.mode === 'preview'
        ? { tone: 'pending' as const, word: 'In preview', body: `${preset} schedule. Evaluating daily and showing results on the worklist — nothing is sent.` }
        : { tone: 'draft' as const, word: 'Off', body: 'Reminders, late fees and termination notices are worked by hand. Set up takes about a minute.' }
  return (
    <Panel className="border-accent/40">
      <div className="flex flex-wrap items-center justify-between gap-4 px-4 py-4">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <h2 className="text-h2 text-ink-primary">Automatic dunning</h2>
            <StateFlag tone={state.tone}>{state.word}</StateFlag>
          </div>
          <p className="mt-0.5 text-data text-ink-secondary">{state.body}</p>
        </div>
        <Link
          href={'/settings/dunning' as Route}
          className="inline-flex h-8 items-center justify-center rounded-sm border border-accent bg-accent px-3.5 text-data font-medium text-ink-inverse hover:bg-accent-hover"
        >
          {c.mode === 'off' ? 'Set up dunning' : 'Change dunning'}
        </Link>
      </div>
    </Panel>
  )
}

/** Settings with their own screens, which the catalog does not describe value by value. */
const CUSTOM_LABEL: Record<string, string> = {
  dunning: 'Dunning',
  'org.roles': 'Roles',
  'org.members': 'Role assignments',
}

/** Every change saved, newest first — tenant configuration is history, so this is the record of it. */
export function ChangeHistory() {
  const { log } = useSettings()
  const rows = log.filter((e) => !e.key.startsWith('me.')).slice().reverse().slice(0, 25)
  return (
    <Panel>
      <PanelHeader title="Change history" meta={rows.length ? `${rows.length} most recent` : undefined} />
      {rows.length ? (
        <ul className="divide-y divide-rule-hair">
          {rows.map((e, i) => {
            const def = settingByKey.get(e.key)
            const label = def?.label ?? CUSTOM_LABEL[e.key] ?? e.key
            const show = (v: unknown) => (def && def.kind !== 'rows' ? describe(def, v as never) : def ? 'updated' : '')
            const from = show(e.from)
            const to = show(e.to)
            return (
              <li key={i} className="px-4 py-2.5">
                <div className="flex flex-wrap items-baseline justify-between gap-x-4">
                  <p className="text-data text-ink-primary">
                    <span className="font-medium">{label}</span>
                    {from || to ? (
                      <>
                        {' '}
                        <span className="text-ink-tertiary">{from}</span> <span aria-hidden className="text-ink-tertiary">→</span>{' '}
                        <span>{to}</span>
                      </>
                    ) : null}
                  </p>
                  <p className="text-micro text-ink-tertiary">
                    {e.effectiveFrom > asOf.validAt ? 'From ' : 'In force '}
                    {date(e.effectiveFrom)}
                  </p>
                </div>
                <p className="mt-0.5 text-micro text-ink-tertiary">
                  {e.by} · {stamp(e.at)} · {e.reason}
                </p>
              </li>
            )
          })}
        </ul>
      ) : (
        <p className="px-4 py-4 text-micro text-ink-tertiary">
          No changes yet. Every saved change lands here with who made it, when it takes effect and why.
        </p>
      )}
    </Panel>
  )
}
