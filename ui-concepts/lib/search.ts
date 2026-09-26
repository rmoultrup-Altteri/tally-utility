/**
 * Record-list search: every word typed must appear somewhere in the fields,
 * in any order, ignoring case — so "bryan wendell" finds Wendell Fry in Bryan.
 */
export function matchesSearch(query: string, fields: (string | null | undefined)[]): boolean {
  const terms = query.trim().toLowerCase().split(/\s+/).filter(Boolean)
  if (!terms.length) return true
  const haystack = fields.filter(Boolean).join(' ').toLowerCase()
  return terms.every((t) => haystack.includes(t))
}
