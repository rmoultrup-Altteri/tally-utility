'use client'

import { useSyncExternalStore } from 'react'
import {
  templateById,
  type Channel,
  type ChannelContent,
  type Lang,
  type Template,
  type TemplateContent,
} from '@/fixtures/templates'

/**
 * Template edits, until the API exists.
 *
 * A template is reference data, so an edit never overwrites: it appends a
 * version carrying who, when, why and where it came from — the editor or the
 * assistant. The current text is the newest version for each channel and
 * language, laid over the catalog. Kept in this browser, the same way every
 * other store in the concepts is, and never able to break a page if storage
 * is unavailable.
 */

const KEY = 'tu-templates'

export type TemplateVersion = {
  id: string
  templateId: string
  channel: Channel
  lang: Lang
  before: ChannelContent | null
  after: ChannelContent
  reason: string
  by: string
  at: string
  source: 'editor' | 'assistant'
}

type State = { versions: TemplateVersion[] }
const EMPTY: State = { versions: [] }

let current: State = EMPTY
let hydrated = false
const listeners = new Set<() => void>()

function read(): State {
  try {
    const raw = window.localStorage.getItem(KEY)
    const parsed = raw ? JSON.parse(raw) : null
    return parsed && Array.isArray(parsed.versions) ? parsed : EMPTY
  } catch {
    return EMPTY
  }
}

function hydrate() {
  if (!hydrated) {
    hydrated = true
    current = read()
  }
}

function subscribe(onChange: () => void) {
  hydrate()
  listeners.add(onChange)
  const onStorage = (e: StorageEvent) => {
    if (e.key !== KEY) return
    current = read()
    onChange()
  }
  window.addEventListener('storage', onStorage)
  return () => {
    listeners.delete(onChange)
    window.removeEventListener('storage', onStorage)
  }
}

function write(next: State) {
  current = next
  try {
    window.localStorage.setItem(KEY, JSON.stringify(current))
  } catch {
    /* Storage denied. The edit still shows for this session. */
  }
  for (const l of listeners) l()
}

export function useTemplateVersions(): TemplateVersion[] {
  return useSyncExternalStore(
    subscribe,
    () => current.versions,
    () => EMPTY.versions,
  )
}

export function getTemplateVersions(): TemplateVersion[] {
  hydrate()
  return current.versions
}

/** The catalog content with every version applied, oldest first. */
export function contentWith(template: Template, versions: TemplateVersion[]): TemplateContent {
  const content: TemplateContent = structuredClone(template.content)
  for (const v of versions) {
    if (v.templateId !== template.id) continue
    content[v.channel] = { ...(content[v.channel] ?? {}), [v.lang]: v.after }
  }
  return content
}

/** Current content for every template that has been edited, for the assistant to read. */
export function editedContent(): Record<string, TemplateContent> {
  const versions = getTemplateVersions()
  const out: Record<string, TemplateContent> = {}
  for (const id of new Set(versions.map((v) => v.templateId))) {
    const t = templateById.get(id)
    if (t) out[id] = contentWith(t, versions)
  }
  return out
}

export function useTemplate(template: Template): { content: TemplateContent; history: TemplateVersion[] } {
  const versions = useTemplateVersions()
  return {
    content: contentWith(template, versions),
    history: versions.filter((v) => v.templateId === template.id).slice().reverse(),
  }
}

const uid = () => Math.random().toString(36).slice(2, 10)

export function saveTemplateVersion(v: Omit<TemplateVersion, 'id' | 'at'>): TemplateVersion {
  hydrate()
  const version = { ...v, id: `tv-${uid()}`, at: new Date().toISOString() }
  write({ versions: [...current.versions, version] })
  return version
}

/** Forget every edit made in this browser. The catalog is untouched. */
export function clearTemplateEdits() {
  hydrate()
  write(EMPTY)
}
