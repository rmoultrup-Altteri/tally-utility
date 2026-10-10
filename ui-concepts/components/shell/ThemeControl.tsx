'use client'

import { useEffect, useState } from 'react'

/**
 * Display controls: appearance and density.
 *
 * Appearance has three states, not a toggle. Day is the default — these are
 * daylight office users comparing the screen to a printed bill, and Day is
 * the palette the design was drawn in. Auto follows the operating system
 * through `light-dark()` with no JavaScript at all (it is the absence of the
 * attribute); Night pins the press palette. An operator who works a night
 * close wants the machine to decide; one reading a bill against a printout
 * wants it pinned. Collapsing those into one switch takes a choice away.
 *
 * Density has two. Comfortable is the instrument as drawn; Compact tightens
 * the 4px spacing base and the data type a step, so every padding, gap and
 * row on every screen closes up together — analysts clearing a queue pick it,
 * CSRs on a call usually do not. Both are per-person preferences, kept in this
 * browser, and applied before first paint so neither flashes.
 */

type Choice = 'light' | 'system' | 'dark'
type Density = 'comfortable' | 'compact'

const THEME_KEY = 'tu-theme'
const DENSITY_KEY = 'tu-density'

const OPTIONS: { value: Choice; label: string; hint: string }[] = [
  { value: 'light', label: 'Day', hint: 'The paper palette — the default' },
  { value: 'system', label: 'Auto', hint: 'Follow the operating system' },
  { value: 'dark', label: 'Night', hint: 'Always the press palette' },
]

const DENSITIES: { value: Density; label: string; hint: string }[] = [
  { value: 'comfortable', label: 'Comfortable', hint: 'Room to read — on a call, or new to the screen' },
  { value: 'compact', label: 'Compact', hint: 'More rows on screen — for working a queue' },
]

function applyTheme(choice: Choice) {
  const root = document.documentElement
  if (choice === 'system') root.removeAttribute('data-theme')
  else root.setAttribute('data-theme', choice)
}

function applyDensity(d: Density) {
  const root = document.documentElement
  if (d === 'compact') root.setAttribute('data-density', 'compact')
  else root.removeAttribute('data-density')
}

/* The sidebar and Settings both show these switches; one changing tells the other. */
const DISPLAY_EVENT = 'tu-display'

function useDisplaySync<T>(key: string, set: (v: T) => void) {
  useEffect(() => {
    const on = (e: Event) => {
      const d = (e as CustomEvent<{ key: string; value: T }>).detail
      if (d?.key === key) set(d.value)
    }
    window.addEventListener(DISPLAY_EVENT, on)
    return () => window.removeEventListener(DISPLAY_EVENT, on)
  }, [key, set])
}

function remember(key: string, value: string) {
  window.dispatchEvent(new CustomEvent(DISPLAY_EVENT, { detail: { key, value } }))
  try {
    window.localStorage.setItem(key, value)
  } catch {
    /* Private browsing denies storage. The choice still applies to this
       session; it simply will not be remembered — never a blocked interaction. */
  }
}

function Segmented<T extends string>({
  label,
  options,
  value,
  onSelect,
}: {
  label: string
  options: { value: T; label: string; hint: string }[]
  value: T
  onSelect: (v: T) => void
}) {
  return (
    <div role="radiogroup" aria-label={label} className="flex gap-0.5 rounded-full border border-rule-hair bg-surface-sunken p-0.5">
      {options.map((o) => {
        const active = o.value === value
        return (
          <button
            key={o.value}
            type="button"
            role="radio"
            aria-checked={active}
            title={o.hint}
            onClick={() => onSelect(o.value)}
            className={`flex-1 rounded-full px-2 py-1 text-micro transition-colors duration-fast ${
              active ? 'bg-accent-wash text-ink-primary font-medium' : 'bg-surface-raised text-ink-tertiary hover:bg-surface-sunken hover:text-ink-primary'
            }`}
          >
            {o.label}
          </button>
        )
      })}
    </div>
  )
}

export function ThemeControl({ bare = false }: { bare?: boolean } = {}) {
  /* Render the default on the server and correct after mount — the inline
     script in the layout has already painted the right palette, so this only
     syncs the control's own highlight and never causes a visible change. */
  const [choice, setChoice] = useState<Choice>('light')
  useDisplaySync<Choice>(THEME_KEY, setChoice)

  useEffect(() => {
    try {
      const stored = window.localStorage.getItem(THEME_KEY)
      if (stored === 'system' || stored === 'dark') setChoice(stored)
    } catch {
      /* Storage denied — stay on the default. */
    }
  }, [])

  function select(next: Choice) {
    setChoice(next)
    applyTheme(next)
    remember(THEME_KEY, next)
  }

  return (
    <div>
      {bare ? null : <p className="field-label mb-1">Appearance</p>}
      <Segmented label="Appearance" options={OPTIONS} value={choice} onSelect={select} />
    </div>
  )
}

export function DensityControl({ bare = false }: { bare?: boolean } = {}) {
  const [density, setDensity] = useState<Density>('comfortable')
  useDisplaySync<Density>(DENSITY_KEY, setDensity)

  useEffect(() => {
    try {
      if (window.localStorage.getItem(DENSITY_KEY) === 'compact') setDensity('compact')
    } catch {
      /* Storage denied — stay comfortable. */
    }
  }, [])

  function select(next: Density) {
    setDensity(next)
    applyDensity(next)
    remember(DENSITY_KEY, next)
  }

  return (
    <div>
      {bare ? null : <p className="field-label mb-1">Density</p>}
      <Segmented label="Density" options={DENSITIES} value={density} onSelect={select} />
    </div>
  )
}

/**
 * Runs before first paint, so neither a pinned theme nor compact density is
 * preceded by a flash of the other. Anything but an explicit Auto or Night
 * paints Day. Kept to a single expression with no interpolated values —
 * nothing here is derived from data, so there is no injection surface.
 */
export const THEME_BOOTSTRAP = `try{var r=document.documentElement,t=localStorage.getItem('${THEME_KEY}');if(t!=='system')r.setAttribute('data-theme',t==='dark'?'dark':'light');if(localStorage.getItem('${DENSITY_KEY}')==='compact')r.setAttribute('data-density','compact')}catch(e){document.documentElement.setAttribute('data-theme','light')}`
