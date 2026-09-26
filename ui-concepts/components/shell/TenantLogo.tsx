/**
 * The tenant's mark in the top band.
 *
 * Placeholder artwork for the fictional Brazos Valley Gas: a gas flame over the
 * river the valley is named for. A real tenant supplies its own file, which
 * replaces this component's body with an <img>. The colours are the tenant's
 * brand, not theme tokens — the band behind it is dark in both themes.
 */
export function TenantLogo({ name, size = 20 }: { name: string; size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      role="img"
      aria-label={`${name} logo`}
      className="shrink-0"
    >
      <rect width="24" height="24" rx="5" fill="#1d4f7a" />
      <path
        d="M12 3.5c.6 2.4 3.6 4.4 3.6 7.9a3.6 3.6 0 0 1-7.2 0c0-1.7.9-2.8 1.8-3.8.2 1.2.8 1.9 1.5 2.2-.3-2.2-.2-4.3.3-6.3Z"
        fill="#f59e2b"
      />
      <path d="M11.9 9.6c.3 1.2 1.6 2 1.6 3.4a1.5 1.5 0 0 1-3 0c0-.9.6-1.5 1-2 .1.4.3.7.6.8-.2-.7-.3-1.5-.2-2.2Z" fill="#ffe2a8" />
      <path
        d="M3.5 17.6c1.4 0 1.4-.9 2.8-.9s1.4.9 2.8.9 1.4-.9 2.9-.9 1.4.9 2.8.9 1.4-.9 2.8-.9 1.4.9 2.9.9"
        fill="none"
        stroke="#8fc3ea"
        strokeWidth="1.3"
        strokeLinecap="round"
      />
      <path
        d="M3.5 20.3c1.4 0 1.4-.9 2.8-.9s1.4.9 2.8.9 1.4-.9 2.9-.9 1.4.9 2.8.9 1.4-.9 2.8-.9 1.4.9 2.9.9"
        fill="none"
        stroke="#8fc3ea"
        strokeOpacity=".55"
        strokeWidth="1.3"
        strokeLinecap="round"
      />
    </svg>
  )
}
