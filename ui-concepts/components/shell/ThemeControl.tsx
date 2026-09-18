'use client'

import { useEffect, useState } from 'react'

/**
 * Theme control.
 *
 * Three states, not a toggle. "System" is the default and is the absence of an
 * attribute — the palette then follows `prefers-color-scheme` through
 * `light-dark()` with no JavaScript involved at all. Choosing Day or Night
 * pins `data-theme` on the document element and records the choice.
 *
 * An operator who works a night close and a morning cycle wants the app to
 * follow the machine; one reading a bill against a printout wants it pinned.
 * Collapsing those into one switch takes the second person's choice away.
 */

type Choice = 'light' | 'system' | 'dark'

const STORAGE_KEY = 'tu-theme'

const OPTIONS: { value: Choice; label: string; hint: string }[] = [
  { value: 'light', label: 'Day', hint: 'Always the paper palette' },
  { value: 'system', label: 'Auto', hint: 'Follow the operating system' },
  { value: 'dark', label: 'Night', hint: 'Always the press palette' },
]

function apply(choice: Choice) {
  const root = document.documentElement
  if (choice === 'system') {
    root.removeAttribute('data-theme')
  } else {
    root.setAttribute('data-theme', choice)
  }
}

export function ThemeControl() {
  /* Render "system" on the server and correct after mount — the inline script
     in the layout has already painted the right palette, so this only syncs
     the control's own highlight and never causes a visible change. */
  const [choice, setChoice] = useState<Choice>('system')

  useEffect(() => {
    const stored = window.localStorage.getItem(STORAGE_KEY)
    if (stored === 'light' || stored === 'dark') setChoice(stored)
  }, [])

  function select(next: Choice) {
    setChoice(next)
    apply(next)
    try {
      if (next === 'system') window.localStorage.removeItem(STORAGE_KEY)
      else window.localStorage.setItem(STORAGE_KEY, next)
    } catch {
      /* Private browsing denies storage. The choice still applies to this
         session; it simply will not be remembered, which is the correct
         degradation — never a blocked interaction. */
    }
  }

  return (
    <div>
      <p className="label-caps mb-1">Appearance</p>
      <div
        role="radiogroup"
        aria-label="Appearance"
        className="flex border border-rule-solid rounded-xs overflow-hidden"
      >
        {OPTIONS.map((o) => {
          const active = o.value === choice
          return (
            <button
              key={o.value}
              type="button"
              role="radio"
              aria-checked={active}
              title={o.hint}
              onClick={() => select(o.value)}
              className={`flex-1 px-2 py-1 text-micro transition-colors duration-fast ${
                active
                  ? 'bg-accent-wash text-ink-primary font-medium'
                  : 'bg-surface-raised text-ink-tertiary hover:bg-surface-sunken hover:text-ink-primary'
              }`}
            >
              {o.label}
            </button>
          )
        })}
      </div>
    </div>
  )
}

/**
 * Runs before first paint, so a pinned theme is never preceded by a flash of
 * the other one. Kept to a single expression with no interpolated values —
 * nothing here is derived from data, so there is no injection surface.
 */
export const THEME_BOOTSTRAP = `try{var t=localStorage.getItem('${STORAGE_KEY}');if(t==='dark'||t==='light')document.documentElement.setAttribute('data-theme',t)}catch(e){}`
