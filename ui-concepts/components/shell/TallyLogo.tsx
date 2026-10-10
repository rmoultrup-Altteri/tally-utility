/**
 * Our own wordmark in the top band: "Tally Utility" with a strike through the
 * "ll", the fifth stroke of a tally gate. Artwork:
 * `logos/07 · Tally Gate, struck ll@2x.png`.
 *
 * Like the tenant's mark, the colours are brand, not theme tokens — the band
 * behind it is dark in both themes, so this is the on-dark variant only.
 */
const STRIKE = '#8aaeff'

export function TallyLogo() {
  return (
    <span role="img" aria-label="Tally Utility" className="flex items-center">
      <span aria-hidden className="text-[17px] leading-none font-bold tracking-[-0.03em] whitespace-nowrap">
        Ta
        <span className="relative inline-block">
          ll
          <svg
            viewBox="0 0 20 20"
            preserveAspectRatio="none"
            className="pointer-events-none absolute -left-[0.14em] top-[0.06em] h-[0.86em] w-[calc(100%+0.28em)] overflow-visible"
          >
            <line
              x1="1"
              y1="16"
              x2="19"
              y2="4"
              stroke={STRIKE}
              strokeWidth="2.4"
              strokeLinecap="round"
              vectorEffect="non-scaling-stroke"
            />
          </svg>
        </span>
        y Utility
      </span>
    </span>
  )
}
