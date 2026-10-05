'use client'

import { useEffect, useRef, type ReactNode } from 'react'

/**
 * A modal form dialog on the native `<dialog>` element, which brings focus
 * trapping, Escape to close and an inert page behind it without any library.
 */
export function Dialog({
  open,
  onClose,
  title,
  meta,
  children,
  footer,
}: {
  open: boolean
  onClose: () => void
  title: ReactNode
  meta?: ReactNode
  children: ReactNode
  footer: ReactNode
}) {
  const ref = useRef<HTMLDialogElement>(null)

  useEffect(() => {
    const d = ref.current
    if (!d) return
    if (open && !d.open) d.showModal()
    if (!open && d.open) d.close()
  }, [open])

  return (
    <dialog
      ref={ref}
      onClose={onClose}
      onClick={(e) => {
        /* A click on the backdrop lands on the dialog element itself. */
        if (e.target === e.currentTarget) onClose()
      }}
      className="m-auto w-[min(560px,calc(100vw-2rem))] max-h-[calc(100dvh-4rem)] overflow-clip rounded-lg border border-rule-hair bg-surface-raised p-0 text-ink-primary shadow-modal backdrop:bg-surface-scrim"
    >
      {open ? (
        <div className="flex max-h-[calc(100dvh-4rem)] flex-col">
          <header className="flex items-start justify-between gap-4 border-b border-rule-hair px-5 py-4">
            <div className="min-w-0">
              <h2 className="text-h2 text-ink-primary">{title}</h2>
              {meta ? <p className="mt-0.5 text-micro text-ink-tertiary">{meta}</p> : null}
            </div>
            <button
              type="button"
              onClick={onClose}
              aria-label="Close"
              className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-ink-secondary hover:bg-surface-sunken hover:text-ink-primary"
            >
              <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden>
                <path d="M2 2l8 8M10 2l-8 8" stroke="currentColor" strokeWidth="1.5" />
              </svg>
            </button>
          </header>
          <div className="min-h-0 flex-1 overflow-y-auto px-5 py-4">{children}</div>
          <footer className="flex items-center justify-end gap-2 border-t border-rule-hair bg-surface px-5 py-3">{footer}</footer>
        </div>
      ) : null}
    </dialog>
  )
}

/** The input look every edit form shares. */
export const fieldClass =
  'mt-1 h-8 w-full rounded-sm border border-rule-solid bg-surface-raised px-2.5 text-data text-ink-primary placeholder:text-ink-muted aria-invalid:border-exception-critical-rail'

/** A labelled form control with an optional hint or error beneath it. */
export function FormField({
  label,
  htmlFor,
  hint,
  error,
  children,
  className = '',
}: {
  label: string
  htmlFor: string
  hint?: string
  error?: string | null
  children: ReactNode
  className?: string
}) {
  return (
    <div className={className}>
      <label htmlFor={htmlFor} className="field-label">
        {label}
      </label>
      {children}
      {error ? (
        <p id={`${htmlFor}-error`} className="mt-1 text-micro text-exception-critical-text">
          {error}
        </p>
      ) : hint ? (
        <p className="mt-1 text-micro text-ink-tertiary">{hint}</p>
      ) : null}
    </div>
  )
}

/** A pencil-and-label button that opens an edit form. */
export function EditButton({ onClick, label = 'Edit' }: { onClick: () => void; label?: string }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="inline-flex h-8 items-center justify-center gap-1.5 rounded-sm border border-rule-solid bg-surface-raised px-3.5 text-data font-medium text-ink-primary transition-colors duration-fast hover:border-rule-heavy hover:bg-surface-sunken"
    >
      <svg width="13" height="13" viewBox="0 0 16 16" fill="none" aria-hidden>
        <path d="M10.5 2.5l3 3L6 13H3v-3l7.5-7.5z" stroke="currentColor" strokeWidth="1.4" strokeLinejoin="round" />
      </svg>
      {label}
    </button>
  )
}
