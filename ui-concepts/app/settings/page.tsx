import Link from 'next/link'
import type { Route } from 'next'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { SettingsNav } from '@/components/settings/SettingsNav'
import { ChangeHistory, DunningCard } from '@/components/settings/Overview'
import { BadgeLegend } from '@/components/settings/fields'
import { SettingsGate } from '@/components/settings/SettingsGate'
import { AREAS, SECTIONS, type SettingSection } from '@/fixtures/settings'
import { tenant } from '@/fixtures/tenant'

/**
 * Settings, reached from the operator's name at top right.
 *
 * Every tenant-configurable value from the configurable-rules review lives
 * under one of these sections. The overview leads with automatic dunning,
 * because it is the setting most worth turning on and the one most often
 * left off.
 *
 * The whole page is for roles holding Change settings; anyone else sees why
 * not, and is pointed to their own preferences.
 */

function counts(s: SettingSection) {
  const all = s.groups.flatMap((g) => g.settings)
  return {
    editable: all.filter((d) => !d.regulated).length,
    fixed: all.filter((d) => d.regulated).length + s.groups.reduce((n, g) => n + (g.fixed?.length ?? 0), 0),
    tariff: all.filter((d) => d.tariff).length,
  }
}

export default function SettingsPage() {
  return (
    <AppShell current="Settings">
      <PageHeader
        title="Settings"
        meta={<>{tenant.name} · each change takes effect from a date you choose and is kept as history</>}
      />
      <div className="flex-1 overflow-auto">
        <div className="flex gap-6 px-5 py-5">
          <aside className="hidden w-52 shrink-0 lg:block">
            <div className="sticky top-0">
              <SettingsNav />
            </div>
          </aside>
          <div className="min-w-0 flex-1">
            <SettingsGate>
              <div className="space-y-6">
                <DunningCard />

                {AREAS.map((area) => (
                  <section key={area}>
                    <h2 className="field-label mb-2">{area}</h2>
                    <div className="grid grid-cols-1 gap-3 md:grid-cols-2 2xl:grid-cols-3">
                      {SECTIONS.filter((s) => s.area === area && s.key !== 'dunning').map((s) => {
                        const n = counts(s)
                        return (
                          <Link
                            key={s.key}
                            href={`/settings/${s.key}` as Route}
                            className="block rounded-md border border-rule-hair bg-surface-raised px-4 py-3 shadow-panel transition-colors duration-fast hover:border-rule-solid hover:bg-surface"
                          >
                            <span className="block text-h3 text-ink-primary">{s.title}</span>
                            <span className="mt-0.5 block text-micro text-ink-secondary">{s.summary}</span>
                            <span className="mt-2 block text-micro text-ink-tertiary">
                              {s.custom ? 'Its own screen' : n.editable ? `${n.editable} ${n.editable === 1 ? 'setting' : 'settings'}` : 'Nothing to set'}
                              {n.tariff ? ` · ${n.tariff} tariff-bound` : ''}
                              {n.fixed ? ` · ${n.fixed} fixed ${n.fixed === 1 ? 'rule' : 'rules'}` : ''}
                            </span>
                          </Link>
                        )
                      })}
                    </div>
                  </section>
                ))}

                <BadgeLegend />
                <ChangeHistory />
              </div>
            </SettingsGate>
          </div>
        </div>
      </div>
    </AppShell>
  )
}
