'use client'

import { useEffect, useRef, useState, type ReactNode } from 'react'
import { Panel, PanelHeader } from '@/components/ui/Panel'
import { FormField, fieldClass } from '@/components/ui/Dialog'
import { humanize } from '@/components/ui/State'
import type { ImportIssue } from '@/lib/assistant/protocol'

/**
 * The pieces the new-account and new-meter forms share: a values map keyed
 * by import field name, so the form hands the validator exactly what a file
 * row would, and errors that come back keyed the same way land under the
 * input that caused them.
 */

export type Values = Record<string, string>

export function useValues(initial: Values) {
  const [values, setValues] = useState<Values>(initial)
  const set = (key: string, value: string) => setValues((v) => ({ ...v, [key]: value }))
  return { values, set, reset: () => setValues(initial) }
}

export function Section({ title, meta, children }: { title: string; meta?: ReactNode; children: ReactNode }) {
  return (
    <Panel>
      <PanelHeader title={title} meta={meta} />
      <div className="grid grid-cols-1 gap-x-5 gap-y-4 px-4 py-4 sm:grid-cols-2 lg:grid-cols-3">{children}</div>
    </Panel>
  )
}

type FieldProps = {
  name: string
  label: string
  values: Values
  set: (key: string, value: string) => void
  errors: ImportIssue[]
  hint?: string
  className?: string
}

const errorFor = (errors: ImportIssue[], name: string) => errors.find((e) => e.field === name)?.message ?? null

export function TextField({
  name,
  label,
  values,
  set,
  errors,
  hint,
  className,
  type = 'text',
  placeholder,
  required,
}: FieldProps & { type?: 'text' | 'email' | 'tel' | 'date' | 'number'; placeholder?: string; required?: boolean }) {
  const id = `f-${name}`
  const error = errorFor(errors, name)
  return (
    <FormField label={required ? `${label} *` : label} htmlFor={id} hint={hint} error={error} className={className}>
      <input
        id={id}
        type={type}
        value={values[name] ?? ''}
        onChange={(e) => set(name, e.target.value)}
        placeholder={placeholder}
        aria-invalid={error ? true : undefined}
        aria-describedby={error ? `${id}-error` : undefined}
        className={fieldClass}
      />
    </FormField>
  )
}

export function SelectField({
  name,
  label,
  values,
  set,
  errors,
  hint,
  className,
  options,
  blank,
}: FieldProps & { options: readonly (string | { value: string; label: string })[]; blank?: string }) {
  const id = `f-${name}`
  const error = errorFor(errors, name)
  return (
    <FormField label={label} htmlFor={id} hint={hint} error={error} className={className}>
      <select
        id={id}
        value={values[name] ?? ''}
        onChange={(e) => set(name, e.target.value)}
        aria-invalid={error ? true : undefined}
        className={fieldClass}
      >
        {blank !== undefined ? <option value="">{blank}</option> : null}
        {options.map((o) =>
          typeof o === 'string' ? (
            <option key={o} value={o}>
              {humanize(o)}
            </option>
          ) : (
            <option key={o.value} value={o.value}>
              {o.label}
            </option>
          ),
        )}
      </select>
    </FormField>
  )
}

export function CheckField({ name, label, values, set, hint }: Omit<FieldProps, 'errors' | 'className'>) {
  const id = `f-${name}`
  return (
    <div className="flex items-start gap-2 self-end pb-1.5">
      <input
        id={id}
        type="checkbox"
        checked={values[name] === 'yes'}
        onChange={(e) => set(name, e.target.checked ? 'yes' : 'no')}
        className="mt-0.5"
      />
      <label htmlFor={id} className="text-data text-ink-primary">
        {label}
        {hint ? <span className="block text-micro text-ink-tertiary">{hint}</span> : null}
      </label>
    </div>
  )
}

/** Problems the validator found that belong to no field on screen, or to all of them. */
export function ErrorSummary({ errors }: { errors: ImportIssue[] }) {
  /* The submit button sits below the fold; bring the list of problems up to where the eye is. */
  const box = useRef<HTMLDivElement>(null)
  useEffect(() => box.current?.scrollIntoView({ block: 'start', behavior: 'smooth' }), [errors])
  if (!errors.length) return null
  return (
    <div ref={box} role="alert" className="rounded-md border border-exception-critical-rail bg-exception-critical-wash px-4 py-3">
      <p className="text-data font-medium text-exception-critical-text">
        {errors.length === 1 ? 'One thing to fix' : `${errors.length} things to fix`} before this can be saved
      </p>
      <ul className="mt-1 list-disc list-inside text-micro text-exception-critical-text">
        {errors.map((e, i) => (
          <li key={i}>
            {e.field ? `${humanize(e.field)}: ` : ''}
            {e.message}
          </li>
        ))}
      </ul>
    </div>
  )
}
