import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { TemplateLibrary } from '@/components/communications/TemplateLibrary'
import { templates } from '@/fixtures/templates'

/**
 * Communications — every message the utility sends a customer.
 *
 * Legacy systems scatter these: dunning letters in one module, outage texts in
 * a vendor portal, the welcome email in someone's Outlook drafts. Here they are
 * one versioned catalog that every sending feature reads, edited in place or
 * through the assistant, with rule-prescribed wording that cannot be lost.
 */

export default function CommunicationsPage() {
  return (
    <AppShell current="Communications">
      <PageHeader
        title="Communications"
        meta={`${templates.length} templates · every letter, email and text a customer receives`}
      />
      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5">
          <TemplateLibrary />
        </div>
      </div>
    </AppShell>
  )
}
