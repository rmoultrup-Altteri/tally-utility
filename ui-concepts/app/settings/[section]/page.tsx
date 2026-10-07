import { notFound } from 'next/navigation'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { SettingsNav } from '@/components/settings/SettingsNav'
import { SectionForm } from '@/components/settings/SectionForm'
import { DunningSetup } from '@/components/settings/DunningSetup'
import { BadgeLegend } from '@/components/settings/fields'
import { RolesAccess } from '@/components/settings/RolesAccess'
import { SettingsGate } from '@/components/settings/SettingsGate'
import { SECTIONS, sectionByKey, type SectionKey } from '@/fixtures/settings'

/**
 * One settings section. Dunning and roles have their own screens; the rest
 * share one form. Everything but the operator's own preferences sits behind
 * Change settings.
 */

export function generateStaticParams() {
  return SECTIONS.map((s) => ({ section: s.key }))
}

export default async function SettingsSectionPage({ params }: PageProps<'/settings/[section]'>) {
  const { section: key } = await params
  const section = sectionByKey.get(key as SectionKey)
  if (!section) notFound()

  return (
    <AppShell current="Settings">
      <PageHeader back={{ href: '/settings', label: 'Settings' }} title={section.title} meta={section.summary} />
      <div className="flex-1 overflow-auto">
        <div className="flex gap-6 px-5 pt-5 pb-1">
          <aside className="hidden w-52 shrink-0 lg:block">
            <div className="sticky top-5">
              <SettingsNav current={section.key} />
            </div>
          </aside>
          <div className="min-w-0 flex-1 max-w-5xl pb-4">
            {section.personal ? (
              <SectionForm sectionKey={section.key} />
            ) : (
              <SettingsGate>
                {section.key === 'dunning' ? (
                  <DunningSetup />
                ) : section.key === 'roles' ? (
                  <RolesAccess />
                ) : (
                  <>
                    <div className="mb-4">
                      <BadgeLegend />
                    </div>
                    <SectionForm sectionKey={section.key} />
                  </>
                )}
              </SettingsGate>
            )}
          </div>
        </div>
      </div>
    </AppShell>
  )
}
