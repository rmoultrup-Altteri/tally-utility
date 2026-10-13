/**
 * Our own wordmark in the top band: "Tally Utility" with the "ll" drawn as a
 * tally gate — two strokes and the strike across them, all in the brand blue.
 * Artwork: `logos/07 · Tally Gate, struck ll_new.png`.
 *
 * The strike is knocked out of the two strokes beneath it, as in the artwork,
 * with a mask rather than a band-coloured outline so it holds on any ground.
 *
 * Like the tenant's mark, the colours are brand, not theme tokens — the band
 * behind it is dark in both themes, so this is the on-dark variant only.
 */
const GATE = '#86b1ff'

export function TallyLogo() {
  return (
    <span role="img" aria-label="Tally Utility" className="flex items-center">
      <span aria-hidden className="text-[17px] leading-none font-bold tracking-[-0.03em] whitespace-nowrap">
        Ta
        {/* Measured off the artwork: strokes at the ascender height, sitting
            on the baseline; the strike runs past both, under the "y". */}
        <svg viewBox="0 0 52 59" className="inline-block h-[0.76em] w-[0.67em] mr-[-0.1em] align-baseline overflow-visible">
          <mask id="tally-gate-knock" maskUnits="userSpaceOnUse" x="-4" y="-4" width="60" height="67">
            <rect x="-4" y="-4" width="60" height="67" fill="white" />
            <line x1="5" y1="46" x2="47" y2="6" stroke="black" strokeWidth="12.5" strokeLinecap="round" />
          </mask>
          <g stroke={GATE} strokeWidth="9" strokeLinecap="round">
            <g mask="url(#tally-gate-knock)">
              <line x1="13" y1="4.5" x2="13" y2="54.5" />
              <line x1="33" y1="4.5" x2="33" y2="54.5" />
            </g>
            <line x1="5" y1="46" x2="47" y2="6" />
          </g>
        </svg>
        y Utility
      </span>
    </span>
  )
}
