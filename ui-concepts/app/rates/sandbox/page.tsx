import { permanentRedirect } from 'next/navigation'

/**
 * The tariff sandbox grew into the rate case toolkit, which rehearses a
 * design against a full test year and carries it through to the filing.
 * Old links and bookmarks land there.
 */
export default function TariffSandboxPage() {
  permanentRedirect('/rates/rate-case')
}
