import { Hourglass, LayoutDashboard, ShieldCheck } from 'lucide-react'
import type { LucideIcon } from 'lucide-react'

export const glass = 'glass border-white/10 bg-card'

export const rise = (i: number) => ({
  initial: { opacity: 0, y: 18 },
  animate: { opacity: 1, y: 0 },
  transition: { duration: 0.5, delay: 0.06 * i, ease: [0.16, 1, 0.3, 1] as const },
})

export type ViewId = 'overview' | 'inactive-assets'

export interface ReportDef {
  id: ViewId | null
  label: string
  icon: LucideIcon
  blurb: string
}

/** Every report the dashboard knows about. A null id means it is planned and has no page yet. */
export const OVERVIEW: ReportDef = { id: 'overview', label: 'Overview', icon: LayoutDashboard, blurb: 'Governance posture across the tenant' }

export const REPORTS: ReportDef[] = [
  { id: 'inactive-assets', label: 'Inactive assets', icon: Hourglass, blurb: 'Apps and flows with no changes or runs, and what the policy would do with them' },
  { id: null, label: 'DLP policy drift', icon: ShieldCheck, blurb: 'Data loss prevention policies compared with the definitions in source control' },
]
