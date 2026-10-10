'use client'

import { useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import {
  CHANNEL_LABEL,
  LANG_LABEL,
  type Channel,
  type ChannelContent,
  type Lang,
  type Template,
} from '@/fixtures/templates'
import { customers, locationById, serviceLinks } from '@/fixtures/accounts'
import { customerName } from '@/schemas/models'
import { useTemplate, saveTemplateVersion, type TemplateVersion } from '@/lib/templates-store'
import { checkContent, contextFor, fill, smsShape } from '@/lib/templates'
import { InsertFieldMenu } from '@/components/communications/InsertFieldMenu'
import { useAccess } from '@/lib/access'
import { activeUserName } from '@/lib/session'
import { askAssistant } from '@/lib/assistant/bus'
import { MessagePreview } from '@/components/communications/MessagePreview'
import { Panel, PanelHeader, Button } from '@/components/ui/Panel'
import { StateBlock, StateFlag } from '@/components/ui/State'
import { stamp } from '@/lib/format'

/**
 * The template editor.
 *
 * Words on the left, the customer's view on the right, filled from a real
 * account. Two ways to change a template and one way to save it: type here,
 * or ask the assistant — which stages its edit as a card in the chat — and
 * either way a save is a new version with a reason, never an overwrite.
 *
 * Required text is shown beside the editor rather than inside it. The token
 * marks where it prints; the words belong to the rule that prescribes them.
 */

const key = (c: Channel, l: Lang) => `${c}:${l}`

const AI_ACTIONS: { label: string; ask: string }[] = [
  { label: 'Shorter', ask: 'make it shorter without losing anything the customer needs' },
  { label: 'Warmer', ask: 'make the tone warmer and more personal' },
  { label: 'Plainer', ask: 'rewrite it in plain language a sixth-grader could follow' },
  { label: 'Check it', ask: 'review it for tone, clarity and anything a regulator or customer could object to, and suggest one improved version' },
]

export function TemplateEditor({ template }: { template: Template }) {
  const { content, history } = useTemplate(template)
  const { can } = useAccess()
  const editable = can('communications.edit')

  const [channel, setChannel] = useState<Channel>(template.channels[0])
  const [lang, setLang] = useState<Lang>('en')
  const [drafts, setDrafts] = useState<Record<string, ChannelContent>>({})
  const [bases, setBases] = useState<Record<string, string | null>>({})
  const [reason, setReason] = useState('')
  const [previewAs, setPreviewAs] = useState('cus-0001')
  const [marks, setMarks] = useState(true)
  const [saved, setSaved] = useState<TemplateVersion | null>(null)
  const body = useRef<HTMLTextAreaElement>(null)
  const subjectRef = useRef<HTMLInputElement>(null)
  const lastFocus = useRef<'subject' | 'body'>('body')

  const k = key(channel, lang)
  const stored = content[channel]?.[lang] ?? null
  const latest = history.find((v) => v.channel === channel && v.lang === lang) ?? null
  const draft = drafts[k] ?? stored
  const dirty = drafts[k] !== undefined && JSON.stringify(drafts[k]) !== JSON.stringify(stored)
  /* Someone — usually the assistant — saved a version while this draft was open. */
  const overtaken = dirty && (bases[k] ?? null) !== (latest?.id ?? null)

  const ctx = useMemo(() => contextFor(previewAs, lang), [previewAs, lang])
  const customer = customers.find((c) => c.id === previewAs)!
  const link = serviceLinks.find((l) => l.customerId === previewAs)
  const loc = link ? locationById.get(link.locationId) : undefined
  const to = {
    name: customerName(customer),
    email: customer.email,
    phone: customer.phone,
    address: loc ? `${loc.address}, ${loc.city}, ${loc.state} ${loc.zip}` : '',
  }

  const issues = draft ? checkContent(template, channel, lang, draft) : []
  const errors = issues.filter((i) => i.level === 'error')
  const canSave = editable && dirty && errors.length === 0 && reason.trim().length >= 8

  function edit(patch: Partial<ChannelContent>) {
    if (!editable) return
    setSaved(null)
    if (drafts[k] === undefined) setBases((b) => ({ ...b, [k]: latest?.id ?? null }))
    setDrafts((d) => ({ ...d, [k]: { ...(d[k] ?? stored ?? { body: '' }), ...patch } }))
  }

  function insert(token: string) {
    const target = lastFocus.current === 'subject' && channel !== 'sms' ? subjectRef.current : body.current
    const field = lastFocus.current === 'subject' && channel !== 'sms' ? 'subject' : 'body'
    const value = (field === 'subject' ? draft?.subject : draft?.body) ?? ''
    const at = target?.selectionStart ?? value.length
    const end = target?.selectionEnd ?? at
    const next = value.slice(0, at) + token + value.slice(end)
    edit({ [field]: next })
    requestAnimationFrame(() => {
      target?.focus()
      target?.setSelectionRange(at + token.length, at + token.length)
    })
  }

  function discard() {
    setDrafts((d) => {
      const { [k]: _drop, ...rest } = d
      return rest
    })
    setReason('')
  }

  function save() {
    if (!canSave || !draft) return
    const v = saveTemplateVersion({
      templateId: template.id,
      channel,
      lang,
      before: stored,
      after: draft,
      reason: reason.trim(),
      by: activeUserName(),
      source: 'editor',
    })
    discard()
    setSaved(v)
  }

  function ask(what: string) {
    askAssistant(
      `Edit the "${template.name}" template (${template.id}), ${CHANNEL_LABEL[channel].toLowerCase()} in ${LANG_LABEL[lang]}: ${what}. Keep every merge field and required text. Stage the change for me to review.`,
    )
  }

  const sms = channel === 'sms' && draft ? smsShape(fill(draft.body, ctx), lang) : null

  return (
    <div className="grid grid-cols-1 xl:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] gap-5">
      {/* ==== The words ==== */}
      <div className="space-y-5 min-w-0">
        <Panel>
          <div className="flex flex-wrap items-center justify-between gap-3 border-b border-rule-hair px-4 py-2.5">
            <div role="tablist" aria-label="Channel" className="flex gap-1">
              {template.channels.map((c) => (
                <Tab key={c} on={c === channel} onClick={() => setChannel(c)} dot={drafts[key(c, lang)] !== undefined}>
                  {CHANNEL_LABEL[c]}
                </Tab>
              ))}
            </div>
            <div role="tablist" aria-label="Language" className="flex gap-1">
              {(['en', 'es'] as Lang[]).map((l) => (
                <Tab key={l} on={l === lang} onClick={() => setLang(l)} dot={drafts[key(channel, l)] !== undefined}>
                  {LANG_LABEL[l]}
                  {content[channel]?.[l] ? null : <span className="text-ink-tertiary"> · none yet</span>}
                </Tab>
              ))}
            </div>
          </div>

          {!editable ? (
            <div className="px-4 pt-3">
              <StateBlock tone="snoozed">
                <p className="text-data text-ink-primary">
                  Your role can read templates but not change them. <strong className="font-semibold">Edit communications</strong> is
                  held by administrators and billing analysts.
                </p>
              </StateBlock>
            </div>
          ) : null}

          {overtaken ? (
            <div className="px-4 pt-3">
              <StateBlock tone="warning">
                <p className="text-data text-ink-primary">
                  <strong className="font-semibold">A newer version was saved while you were editing</strong>
                  {latest ? ` — by ${latest.by}${latest.source === 'assistant' ? ' with the assistant' : ''}, ${stamp(latest.at)}` : ''}.
                  Saving now would replace it with your draft.{' '}
                  <button type="button" onClick={discard} className="text-accent-text underline">
                    Load the newer version
                  </button>
                </p>
              </StateBlock>
            </div>
          ) : null}

          {draft ? (
            <div className="px-4 py-4 space-y-3">
              {channel !== 'sms' ? (
                <div>
                  <label htmlFor="tpl-subject" className="field-label">
                    {channel === 'email' ? 'Subject line' : 'Heading'}
                  </label>
                  <input
                    id="tpl-subject"
                    ref={subjectRef}
                    value={draft.subject ?? ''}
                    readOnly={!editable}
                    onFocus={() => (lastFocus.current = 'subject')}
                    onChange={(e) => edit({ subject: e.target.value })}
                    className="mt-1 h-9 w-full rounded-sm border border-rule-solid bg-surface-raised px-2.5 text-body text-ink-primary"
                  />
                </div>
              ) : null}
              <div>
                <div className="flex items-center justify-between gap-3">
                  <label htmlFor="tpl-body" className="field-label">
                    Message
                  </label>
                  <div className="flex items-center gap-3">
                    {sms ? (
                      <span className={`text-micro ${sms.segments > 1 ? 'text-exception-warning-text' : 'text-ink-tertiary'}`}>
                        {sms.length} characters with the opt-out line · {sms.segments} message{sms.segments === 1 ? '' : 's'}
                      </span>
                    ) : null}
                    <InsertFieldMenu ctx={ctx} disabled={!editable} onInsert={insert} />
                  </div>
                </div>
                <textarea
                  id="tpl-body"
                  ref={body}
                  value={draft.body}
                  readOnly={!editable}
                  onFocus={() => (lastFocus.current = 'body')}
                  onChange={(e) => edit({ body: e.target.value })}
                  rows={channel === 'sms' ? 5 : 16}
                  className="mt-1 w-full rounded-sm border border-rule-solid bg-surface-raised px-3 py-2.5 text-body leading-relaxed text-ink-primary [field-sizing:content] min-h-32"
                />
                {channel === 'sms' ? (
                  <p className="mt-1 text-micro text-ink-tertiary">“Reply STOP to opt out.” is added to every text automatically.</p>
                ) : null}
              </div>

              {issues.length ? (
                <ul className="space-y-1">
                  {issues.map((i) => (
                    <li
                      key={i.text}
                      className={`text-micro ${i.level === 'error' ? 'text-exception-critical-text' : 'text-exception-warning-text'}`}
                    >
                      {i.level === 'error' ? 'Must fix · ' : 'Note · '}
                      {i.text}
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="text-micro text-exception-cleared-text">Every merge field resolves and the required text is in place.</p>
              )}

              {editable ? (
                <div className="flex flex-wrap items-center gap-1.5 border-t border-rule-hair pt-3">
                  <span className="field-label mr-1">Ask the assistant</span>
                  {AI_ACTIONS.map((a) => (
                    <button
                      key={a.label}
                      type="button"
                      onClick={() => ask(a.ask)}
                      className="inline-flex h-6 items-center rounded-full border border-rule-solid bg-surface-raised px-2.5 text-micro text-ink-secondary hover:border-rule-heavy hover:text-ink-primary"
                    >
                      {a.label}
                    </button>
                  ))}
                  {lang === 'en' && template.channels.some((c) => !content[c]?.es) ? (
                    <button
                      type="button"
                      onClick={() =>
                        askAssistant(
                          `Write the Spanish version of the "${template.name}" template (${template.id}) for ${template.channels
                            .filter((c) => !content[c]?.es)
                            .map((c) => CHANNEL_LABEL[c].toLowerCase())
                            .join(' and ')}, natural for Texas customers, keeping every merge field and required text. Stage each for me to review.`,
                        )
                      }
                      className="inline-flex h-6 items-center rounded-full border border-accent/50 bg-accent-wash px-2.5 text-micro text-accent-text hover:bg-accent-wash-hover"
                    >
                      Write the Spanish
                    </button>
                  ) : null}
                </div>
              ) : null}
            </div>
          ) : (
            <div className="px-4 py-6 space-y-3">
              <p className="text-data text-ink-secondary">
                There is no {LANG_LABEL[lang]} version of this {CHANNEL_LABEL[channel].toLowerCase()} yet. Customers who prefer{' '}
                {LANG_LABEL[lang]} receive the English one.
              </p>
              {editable ? (
                <div className="flex gap-2">
                  <Button
                    variant="primary"
                    onClick={() =>
                      askAssistant(
                        `Write the ${LANG_LABEL[lang]} version of the "${template.name}" template (${template.id}), ${CHANNEL_LABEL[channel].toLowerCase()}, from the English, keeping every merge field and required text. Stage it for me to review.`,
                      )
                    }
                  >
                    Ask the assistant to write it
                  </Button>
                  <Button onClick={() => edit(content[channel]?.en ?? { body: '' })}>Start from the English</Button>
                </div>
              ) : null}
            </div>
          )}

          {draft && editable ? (
            <div className="flex flex-wrap items-end gap-3 border-t border-rule-hair bg-surface px-4 py-3">
              <div className="min-w-64 flex-1">
                <label htmlFor="tpl-reason" className="field-label">
                  Why this change
                </label>
                <input
                  id="tpl-reason"
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  placeholder="Recorded on the version — what a reviewer reads first"
                  className="mt-1 h-8 w-full rounded-sm border border-rule-solid bg-surface-raised px-2.5 text-data text-ink-primary placeholder:text-ink-muted"
                />
              </div>
              <Button variant="quiet" disabled={!dirty} onClick={discard}>
                Discard
              </Button>
              <Button
                variant="primary"
                disabled={!canSave}
                onClick={save}
                title={
                  !dirty
                    ? 'Nothing has changed'
                    : errors.length
                      ? 'Fix the items marked “Must fix” first'
                      : reason.trim().length < 8
                        ? 'Say why — at least eight characters'
                        : undefined
                }
              >
                Save new version
              </Button>
            </div>
          ) : null}
          {saved ? (
            <p className="border-t border-rule-hair px-4 py-2 text-micro text-exception-cleared-text">
              Saved as a new version. Every message from now on uses it; anything already sent keeps the words it went out with.
            </p>
          ) : null}
        </Panel>

        {/* ==== Required text ==== */}

        {template.required?.length ? (
          <Panel>
            <PanelHeader title="Required text" meta="Prescribed by rule — placed by its token, not edited here" />
            <div className="divide-y divide-rule-hair">
              {template.required.map((b) => {
                const placed = draft?.body.includes(`{{required.${b.key}}}`)
                return (
                  <div key={b.key} className="px-4 py-3">
                    <div className="flex items-center gap-2">
                      <svg width="12" height="12" viewBox="0 0 16 16" fill="none" aria-hidden className="text-ink-tertiary">
                        <rect x="3" y="7" width="10" height="7" rx="1.5" stroke="currentColor" strokeWidth="1.4" />
                        <path d="M5.5 7V5a2.5 2.5 0 015 0v2" stroke="currentColor" strokeWidth="1.4" />
                      </svg>
                      <p className="text-data font-medium text-ink-primary">{b.label}</p>
                      <span className="ident text-ink-tertiary">{b.citation}</span>
                      {channel === 'sms' ? null : placed ? (
                        <StateFlag tone="cleared">Placed</StateFlag>
                      ) : (
                        <>
                          <StateFlag tone="critical">Missing</StateFlag>
                          {editable ? (
                            <button type="button" onClick={() => insert(`{{required.${b.key}}}`)} className="text-micro text-accent-text underline">
                              Put it back
                            </button>
                          ) : null}
                        </>
                      )}
                    </div>
                    <p className="mt-1.5 text-data text-ink-secondary leading-relaxed">{fill(b.text[lang] ?? b.text.en, ctx)}</p>
                  </div>
                )
              })}
            </div>
          </Panel>
        ) : null}
      </div>

      {/* ==== The customer's view ==== */}
      <div className="space-y-5 min-w-0">
        <Panel>
          <PanelHeader
            title="Preview"
            meta={dirty ? 'Draft' : 'Live'}
            actions={
              <>
                <label className="flex items-center gap-1.5 text-micro text-ink-secondary">
                  <input type="checkbox" checked={marks} onChange={(e) => setMarks(e.target.checked)} />
                  Merge fields
                </label>
                <label htmlFor="preview-as" className="sr-only">
                  Preview as
                </label>
                <select
                  id="preview-as"
                  value={previewAs}
                  onChange={(e) => setPreviewAs(e.target.value)}
                  className="h-7 rounded-sm border border-rule-solid bg-surface-raised px-2 text-micro text-ink-primary"
                >
                  {customers.map((c) => (
                    <option key={c.id} value={c.id}>
                      {customerName(c)}
                    </option>
                  ))}
                </select>
              </>
            }
          />
          <div className="bg-surface-sunken px-4 py-5">
            {draft ? (
              <MessagePreview template={template} channel={channel} lang={lang} content={draft} ctx={ctx} to={to} marks={marks} />
            ) : (
              <p className="text-data text-ink-secondary">Nothing to preview in {LANG_LABEL[lang]} yet.</p>
            )}
          </div>
          <p className="border-t border-rule-hair px-4 py-2 text-micro text-ink-tertiary">
            Filled from{' '}
            <Link href={`/customers/${customer.id}` as Route} className="text-accent-text underline">
              {customerName(customer)}
            </Link>
            ’s own account — the {ctx['bill.period']} bill, compared with the same month last year by the bill-explanation engine.
          </p>
        </Panel>

        <Panel>
          <PanelHeader title="Versions" meta="Every save is kept; nothing is overwritten" />
          <ol className="divide-y divide-rule-hair">
            {history.map((v) => (
              <li key={v.id} className="px-4 py-2.5">
                <div className="flex flex-wrap items-baseline gap-x-2">
                  <span className="text-data text-ink-primary">{v.by}</span>
                  {v.source === 'assistant' ? <StateFlag tone="info">With the assistant</StateFlag> : null}
                  <span className="text-micro text-ink-tertiary">
                    {CHANNEL_LABEL[v.channel]} · {LANG_LABEL[v.lang]} · {stamp(v.at)}
                  </span>
                </div>
                <p className="text-micro text-ink-secondary mt-0.5">“{v.reason}”</p>
                <details className="mt-1">
                  <summary className="cursor-pointer text-micro text-accent-text">What changed</summary>
                  <Diff before={v.before} after={v.after} />
                </details>
              </li>
            ))}
            <li className="px-4 py-2.5">
              <span className="text-data text-ink-secondary">{template.updatedBy}</span>{' '}
              <span className="text-micro text-ink-tertiary">· catalog version · {stamp(template.updatedAt)}</span>
            </li>
          </ol>
        </Panel>
      </div>
    </div>
  )
}

function Tab({ on, onClick, dot, children }: { on: boolean; onClick: () => void; dot?: boolean; children: React.ReactNode }) {
  return (
    <button
      type="button"
      role="tab"
      aria-selected={on}
      onClick={onClick}
      className={`inline-flex h-7 items-center gap-1.5 rounded-full px-3 text-micro transition-colors duration-fast ${
        on ? 'bg-accent-wash text-accent-text font-medium' : 'text-ink-secondary hover:bg-surface-sunken hover:text-ink-primary'
      }`}
    >
      {children}
      {dot ? <span aria-label="unsaved" className="h-1.5 w-1.5 rounded-full bg-exception-warning-rail" /> : null}
    </button>
  )
}

/** A word-level before/after, enough to read what a version changed. */
export function Diff({ before, after }: { before: ChannelContent | null; after: ChannelContent }) {
  const parts = (s: string) => s.split(/(\s+)/)
  const render = (a: string, b: string) => {
    const A = parts(a)
    const B = parts(b)
    /* Longest common subsequence over words — small texts, so the quadratic table is fine. */
    const n = A.length
    const m = B.length
    const dp: number[][] = Array.from({ length: n + 1 }, () => new Array(m + 1).fill(0))
    for (let i = n - 1; i >= 0; i--)
      for (let j = m - 1; j >= 0; j--) dp[i][j] = A[i] === B[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1])
    const out: { t: string; k: 'same' | 'del' | 'add' }[] = []
    let i = 0
    let j = 0
    while (i < n && j < m) {
      if (A[i] === B[j]) {
        out.push({ t: A[i], k: 'same' })
        i++
        j++
      } else if (dp[i + 1][j] >= dp[i][j + 1]) out.push({ t: A[i++], k: 'del' })
      else out.push({ t: B[j++], k: 'add' })
    }
    while (i < n) out.push({ t: A[i++], k: 'del' })
    while (j < m) out.push({ t: B[j++], k: 'add' })
    return out.map((p, x) =>
      p.k === 'same' ? (
        <span key={x}>{p.t}</span>
      ) : p.k === 'del' ? (
        <del key={x} className="bg-exception-critical-wash text-exception-critical-text">
          {p.t}
        </del>
      ) : (
        <ins key={x} className="bg-exception-cleared-wash text-exception-cleared-text no-underline">
          {p.t}
        </ins>
      ),
    )
  }
  return (
    <div className="mt-1.5 rounded-sm border border-rule-hair bg-surface px-2.5 py-2 text-micro leading-relaxed whitespace-pre-wrap text-ink-secondary">
      {after.subject !== undefined ? (
        <p className="mb-1.5">
          <span className="field-label">Subject </span>
          {render(before?.subject ?? '', after.subject)}
        </p>
      ) : null}
      {render(before?.body ?? '', after.body)}
    </div>
  )
}
