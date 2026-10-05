import Link from 'next/link'
import type { Route } from 'next'
import type { ReactNode } from 'react'

/**
 * The few pieces of Markdown a chat answer uses: paragraphs, lists, small
 * tables, code, emphasis and links. Portal paths become in-app links so the
 * panel stays open while the operator follows one.
 */
export function Markdown({ text }: { text: string }) {
  return <div className="space-y-2">{blocks(text)}</div>
}

function blocks(text: string): ReactNode[] {
  const lines = text.replace(/\r\n/g, '\n').split('\n')
  const out: ReactNode[] = []
  let i = 0
  while (i < lines.length) {
    const line = lines[i]
    if (!line.trim()) {
      i++
      continue
    }
    if (line.startsWith('```')) {
      const body: string[] = []
      i++
      while (i < lines.length && !lines[i].startsWith('```')) body.push(lines[i++])
      i++
      out.push(
        <pre key={out.length} className="overflow-x-auto rounded-xs bg-surface-inset px-2 py-1.5 font-mono text-micro text-ink-primary">
          {body.join('\n')}
        </pre>,
      )
      continue
    }
    if (/^\s*\|.*\|\s*$/.test(line)) {
      const rows: string[] = []
      while (i < lines.length && /^\s*\|.*\|\s*$/.test(lines[i])) rows.push(lines[i++])
      out.push(<MdTable key={out.length} rows={rows} />)
      continue
    }
    const heading = line.match(/^#{1,6}\s+(.*)$/)
    if (heading) {
      out.push(
        <p key={out.length} className="text-data font-semibold text-ink-primary">
          {inline(heading[1])}
        </p>,
      )
      i++
      continue
    }
    if (/^\s*([-*•]|\d+[.)])\s+/.test(line)) {
      const ordered = /^\s*\d+[.)]/.test(line)
      const items: string[] = []
      while (i < lines.length && /^\s*([-*•]|\d+[.)])\s+/.test(lines[i])) {
        items.push(lines[i].replace(/^\s*([-*•]|\d+[.)])\s+/, ''))
        i++
        /* A wrapped continuation line belongs to the item above it. */
        while (i < lines.length && /^\s{2,}\S/.test(lines[i]) && !/^\s*([-*•]|\d+[.)])\s+/.test(lines[i]))
          items[items.length - 1] += ` ${lines[i++].trim()}`
      }
      const List = ordered ? 'ol' : 'ul'
      out.push(
        <List key={out.length} className={`space-y-0.5 pl-4 ${ordered ? 'list-decimal' : 'list-disc'} marker:text-ink-tertiary`}>
          {items.map((t, k) => (
            <li key={k}>{inline(t)}</li>
          ))}
        </List>,
      )
      continue
    }
    const para: string[] = []
    while (
      i < lines.length &&
      lines[i].trim() &&
      !/^(```|#{1,6}\s|\s*\||\s*([-*•]|\d+[.)])\s+)/.test(lines[i])
    )
      para.push(lines[i++])
    out.push(<p key={out.length}>{inline(para.join(' '))}</p>)
  }
  return out
}

function MdTable({ rows }: { rows: string[] }) {
  const cells = rows
    .filter((r) => !/^\s*\|[\s:|-]+\|\s*$/.test(r))
    .map((r) => r.trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim()))
  const [head, ...body] = cells
  if (!head) return null
  return (
    <div className="overflow-x-auto border border-rule-hair">
      <table className="w-full text-micro">
        <thead className="bg-surface-sunken">
          <tr>
            {head.map((h, k) => (
              <th key={k} className="px-1.5 py-1 text-left font-semibold text-ink-secondary whitespace-nowrap">
                {inline(h)}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {body.map((r, k) => (
            <tr key={k} className="border-t border-rule-hair">
              {r.map((c, j) => (
                <td key={j} className="px-1.5 py-1 align-top tabular-nums">
                  {inline(c)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

const INLINE = /(`[^`]+`|\*\*[^*]+\*\*|\[[^\]]+\]\([^)\s]+\)|https?:\/\/[^\s)<]+|\*[^*\s][^*]*\*)/g

function inline(text: string): ReactNode[] {
  return text.split(INLINE).map((part, k) => {
    if (!part) return null
    if (part.startsWith('`') && part.endsWith('`') && part.length > 2)
      return (
        <code key={k} className="rounded-xs bg-surface-inset px-1 font-mono text-[0.92em]">
          {part.slice(1, -1)}
        </code>
      )
    if (part.startsWith('**') && part.endsWith('**')) return <strong key={k} className="font-semibold text-ink-primary">{part.slice(2, -2)}</strong>
    const link = part.match(/^\[([^\]]+)\]\(([^)\s]+)\)$/)
    if (link) return <A key={k} href={link[2]}>{link[1]}</A>
    if (/^https?:\/\//.test(part)) return <A key={k} href={part}>{part.replace(/^https?:\/\/(www\.)?/, '').slice(0, 48)}</A>
    if (part.startsWith('*') && part.endsWith('*') && part.length > 2) return <em key={k}>{part.slice(1, -1)}</em>
    return part
  })
}

function A({ href, children }: { href: string; children: ReactNode }) {
  const cls = 'text-accent-text underline decoration-accent-text/40 underline-offset-2 hover:text-accent-text-hover'
  if (href.startsWith('/'))
    return (
      <Link href={href as Route} className={cls}>
        {children}
      </Link>
    )
  if (!/^https?:\/\//.test(href)) return <>{children}</>
  return (
    <a href={href} target="_blank" rel="noopener noreferrer" className={cls}>
      {children}
    </a>
  )
}
