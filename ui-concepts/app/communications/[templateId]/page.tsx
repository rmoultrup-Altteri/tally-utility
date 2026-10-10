import Link from 'next/link'
import type { Route } from 'next'
import { notFound } from 'next/navigation'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { TemplateEditor } from '@/components/communications/TemplateEditor'
import { StateFlag } from '@/components/ui/State'
import { templateById, templates } from '@/fixtures/templates'

export function generateStaticParams() {
  return templates.map((t) => ({ templateId: t.id }))
}

export default async function TemplatePage({ params }: PageProps<'/communications/[templateId]'>) {
  const { templateId } = await params
  const template = templateById.get(templateId)
  if (!template) notFound()

  return (
    <AppShell current="Communications">
      <PageHeader
        back={{ href: '/communications', label: 'Communications' }}
        title={template.name}
        meta={
          <>
            {template.category} · sent when: {template.trigger.charAt(0).toLowerCase() + template.trigger.slice(1)}
            {template.usedBy ? (
              <>
                {' '}
                ·{' '}
                <Link href={template.usedBy.href as Route} className="underline hover:text-ink-secondary">
                  {template.usedBy.label}
                </Link>
              </>
            ) : null}
          </>
        }
        actions={
          <StateFlag tone={template.kind === 'regulatory' ? 'info' : template.kind === 'courtesy' ? 'cleared' : 'snoozed'}>
            {template.kind === 'regulatory' ? 'Regulatory' : template.kind === 'courtesy' ? 'Courtesy' : 'Transactional'}
          </StateFlag>
        }
      />
      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5">
          <p className="mb-4 max-w-3xl text-data text-ink-secondary">{template.purpose}</p>
          <TemplateEditor template={template} />
        </div>
      </div>
    </AppShell>
  )
}
