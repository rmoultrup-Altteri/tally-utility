'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import {
  CATEGORIES,
  CHANNEL_LABEL,
  templates,
  type Category,
  type Channel,
  type Template,
} from '@/fixtures/templates'
import { contentWith, useTemplateVersions, type TemplateVersion } from '@/lib/templates-store'
import { Panel, PanelHeader } from '@/components/ui/Panel'
import { StateFlag } from '@/components/ui/State'
import { Chip, Group } from '@/components/ui/Chip'
import { Table, HeadRow, Th, Row, Td } from '@/components/table/Table'
import { askAssistant } from '@/lib/assistant/bus'
import { stamp } from '@/lib/format'
import { matchesSearch } from '@/lib/search'

/**
 * The template library: every message the utility sends, grouped by what it
 * is for. The list answers the three questions a supervisor asks of it — is
 * there one for this, is it in Spanish, and who changed it last.
 */

const CHANNELS: Channel[] = ['email', 'sms', 'letter']

function hasSpanish(t: Template, versions: TemplateVersion[]) {
  const c = contentWith(t, versions)
  return t.channels.every((ch) => c[ch]?.es?.body)
}

export function TemplateLibrary() {
  const versions = useTemplateVersions()
  const [query, setQuery] = useState('')
  const [category, setCategory] = useState<Category | null>(null)
  const [channel, setChannel] = useState<Channel | null>(null)
  const [noSpanish, setNoSpanish] = useState(false)

  const lastEdit = useMemo(() => {
    const m = new Map<string, TemplateVersion>()
    for (const v of versions) m.set(v.templateId, v)
    return m
  }, [versions])

  const rows = templates.filter(
    (t) =>
      (!category || t.category === category) &&
      (!channel || t.channels.includes(channel)) &&
      (!noSpanish || !hasSpanish(t, versions)) &&
      matchesSearch(query, [t.name, t.purpose, t.trigger, t.category]),
  )

  const spanishCount = templates.filter((t) => hasSpanish(t, versions)).length
  const regulatory = templates.filter((t) => t.kind === 'regulatory').length
  const editedHere = new Set(versions.map((v) => v.templateId)).size

  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-px overflow-clip rounded-md bg-rule-hair border border-rule-hair shadow-panel">
        <Stat label="Templates" sub="Letters, emails and texts in one place">
          {templates.length}
        </Stat>
        <Stat label="In English and Spanish" sub={`${templates.length - spanishCount} still English only`}>
          {spanishCount}
        </Stat>
        <Stat label="Carry required text" sub="Rule-prescribed wording, cited and locked">
          {regulatory}
        </Stat>
        <Stat label="Edited in this browser" sub="Every save is a new version">
          {editedHere}
        </Stat>
      </div>

      <Panel>
        <div className="flex flex-wrap items-center gap-x-5 gap-y-2 border-b border-rule-hair px-4 py-2.5">
          <label className="sr-only" htmlFor="tpl-search">
            Search templates
          </label>
          <input
            id="tpl-search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search templates…"
            className="h-7 w-56 rounded-full border border-rule-solid bg-surface-raised px-3 text-data text-ink-primary placeholder:text-ink-muted"
          />
          <Group label="Category">
            {CATEGORIES.map((c) => (
              <Chip key={c} on={category === c} onClick={() => setCategory(category === c ? null : c)}>
                {c}
              </Chip>
            ))}
          </Group>
          <Group label="Channel">
            {CHANNELS.map((c) => (
              <Chip key={c} on={channel === c} onClick={() => setChannel(channel === c ? null : c)}>
                {CHANNEL_LABEL[c]}
              </Chip>
            ))}
          </Group>
          <Chip on={noSpanish} onClick={() => setNoSpanish(!noSpanish)}>
            Missing Spanish
          </Chip>
          {noSpanish && rows.length > 0 ? (
            <button
              type="button"
              onClick={() =>
                askAssistant(
                  `Write the missing Spanish version of the "${rows[0].name}" template (${rows[0].id}) for every channel it uses, keeping every merge field and required text exactly. Stage each one for me to review.`,
                )
              }
              className="ml-auto text-micro text-accent-text hover:text-accent-text-hover underline"
            >
              Ask the assistant to write Spanish for “{rows[0].name}”
            </button>
          ) : null}
        </div>

        {CATEGORIES.filter((c) => rows.some((t) => t.category === c)).map((c) => {
          const group = rows.filter((t) => t.category === c)
          return (
            <div key={c}>
              <PanelHeader title={c} meta={`${group.length} template${group.length === 1 ? '' : 's'}`} />
              <Table caption={`${c} templates`}>
                <thead>
                  <HeadRow>
                    <Th width="34%">Template</Th>
                    <Th width="22%">Sent when</Th>
                    <Th width="16%">Channels</Th>
                    <Th width="9%">Languages</Th>
                    <Th width="19%">Last changed</Th>
                  </HeadRow>
                </thead>
                <tbody>
                  {group.map((t) => {
                    const edit = lastEdit.get(t.id)
                    const content = contentWith(t, versions)
                    return (
                      <Row key={t.id}>
                        <Td>
                          <div className="flex items-center gap-2">
                            <Link
                              href={`/communications/${t.id}` as Route}
                              className="text-data font-medium text-accent-text hover:text-accent-text-hover underline"
                            >
                              {t.name}
                            </Link>
                            {t.kind === 'regulatory' ? (
                              <StateFlag tone="info" title="Carries wording a rule prescribes">
                                Required text
                              </StateFlag>
                            ) : null}
                          </div>
                          <p className="text-micro text-ink-secondary mt-0.5">{t.purpose}</p>
                        </Td>
                        <Td>
                          <p className="text-micro text-ink-secondary">{t.trigger}</p>
                          {t.usedBy ? (
                            <Link
                              href={t.usedBy.href as Route}
                              className="text-micro text-accent-text hover:text-accent-text-hover underline"
                            >
                              {t.usedBy.label}
                            </Link>
                          ) : null}
                        </Td>
                        <Td>
                          <div className="flex flex-wrap gap-1">
                            {t.channels.map((ch) => (
                              <span
                                key={ch}
                                className="inline-flex h-5 items-center rounded-full border border-rule-solid bg-surface px-2 text-micro text-ink-secondary"
                              >
                                {CHANNEL_LABEL[ch]}
                              </span>
                            ))}
                          </div>
                        </Td>
                        <Td>
                          <span className="ident text-ink-primary">EN</span>{' '}
                          {t.channels.every((ch) => content[ch]?.es?.body) ? (
                            <span className="ident text-ink-primary">ES</span>
                          ) : t.channels.some((ch) => content[ch]?.es?.body) ? (
                            <span className="ident text-exception-warning-text" title="Spanish on some channels only">
                              ES·
                            </span>
                          ) : (
                            <span className="ident struck" title="No Spanish version yet">
                              ES
                            </span>
                          )}
                        </Td>
                        <Td>
                          {edit ? (
                            <>
                              <p className="text-micro text-ink-primary">
                                {edit.by}
                                {edit.source === 'assistant' ? ' · with the assistant' : ''}
                              </p>
                              <p className="text-micro text-ink-tertiary">{stamp(edit.at)}</p>
                            </>
                          ) : (
                            <>
                              <p className="text-micro text-ink-secondary">{t.updatedBy}</p>
                              <p className="text-micro text-ink-tertiary">{stamp(t.updatedAt)}</p>
                            </>
                          )}
                        </Td>
                      </Row>
                    )
                  })}
                </tbody>
              </Table>
            </div>
          )
        })}
        {rows.length === 0 ? (
          <p className="px-4 py-6 text-data text-ink-secondary">No template matches. Clear a filter to see more.</p>
        ) : null}
      </Panel>
    </div>
  )
}

function Stat({ label, sub, children }: { label: string; sub: string; children: React.ReactNode }) {
  return (
    <div className="bg-surface-raised px-4 py-3">
      <p className="field-label">{label}</p>
      <p className="text-figure text-ink-primary mt-1">{children}</p>
      <p className="text-micro text-ink-tertiary mt-0.5">{sub}</p>
    </div>
  )
}
