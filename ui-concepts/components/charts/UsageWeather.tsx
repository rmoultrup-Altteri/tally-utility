/**
 * Thirteen bill periods of gas against the cold that drove it.
 *
 * Bars are therms, the line is heating degree days. The bill being explained
 * and the bill it is compared with are the only two bars in colour — the rest
 * of the year is context, not the subject. Gas load climbs with the cold, so
 * the picture a customer should recognise is the bars tracking the line.
 */

export type UsagePoint = {
  label: string
  therms: number
  hdd: number
  estimated?: boolean
  mark?: 'current' | 'compare'
}

/** Month only, except on the two marked bars, which carry the year — two Februaries side by side need telling apart. */
function tick(p: UsagePoint): string {
  const [m, y] = p.label.split(' ')
  return p.mark && y ? `${m} ’${y.slice(-2)}` : m
}

export function UsageWeather({
  points,
  height = 140,
  legend = true,
  labels = { therms: 'Therms billed', hdd: 'Heating degree days', current: 'This bill', compare: 'Compared with' },
}: {
  points: UsagePoint[]
  height?: number
  legend?: boolean
  labels?: { therms: string; hdd: string; current: string; compare: string }
}) {
  const width = 640
  const step = width / Math.max(points.length, 1)
  const maxT = Math.max(...points.map((p) => p.therms), 1)
  const maxH = Math.max(...points.map((p) => p.hdd), 1)
  const line = points
    .map((p, i) => `${i * step + step / 2},${height - (p.hdd / maxH) * height * 0.9}`)
    .join(' ')

  return (
    <div>
      <svg viewBox={`0 0 ${width} ${height + 22}`} className="w-full" style={{ height: height + 22 }} role="img" aria-label={`${labels.therms} by bill period against ${labels.hdd.toLowerCase()}`}>
        <defs>
          <pattern id="uw-est" width="6" height="6" patternTransform="rotate(45)" patternUnits="userSpaceOnUse">
            <rect width="6" height="6" className="fill-read-estimated-wash" />
            <line x1="0" y1="0" x2="0" y2="6" strokeWidth="3" className="stroke-read-estimated-rail" />
          </pattern>
        </defs>
        {points.map((p, i) => {
          const h = (p.therms / maxT) * height * 0.9
          return (
            <g key={p.label}>
              <rect
                x={i * step + step * 0.2}
                y={height - h}
                width={step * 0.6}
                height={h}
                rx={2}
                fill={p.estimated && !p.mark ? 'url(#uw-est)' : undefined}
                className={
                  p.mark === 'current'
                    ? 'fill-exception-warning-rail'
                    : p.mark === 'compare'
                      ? 'fill-rule-heavy'
                      : p.estimated
                        ? ''
                        : 'fill-rule-solid'
                }
              />
              {p.mark ? (
                <text x={i * step + step / 2} y={height - h - 4} textAnchor="middle" className="fill-ink-secondary" style={{ fontSize: '10px' }}>
                  {Math.round(p.therms)}
                </text>
              ) : null}
              <text x={i * step + step / 2} y={height + 15} textAnchor="middle" className={p.mark ? 'fill-ink-primary' : 'fill-ink-tertiary'} style={{ fontSize: '9.5px' }}>
                {tick(p)}
              </text>
            </g>
          )
        })}
        <polyline points={line} fill="none" strokeWidth={1.6} className="stroke-exception-info-rail" />
      </svg>
      {legend ? (
        <div className="mt-1.5 flex flex-wrap items-center gap-x-4 gap-y-1 text-micro text-ink-secondary">
          <span className="flex items-center gap-1.5">
            <span className="inline-block h-2.5 w-2.5 rounded-xs bg-exception-warning-rail" /> {labels.current}
          </span>
          <span className="flex items-center gap-1.5">
            <span className="inline-block h-2.5 w-2.5 rounded-xs bg-rule-heavy" /> {labels.compare}
          </span>
          <span className="flex items-center gap-1.5">
            <span className="inline-block h-2.5 w-2.5 rounded-xs bg-rule-solid" /> {labels.therms}
          </span>
          <span className="flex items-center gap-1.5">
            <span className="inline-block h-0.5 w-4 bg-exception-info-rail" /> {labels.hdd}
          </span>
        </div>
      ) : null}
    </div>
  )
}
