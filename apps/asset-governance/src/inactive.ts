import { STAGES, stageOf } from './data'
import type { Asset, Scan, Snapshot, StageKey } from './data'
import type { Periods } from '@/components/parts'

export interface InactiveSummary {
  assets: Asset[]
  counts: Record<StageKey, number>
  periods: Periods
  latest?: Scan
  total: number
  healthy: number
  flagged: number
  /** Soonest stage changes the policy would make, nearest first. */
  upNext: { a: Asset; days: number }[]
}

export function daysUntil(iso?: string): number | null {
  if (!iso) return null
  const t = new Date(iso).getTime()
  return Number.isNaN(t) ? null : Math.ceil((t - Date.now()) / 86400000)
}

export const spaced = (s?: string) => (s ?? '').replace(/([a-z])([A-Z])/g, '$1 $2')

export function summarize(snapshot: Snapshot | null): InactiveSummary {
  const assets = snapshot?.assets ?? []
  const counts = Object.fromEntries(STAGES.map((s) => [s.key, 0])) as Record<StageKey, number>
  for (const a of assets) { const k = stageOf(a.rev_stage); if (k) counts[k]++ }
  const latest = snapshot?.scans[0]
  const healthy = counts.Active + counts.Exempt
  const upNext = assets
    .map((a) => ({ a, days: daysUntil(a.rev_nextstageon) }))
    .filter((x): x is { a: Asset; days: number } => x.days !== null && x.days >= 0 && !!x.a.rev_nextstage && stageOf(x.a.rev_stage) !== 'Exempt')
    .sort((x, y) => x.days - y.days)
  return {
    assets, counts, latest, healthy, upNext,
    total: assets.length,
    flagged: assets.length - healthy,
    periods: {
      inactive: latest?.rev_inactivedays ?? 90,
      warnQ: latest?.rev_quarantinewarningdays ?? 14,
      quarantined: latest?.rev_quarantineddays ?? 90,
      warnD: latest?.rev_deletewarningdays ?? 14,
    },
  }
}
