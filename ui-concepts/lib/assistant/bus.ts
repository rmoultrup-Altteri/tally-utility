'use client'

/**
 * Hand a request to the assistant from anywhere on the page.
 *
 * The chat lives in the root layout, so a screen cannot call it directly. A
 * screen dispatches this event instead; the assistant opens and sends the
 * text as if the operator had typed it. What comes back is still a proposal
 * the operator applies — the event only saves typing.
 */

export const ASK_EVENT = 'tu-assistant-ask'

export function askAssistant(text: string) {
  window.dispatchEvent(new CustomEvent(ASK_EVENT, { detail: { text } }))
}
