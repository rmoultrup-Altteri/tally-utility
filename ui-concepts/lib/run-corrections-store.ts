'use client'

import { useSyncExternalStore } from 'react'
import type { VoidReasonCode } from '@/schemas/enums'
import { activeUserName } from '@/lib/session'
import type { BatchMode } from '@/lib/run-corrections'

/**
 * Batch corrections requested in this browser, until the API exists.
 *
 * A request is a correction run that has been queued but not run: the
 * targets, the reason and the rate election are recorded, and nothing is
 * voided until a second person approves it. Voids and rebills then post
 * together, so no customer is left holding a voided bill with no replacement.
 *
 * Nothing is deleted. A withdrawn request stays in the history, struck, with
 * who withdrew it and why — the same shape as the other stores: one module
 * every screen subscribes to, persisted to localStorage, never able to break
 * a page if storage is unavailable.
 */

export type BatchCorrection = {
  id: string
  runNumber: string
  /** The run whose bills are being voided. */
  targetRunId: string
  scope: 'all' | 'selected'
  /** The bills named in the request; for `all`, every bill the run issued except those excluded. */
  invoiceIds: string[]
  billCount: number
  reasonCode: VoidReasonCode
  notes: string
  mode: BatchMode
  dueDate: 'reset' | 'original'
  holdDunning: boolean
  notify: boolean
  /** Cents, over the bills the preview could price. */
  beforeCents: number
  afterCents: number
  requestedBy: string
  requestedAt: string
  status: 'awaiting_approval' | 'approved' | 'withdrawn'
  decidedBy: string | null
  decidedAt: string | null
  decisionNote: string | null
}

const KEY = 'tu-run-corrections'
const EMPTY: BatchCorrection[] = []

let current: BatchCorrection[] = EMPTY
let hydrated = false
const listeners = new Set<() => void>()

function read(): BatchCorrection[] {
  try {
    const raw = window.localStorage.getItem(KEY)
    const parsed = raw ? JSON.parse(raw) : []
    return Array.isArray(parsed) ? (parsed as BatchCorrection[]) : EMPTY
  } catch {
    return EMPTY
  }
}

function hydrate() {
  if (hydrated) return
  hydrated = true
  current = read()
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

function write(next: BatchCorrection[]) {
  current = next
  try {
    window.localStorage.setItem(KEY, JSON.stringify(current))
  } catch {
    /* Storage denied. The request still shows for this session. */
  }
  for (const l of listeners) l()
}

export function useBatchCorrections(): BatchCorrection[] {
  return useSyncExternalStore(
    subscribe,
    () => current,
    () => EMPTY,
  )
}

/**
 * Requests still open against a run — awaiting approval, or approved and not
 * yet posted. A second batch on the same bills would void them twice.
 */
export const openFor = (all: BatchCorrection[], runId: string) =>
  all.filter((c) => c.targetRunId === runId && (c.status === 'awaiting_approval' || c.status === 'approved'))

/** Why an open request blocks another: "BR-2026-02-COR-2 is waiting for approval". */
export const openReason = (c: BatchCorrection) =>
  `${c.runNumber} ${c.status === 'approved' ? 'is approved and waiting to post' : 'is waiting for approval'}`

export function requestBatchCorrection(
  c: Omit<BatchCorrection, 'id' | 'requestedBy' | 'requestedAt' | 'status' | 'decidedBy' | 'decidedAt' | 'decisionNote'>,
): BatchCorrection {
  hydrate()
  const entry: BatchCorrection = {
    ...c,
    id: `bc-${Date.now().toString(36)}`,
    requestedBy: activeUserName(),
    requestedAt: new Date().toISOString(),
    status: 'awaiting_approval',
    decidedBy: null,
    decidedAt: null,
    decisionNote: null,
  }
  write([...current, entry])
  return entry
}

export function decideBatchCorrection(id: string, status: 'approved' | 'withdrawn', note: string | null) {
  hydrate()
  write(
    current.map((c) =>
      c.id === id && c.status === 'awaiting_approval'
        ? { ...c, status, decidedBy: activeUserName(), decidedAt: new Date().toISOString(), decisionNote: note }
        : c,
    ),
  )
}
