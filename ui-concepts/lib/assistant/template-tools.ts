import {
  CHANNEL_LABEL,
  LANG_LABEL,
  templateById,
  templates,
  type Channel,
  type ChannelContent,
  type Lang,
  type Template,
  type TemplateContent,
} from '@/fixtures/templates'
import { MERGE_FIELDS, checkContent, smsShape } from '@/lib/templates'
import type { TemplateProposal } from '@/lib/assistant/protocol'

/**
 * The assistant's view of the communication templates: read them, and stage
 * an edit for the operator to apply. Everything an edit must satisfy is the
 * same `checkContent` the editor runs, so the model meets the rules the person
 * at the keyboard does — and a refused edit comes back to it as the reason.
 */

type Overrides = Record<string, TemplateContent>

const contentOf = (t: Template, o: Overrides): TemplateContent => o[t.id] ?? t.content

function find(ref: string): Template {
  const r = ref.trim().toLowerCase()
  const t =
    templateById.get(r) ??
    templates.find((x) => x.name.toLowerCase() === r) ??
    templates.find((x) => x.name.toLowerCase().includes(r) || r.includes(x.id))
  if (!t) throw new Error(`No template "${ref}". Call list_templates for the ids.`)
  return t
}

export function listTemplates(o: Overrides) {
  return templates.map((t) => {
    const c = contentOf(t, o)
    return {
      id: t.id,
      name: t.name,
      category: t.category,
      kind: t.kind,
      sent_when: t.trigger,
      channels: t.channels.map((ch) => ({
        channel: ch,
        languages: (['en', 'es'] as Lang[]).filter((l) => c[ch]?.[l]?.body),
      })),
      portal_path: `/communications/${t.id}`,
    }
  })
}

export function getTemplate(o: Overrides, ref: string) {
  const t = find(ref)
  return {
    id: t.id,
    name: t.name,
    purpose: t.purpose,
    sent_when: t.trigger,
    kind: t.kind,
    channels: t.channels,
    content: contentOf(t, o),
    required_text: (t.required ?? []).map((b) => ({
      token: `{{required.${b.key}}}`,
      label: b.label,
      citation: b.citation,
      note: 'Prescribed by rule. Keep the token exactly; do not paraphrase or restate it in the body.',
    })),
    merge_fields: MERGE_FIELDS.map((f) => ({ token: `{{${f.key}}}`, label: f.label })),
    sms_rules:
      'One message is 160 GSM-7 characters (70 if any character is outside GSM, such as curly quotes, em dashes or á/í/ó/ú). “Reply STOP to opt out.” is appended automatically — do not write it. Start with “{{utility.name}}:”.',
    portal_path: `/communications/${t.id}`,
  }
}

export function proposeTemplateEdit(
  o: Overrides,
  input: { template: string; channel: Channel; language: Lang; subject?: string; body: string; reason: string },
): TemplateProposal {
  const t = find(input.template)
  if (!t.channels.includes(input.channel))
    throw new Error(`"${t.name}" is not sent by ${CHANNEL_LABEL[input.channel].toLowerCase()}; its channels are ${t.channels.join(', ')}.`)
  const before = contentOf(t, o)[input.channel]?.[input.language] ?? null
  const after: ChannelContent =
    input.channel === 'sms' ? { body: input.body } : { subject: input.subject ?? before?.subject ?? '', body: input.body }

  const issues = checkContent(t, input.channel, input.language, after)
  const errors = issues.filter((i) => i.level === 'error')
  if (errors.length)
    throw new Error(`Not staged — fix and try again: ${errors.map((e) => e.text).join(' ')}`)
  if (before && before.body === after.body && before.subject === after.subject)
    throw new Error('Not staged — the text is identical to the current version.')

  return {
    id: `tpl-${Math.random().toString(36).slice(2, 8)}`,
    templateId: t.id,
    templateName: t.name,
    channel: input.channel,
    lang: input.language,
    before,
    after,
    reason: input.reason,
    warnings: issues.filter((i) => i.level === 'warning').map((i) => i.text),
  }
}

export function reportTemplateProposal(p: TemplateProposal): string {
  const sms = p.channel === 'sms' ? smsShape(p.after.body, p.lang) : null
  return [
    `Staged ${p.id}: ${p.templateName}, ${CHANNEL_LABEL[p.channel].toLowerCase()} in ${LANG_LABEL[p.lang]}${p.before ? '' : ' (new — there was no version in this language)'}.`,
    sms ? `Text length ${sms.length} with the opt-out line, ${sms.segments} message(s)${sms.unicode ? ', Unicode' : ''}.` : '',
    p.warnings.length ? `Warnings: ${p.warnings.join(' ')}` : 'No warnings.',
    'The operator applies or discards it from the card. It is not saved until they do.',
  ]
    .filter(Boolean)
    .join(' ')
}
