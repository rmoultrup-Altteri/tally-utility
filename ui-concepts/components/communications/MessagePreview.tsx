'use client'

import { Fragment, type ReactNode } from 'react'
import { asOf, tenant } from '@/fixtures/tenant'
import type { Channel, ChannelContent, Lang, Template } from '@/fixtures/templates'
import { TenantLogo } from '@/components/shell/TenantLogo'
import { SMS_OPT_OUT, longDate, segments, smsShape, type MergeContext, type Segment } from '@/lib/templates'


/**
 * A message as the customer receives it.
 *
 * The letter is set like the bill — serif, square, white stock in both themes
 * — because it is the same kind of object: something a customer may hold up
 * at a hearing. Email and text are drawn as the devices they arrive on, so the
 * person editing sees the subject line truncate and the text split the way
 * the customer will.
 *
 * With `marks` on, merge values carry a dotted underline and required text
 * a ruled box, so the editor can see which words are theirs to change.
 */
export function MessagePreview({
  template,
  channel,
  lang,
  content,
  ctx,
  to,
  marks = true,
}: {
  template: Template
  channel: Channel
  lang: Lang
  content: ChannelContent
  ctx: MergeContext
  to: { name: string; email: string | null; phone: string | null; address: string }
  marks?: boolean
}) {
  const body = segments(content.body, ctx, template, lang)
  const subject = content.subject ? segments(content.subject, ctx, template, lang) : []

  if (channel === 'sms') {
    const shape = smsShape(plain(body), lang)
    return (
      <div className="mx-auto w-full max-w-[300px] rounded-[28px] border border-rule-solid bg-surface-raised p-3 shadow-panel">
        <div className="flex items-center justify-between px-2 pb-2 text-micro text-ink-tertiary">
          <span>{to.phone ?? 'No mobile on file'}</span>
          <span className="ident">55142</span>
        </div>
        <div className="rounded-2xl bg-surface-sunken px-3 py-3 min-h-40">
          <p className="text-center text-micro text-ink-tertiary mb-2">Text message · {tenant.name}</p>
          <div className="max-w-[88%] rounded-2xl rounded-bl-xs bg-surface-inset px-3 py-2 text-data text-ink-primary">
            <Body segs={body} marks={marks} />{' '}
            <span className="text-ink-secondary">{SMS_OPT_OUT[lang]}</span>
          </div>
        </div>
        <p className="mt-2 px-2 text-micro text-ink-tertiary">
          {shape.length} characters · {shape.segments} message{shape.segments === 1 ? '' : 's'}
          {shape.unicode ? ` · Unicode (“${shape.culprit}”)` : ''}
        </p>
      </div>
    )
  }

  if (channel === 'email') {
    return (
      <div className="overflow-clip rounded-md border border-rule-solid bg-surface-raised shadow-panel">
        <dl className="border-b border-rule-hair bg-surface px-4 py-2.5 text-micro space-y-0.5">
          <Meta label="From">
            {tenant.name} &lt;billing@{tenant.website.replace(/\.com$/, '')}&gt;
          </Meta>
          <Meta label="To">{to.email ?? <span className="text-exception-warning-text">No email on file</span>}</Meta>
          <Meta label="Subject">
            <span className="font-medium text-ink-primary">
              <Body segs={subject} marks={marks} />
            </span>
          </Meta>
        </dl>
        {/* The email itself sits on white in both themes — it is the customer's inbox, not ours. */}
        <div className="stock px-6 py-5" style={{ fontFamily: 'var(--font-sans)' }}>
          <div className="flex items-center gap-2 border-b border-rule-hair pb-3 mb-4">
            <TenantLogo name={tenant.name} size={22} />
            <span className="text-h3 text-ink-primary">{tenant.name}</span>
          </div>
          <div className="text-body text-ink-primary leading-relaxed">
            <Body segs={body} marks={marks} block />
          </div>
          <p className="mt-6 border-t border-rule-hair pt-3 text-micro text-ink-tertiary">
            {tenant.name} · P.O. Box 1000 · Bryan, TX 77805 · {tenant.phone}. Gas emergency, 24 hours:{' '}
            {tenant.emergencyPhone}.
          </p>
        </div>
      </div>
    )
  }

  return (
    <article className="stock w-full border border-rule-solid px-9 py-8 text-doc" style={{ fontFamily: 'var(--font-doc)' }}>
      <header className="flex items-start justify-between gap-6 border-b-2 border-rule-doc pb-3">
        <div className="flex items-center gap-2">
          <TenantLogo name={tenant.name} size={24} />
          <div>
            <p className="text-doc-h font-semibold tracking-tight">{tenant.name}</p>
            <p className="text-[9pt] leading-[13pt] opacity-70">
              P.O. Box 1000 · Bryan, TX 77805 · {tenant.phone}
            </p>
          </div>
        </div>
        <p className="text-[9pt] opacity-70">{longDate(asOf.validAt, lang)}</p>
      </header>
      <div className="py-4">
        <p className="font-semibold">{to.name}</p>
        <p className="opacity-80">{to.address}</p>
      </div>
      <h3 className="text-doc-h font-semibold mb-3">
        <Body segs={subject} marks={marks} />
      </h3>
      <div className="leading-[16pt]">
        <Body segs={body} marks={marks} block />
      </div>
    </article>
  )
}

function plain(segs: Segment[]) {
  return segs.map((s) => (s.kind === 'text' ? s.text : s.kind === 'field' ? s.value : s.text)).join('')
}

function Meta({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex gap-3">
      <dt className="w-14 shrink-0 text-ink-tertiary">{label}</dt>
      <dd className="min-w-0 truncate text-ink-secondary">{children}</dd>
    </div>
  )
}

/** Text runs keep their line breaks; a blank line is a paragraph. */
function Body({ segs, marks, block = false }: { segs: Segment[]; marks: boolean; block?: boolean }) {
  return (
    <span className={block ? 'block whitespace-pre-wrap' : 'whitespace-pre-wrap'}>
      {segs.map((s, i) => (
        <Fragment key={i}>
          {s.kind === 'text' ? (
            s.text
          ) : s.kind === 'field' ? (
            <span
              title={s.known ? `{{${s.key}}}` : `Unknown merge field {{${s.key}}}`}
              className={
                !s.known
                  ? 'rounded-xs bg-exception-critical-wash px-0.5 text-exception-critical-text'
                  : marks
                    ? 'underline decoration-dotted decoration-accent underline-offset-2'
                    : ''
              }
            >
              {s.value}
            </span>
          ) : (
            <span
              title={`${s.block.label} — ${s.block.citation}`}
              className={`my-1 block whitespace-normal ${marks ? 'border-l-2 border-rule-doc bg-surface-inset/60 pl-3 py-1.5' : ''}`}
            >
              {s.text}
              {marks ? (
                <span className="mt-1 block text-[8pt] uppercase tracking-wide opacity-60" style={{ fontFamily: 'var(--font-sans)' }}>
                  Required · {s.block.citation}
                </span>
              ) : null}
            </span>
          )}
        </Fragment>
      ))}
    </span>
  )
}
