'use client'

import { useCallback, useEffect, useRef, useState, type DragEvent, type KeyboardEvent } from 'react'
import { usePathname } from 'next/navigation'
import { Markdown } from '@/components/assistant/Markdown'
import { ImportCard, type ProposalState } from '@/components/assistant/ImportCard'
import { applyProposal, getImported } from '@/lib/imports-store'
import { ENTITY_NOUN, type ActivityKind, type Attachment, type StreamEvent } from '@/lib/assistant/protocol'

/**
 * The assistant: a bubble in the bottom-right corner of every screen that
 * opens a chat. It answers from the tenant's records and from the web, and
 * stages imports the operator applies from the chat.
 *
 * It lives in the root layout rather than the app shell, so the conversation
 * survives navigation — follow a link out of an answer and the chat is still
 * there. It is also kept in sessionStorage, so a reload does not lose it.
 */

type Part = { kind: 'text'; text: string } | { kind: 'activity'; activity: ActivityKind; label: string } | { kind: 'proposal'; id: string }

type Item =
  | { id: string; role: 'user'; text: string; attachments: string[] }
  | {
      id: string
      role: 'assistant'
      parts: Part[]
      sources: { title: string; url: string }[]
      error?: string
      pending: boolean
    }

type Saved = {
  items: Item[]
  transcript: unknown[]
  files: Attachment[]
  proposals: Record<string, ProposalState>
  notes: string[]
}

const KEY = 'tu-assistant'
const EMPTY: Saved = { items: [], transcript: [], files: [], proposals: {}, notes: [] }

const TABLE_TYPES = /\.(csv|tsv|txt|json)$/i
const MAX_TABLE = 5 * 1024 * 1024
const MAX_PDF = 20 * 1024 * 1024

const SUGGESTIONS = [
  'Which accounts owe more than $1,000?',
  'What PGA are we billing, and where is Henry Hub today?',
  'What rates are in force on R-1?',
  'Import accounts from a spreadsheet',
]

const uid = () => Math.random().toString(36).slice(2, 10)

function load(): Saved {
  try {
    const raw = window.sessionStorage.getItem(KEY)
    const s = raw ? (JSON.parse(raw) as Saved) : EMPTY
    /* A reply cut off by a reload is finished, not pending forever. */
    return { ...EMPTY, ...s, items: s.items.map((i) => (i.role === 'assistant' && i.pending ? { ...i, pending: false } : i)) }
  } catch {
    return EMPTY
  }
}

export function Assistant() {
  const pathname = usePathname()
  const [open, setOpen] = useState(false)
  const [state, setState] = useState<Saved>(EMPTY)
  const [draft, setDraft] = useState('')
  const [staged, setStaged] = useState<Attachment[]>([])
  const [notice, setNotice] = useState<string | null>(null)
  const [dragging, setDragging] = useState(false)
  const [busy, setBusy] = useState(false)
  const abort = useRef<AbortController | null>(null)
  const scroller = useRef<HTMLDivElement>(null)
  const input = useRef<HTMLTextAreaElement>(null)
  const fileInput = useRef<HTMLInputElement>(null)
  const [restored, setRestored] = useState(false)

  /* Restore after mount, so the server render and the first client render agree. */
  useEffect(() => {
    setState(load())
    setRestored(true)
  }, [])

  useEffect(() => {
    /* Not before the restore has landed, or the empty first render would overwrite what was saved. */
    if (!restored) return
    try {
      window.sessionStorage.setItem(KEY, JSON.stringify(state))
    } catch {
      /* Over quota (a large PDF) or storage denied: the chat still works, it just won't survive a reload. */
    }
  }, [state, restored])

  useEffect(() => {
    scroller.current?.scrollTo({ top: scroller.current.scrollHeight })
  }, [state.items, open])

  useEffect(() => {
    if (open) input.current?.focus()
  }, [open])

  const patchLast = useCallback((fn: (a: Extract<Item, { role: 'assistant' }>) => Extract<Item, { role: 'assistant' }>) => {
    setState((s) => {
      const items = [...s.items]
      const last = items[items.length - 1]
      if (last?.role === 'assistant') items[items.length - 1] = fn(last)
      return { ...s, items }
    })
  }, [])

  async function send(text: string) {
    const message = text.trim()
    if ((!message && staged.length === 0) || busy) return
    const attachments = staged
    const files = [...state.files.filter((f) => !attachments.some((a) => a.name === f.name)), ...attachments]
    const notes = state.notes
    const prior = state.transcript

    setDraft('')
    setStaged([])
    setNotice(null)
    setBusy(true)
    setState((s) => ({
      ...s,
      files,
      notes: [],
      items: [
        ...s.items,
        { id: uid(), role: 'user', text: message, attachments: attachments.map((a) => a.name) },
        { id: uid(), role: 'assistant', parts: [], sources: [], pending: true },
      ],
    }))

    const controller = new AbortController()
    abort.current = controller
    try {
      const res = await fetch('/api/assistant', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        signal: controller.signal,
        body: JSON.stringify({
          transcript: prior,
          message: { text: message, attachments: attachments.map((a) => a.name), pathname, notes },
          /* Tables travel every turn so a later message can still import from them; a PDF is in the transcript already. */
          files: files.filter((f) => f.kind === 'table' || attachments.includes(f)),
          imported: getImported(),
        }),
      })
      if (!res.ok || !res.body) throw new Error(`The assistant is unavailable (${res.status}).`)

      const reader = res.body.getReader()
      const decoder = new TextDecoder()
      let buffer = ''
      for (;;) {
        const { value, done } = await reader.read()
        if (done) break
        buffer += decoder.decode(value, { stream: true })
        const lines = buffer.split('\n')
        buffer = lines.pop() ?? ''
        for (const line of lines) if (line.trim()) handle(JSON.parse(line) as StreamEvent)
      }
    } catch (err) {
      if (!controller.signal.aborted) {
        patchLast((a) => ({ ...a, error: err instanceof Error ? err.message : String(err) }))
      }
    } finally {
      patchLast((a) => ({ ...a, pending: false }))
      setBusy(false)
      abort.current = null
    }
  }

  function handle(e: StreamEvent) {
    switch (e.type) {
      case 'text':
        return patchLast((a) => {
          const parts = [...a.parts]
          const last = parts[parts.length - 1]
          if (last?.kind === 'text') parts[parts.length - 1] = { ...last, text: last.text + e.text }
          else parts.push({ kind: 'text', text: e.text })
          return { ...a, parts }
        })
      case 'activity':
        return patchLast((a) => ({ ...a, parts: [...a.parts, { kind: 'activity', activity: e.kind, label: e.label }] }))
      case 'sources':
        return patchLast((a) => ({
          ...a,
          sources: [...a.sources, ...e.sources.filter((s) => !a.sources.some((x) => x.url === s.url))],
        }))
      case 'proposal':
        setState((s) => ({ ...s, proposals: { ...s.proposals, [e.proposal.id]: { proposal: e.proposal, status: 'staged' } } }))
        return patchLast((a) => ({ ...a, parts: [...a.parts, { kind: 'proposal', id: e.proposal.id }] }))
      case 'transcript':
        return setState((s) => ({ ...s, transcript: e.messages }))
      case 'error':
        return patchLast((a) => ({ ...a, error: e.message }))
      case 'done':
        return
    }
  }

  function apply(id: string) {
    const p = state.proposals[id]
    if (!p || p.status !== 'staged') return
    const applied = applyProposal(p.proposal)
    const noun = ENTITY_NOUN[p.proposal.entity][applied === 1 ? 0 : 1]
    setState((s) => ({
      ...s,
      proposals: { ...s.proposals, [id]: { ...p, status: 'applied', applied } },
      notes: [...s.notes, `The operator applied staged import ${id}: ${applied} ${noun} written.`],
    }))
  }

  function discard(id: string) {
    const p = state.proposals[id]
    if (!p || p.status !== 'staged') return
    setState((s) => ({
      ...s,
      proposals: { ...s.proposals, [id]: { ...p, status: 'discarded' } },
      notes: [...s.notes, `The operator discarded staged import ${id}.`],
    }))
  }

  async function attach(list: FileList | File[]) {
    const added: Attachment[] = []
    for (const file of Array.from(list)) {
      try {
        if (/\.pdf$/i.test(file.name)) {
          if (file.size > MAX_PDF) throw new Error(`${file.name} is over 20 MB`)
          const bytes = new Uint8Array(await file.arrayBuffer())
          let bin = ''
          for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000))
          added.push({ name: file.name, kind: 'pdf', base64: btoa(bin) })
        } else if (TABLE_TYPES.test(file.name)) {
          if (file.size > MAX_TABLE) throw new Error(`${file.name} is over 5 MB`)
          added.push({ name: file.name, kind: 'table', text: await file.text() })
        } else if (/\.xlsx?$/i.test(file.name)) {
          throw new Error(`${file.name}: save the sheet as CSV first`)
        } else {
          throw new Error(`${file.name}: attach a CSV, TSV, JSON or PDF`)
        }
      } catch (err) {
        setNotice(err instanceof Error ? err.message : String(err))
      }
    }
    setStaged((s) => [...s.filter((a) => !added.some((b) => b.name === a.name)), ...added])
    input.current?.focus()
  }

  function onKey(e: KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) {
      e.preventDefault()
      void send(draft)
    }
  }

  function onDrop(e: DragEvent) {
    e.preventDefault()
    setDragging(false)
    if (e.dataTransfer.files.length) void attach(e.dataTransfer.files)
  }

  function reset() {
    abort.current?.abort()
    setState(EMPTY)
    setStaged([])
    setDraft('')
    setNotice(null)
  }

  return (
    <>
      {open ? (
        <section
          role="dialog"
          aria-label="Assistant"
          onKeyDown={(e) => e.key === 'Escape' && setOpen(false)}
          onDragOver={(e) => {
            e.preventDefault()
            setDragging(true)
          }}
          onDragLeave={(e) => {
            if (!e.currentTarget.contains(e.relatedTarget as Node)) setDragging(false)
          }}
          onDrop={onDrop}
          className="fixed bottom-20 right-5 z-50 flex h-[min(640px,calc(100dvh-7rem))] w-[min(420px,calc(100vw-2.5rem))] flex-col border border-rule-solid bg-surface-raised shadow-modal"
        >
          <header className="flex items-center justify-between gap-2 border-b border-rule-solid bg-surface-ink px-3 py-2 text-ink-inverse">
            <div className="min-w-0">
              <h2 className="text-h3">Assistant</h2>
              <p className="text-micro opacity-70">Your account, the web, and imports</p>
            </div>
            <div className="flex items-center gap-1">
              <button
                type="button"
                onClick={reset}
                disabled={state.items.length === 0}
                className="h-6 rounded-xs px-2 text-micro opacity-80 hover:bg-white/10 hover:opacity-100 disabled:opacity-35"
              >
                New chat
              </button>
              <button
                type="button"
                onClick={() => setOpen(false)}
                aria-label="Close assistant"
                className="flex h-6 w-6 items-center justify-center rounded-xs opacity-80 hover:bg-white/10 hover:opacity-100"
              >
                <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden>
                  <path d="M2 2l8 8M10 2l-8 8" stroke="currentColor" strokeWidth="1.5" />
                </svg>
              </button>
            </div>
          </header>

          <div ref={scroller} className="relative flex-1 min-h-0 overflow-y-auto px-3 py-3 text-body text-ink-primary">
            {state.items.length === 0 ? (
              <div className="space-y-3">
                <p className="text-data text-ink-secondary">
                  Ask about an account, a bill or a rate; look something up on the web; or drop in a CSV of accounts,
                  meters, addresses or rates to import.
                </p>
                <ul className="space-y-1.5">
                  {SUGGESTIONS.map((s) => (
                    <li key={s}>
                      <button
                        type="button"
                        onClick={() => (s.startsWith('Import') ? fileInput.current?.click() : void send(s))}
                        className="w-full border border-rule-solid bg-surface px-2.5 py-1.5 text-left text-data text-ink-secondary transition-colors duration-fast hover:border-rule-heavy hover:bg-surface-sunken hover:text-ink-primary"
                      >
                        {s}
                      </button>
                    </li>
                  ))}
                </ul>
              </div>
            ) : (
              <ol className="space-y-4">
                {state.items.map((item) =>
                  item.role === 'user' ? (
                    <li key={item.id} className="flex flex-col items-end gap-1">
                      {item.attachments.map((a) => (
                        <span key={a} className="ident max-w-[85%] truncate border border-rule-solid bg-surface-sunken px-1.5 py-0.5 text-micro text-ink-secondary">
                          {a}
                        </span>
                      ))}
                      {item.text ? (
                        <p className="max-w-[85%] whitespace-pre-wrap bg-accent-wash px-2.5 py-1.5 text-data">{item.text}</p>
                      ) : null}
                    </li>
                  ) : (
                    <li key={item.id} className="space-y-2 text-data">
                      {item.parts.map((part, k) =>
                        part.kind === 'text' ? (
                          <Markdown key={k} text={part.text} />
                        ) : part.kind === 'activity' ? (
                          <p key={k} className="flex items-center gap-1.5 text-micro text-ink-tertiary">
                            <ActivityIcon kind={part.activity} />
                            <span className="truncate">{part.label}</span>
                          </p>
                        ) : state.proposals[part.id] ? (
                          <ImportCard
                            key={k}
                            state={state.proposals[part.id]}
                            onApply={() => apply(part.id)}
                            onDiscard={() => discard(part.id)}
                          />
                        ) : null,
                      )}
                      {item.pending ? <Thinking /> : null}
                      {item.error ? (
                        <p className="border-l-[3px] border-exception-critical-rail bg-exception-critical-wash px-2 py-1 text-micro text-exception-critical-text">
                          {item.error}
                        </p>
                      ) : null}
                      {item.sources.length && !item.pending ? (
                        <div className="border-t border-rule-hair pt-1.5">
                          <p className="label-caps mb-0.5">Sources</p>
                          <ul className="space-y-0.5 text-micro">
                            {item.sources.slice(0, 8).map((s) => (
                              <li key={s.url} className="truncate">
                                <a href={s.url} target="_blank" rel="noopener noreferrer" className="text-accent-text hover:underline">
                                  {s.title || s.url}
                                </a>
                              </li>
                            ))}
                          </ul>
                        </div>
                      ) : null}
                    </li>
                  ),
                )}
              </ol>
            )}

            {dragging ? (
              <div className="pointer-events-none absolute inset-2 flex items-center justify-center border-2 border-dashed border-accent bg-accent-wash/90 text-data text-ink-primary">
                Drop a CSV, TSV, JSON or PDF to attach
              </div>
            ) : null}
          </div>

          <form
            onSubmit={(e) => {
              e.preventDefault()
              void send(draft)
            }}
            className="border-t border-rule-solid bg-surface px-2.5 py-2"
          >
            {notice ? <p className="mb-1.5 text-micro text-exception-warning-text">{notice}</p> : null}
            {staged.length ? (
              <ul className="mb-1.5 flex flex-wrap gap-1">
                {staged.map((a) => (
                  <li key={a.name} className="flex items-center gap-1 border border-rule-solid bg-surface-raised py-0.5 pl-1.5 pr-0.5 text-micro">
                    <span className="ident max-w-48 truncate">{a.name}</span>
                    <button
                      type="button"
                      aria-label={`Remove ${a.name}`}
                      onClick={() => setStaged((s) => s.filter((x) => x.name !== a.name))}
                      className="flex h-4 w-4 items-center justify-center text-ink-tertiary hover:text-ink-primary"
                    >
                      ×
                    </button>
                  </li>
                ))}
              </ul>
            ) : null}
            <div className="flex items-end gap-1.5">
              <input
                ref={fileInput}
                type="file"
                multiple
                accept=".csv,.tsv,.txt,.json,.pdf"
                className="hidden"
                onChange={(e) => {
                  if (e.target.files) void attach(e.target.files)
                  e.target.value = ''
                }}
              />
              <button
                type="button"
                onClick={() => fileInput.current?.click()}
                aria-label="Attach a file"
                title="Attach a CSV, TSV, JSON or PDF"
                className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xs border border-rule-solid bg-surface-raised text-ink-secondary hover:border-rule-heavy hover:text-ink-primary"
              >
                <svg width="14" height="14" viewBox="0 0 16 16" fill="none" aria-hidden>
                  <path
                    d="M10.5 4.5L5.4 9.6a1.5 1.5 0 002.1 2.1l5.6-5.6a3 3 0 00-4.2-4.2L3.3 7.5a4.5 4.5 0 006.4 6.4l4.1-4.1"
                    stroke="currentColor"
                    strokeWidth="1.3"
                    strokeLinecap="round"
                  />
                </svg>
              </button>
              <label htmlFor="assistant-input" className="sr-only">
                Message the assistant
              </label>
              <textarea
                id="assistant-input"
                ref={input}
                rows={1}
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
                onKeyDown={onKey}
                placeholder={staged.length ? 'Say what this file is, or just send it…' : 'Ask, or drop a file to import…'}
                className="max-h-32 min-h-8 flex-1 resize-none rounded-xs border border-rule-solid bg-surface-raised px-2 py-1.5 text-data text-ink-primary placeholder:text-ink-muted [field-sizing:content]"
              />
              {busy ? (
                <button
                  type="button"
                  onClick={() => abort.current?.abort()}
                  className="h-8 shrink-0 rounded-xs border border-rule-solid bg-surface-raised px-3 text-data text-ink-primary hover:bg-surface-sunken"
                >
                  Stop
                </button>
              ) : (
                <button
                  type="submit"
                  disabled={!draft.trim() && staged.length === 0}
                  className="h-8 shrink-0 rounded-xs border border-accent bg-accent px-3 text-data text-ink-inverse hover:bg-accent-hover disabled:cursor-not-allowed disabled:opacity-45"
                >
                  Send
                </button>
              )}
            </div>
          </form>
        </section>
      ) : null}

      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-label={open ? 'Close assistant' : 'Open assistant'}
        aria-expanded={open}
        className="fixed bottom-5 right-5 z-50 flex h-12 w-12 items-center justify-center rounded-full bg-surface-ink text-ink-inverse shadow-overlay ring-1 ring-rule-heavy/20 transition-transform duration-base ease-standard hover:scale-105 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
      >
        {open ? (
          <svg width="16" height="16" viewBox="0 0 12 12" aria-hidden>
            <path d="M2 2l8 8M10 2l-8 8" stroke="currentColor" strokeWidth="1.5" />
          </svg>
        ) : (
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" aria-hidden>
            <path
              d="M4 5.5A2.5 2.5 0 016.5 3h11A2.5 2.5 0 0120 5.5v8a2.5 2.5 0 01-2.5 2.5H10l-4.5 4v-4h0A1.5 1.5 0 014 14.5v-9z"
              stroke="currentColor"
              strokeWidth="1.6"
              strokeLinejoin="round"
            />
            <path d="M8.5 9.5h.01M12 9.5h.01M15.5 9.5h.01" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" />
          </svg>
        )}
        {busy && !open ? (
          <span aria-hidden className="absolute right-0.5 top-0.5 h-2.5 w-2.5 animate-pulse rounded-full bg-accent ring-2 ring-surface-raised" />
        ) : null}
      </button>
    </>
  )
}

function Thinking() {
  return (
    <p className="flex items-center gap-1 text-micro text-ink-tertiary" aria-live="polite">
      <span className="flex gap-0.5" aria-hidden>
        {[0, 1, 2].map((i) => (
          <span key={i} className="h-1 w-1 animate-pulse rounded-full bg-current" style={{ animationDelay: `${i * 160}ms` }} />
        ))}
      </span>
      Working
    </p>
  )
}

function ActivityIcon({ kind }: { kind: ActivityKind }) {
  if (kind === 'web')
    return (
      <svg width="11" height="11" viewBox="0 0 16 16" fill="none" aria-hidden className="shrink-0">
        <circle cx="8" cy="8" r="6.25" stroke="currentColor" strokeWidth="1.3" />
        <path d="M1.75 8h12.5M8 1.75c1.8 1.7 2.7 3.8 2.7 6.25S9.8 12.55 8 14.25C6.2 12.55 5.3 10.45 5.3 8S6.2 3.45 8 1.75z" stroke="currentColor" strokeWidth="1.3" />
      </svg>
    )
  if (kind === 'import')
    return (
      <svg width="11" height="11" viewBox="0 0 16 16" fill="none" aria-hidden className="shrink-0">
        <path d="M8 2v8m0 0L5 7m3 3l3-3M2.5 11v2.5h11V11" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    )
  return (
    <svg width="11" height="11" viewBox="0 0 16 16" fill="none" aria-hidden className="shrink-0">
      <ellipse cx="8" cy="3.75" rx="5.5" ry="2" stroke="currentColor" strokeWidth="1.3" />
      <path d="M2.5 3.75v8.5c0 1.1 2.46 2 5.5 2s5.5-.9 5.5-2v-8.5M2.5 8c0 1.1 2.46 2 5.5 2s5.5-.9 5.5-2" stroke="currentColor" strokeWidth="1.3" />
    </svg>
  )
}
