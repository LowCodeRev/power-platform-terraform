import { Rev_governedassetsService, Rev_assetscansService, Rev_asseteventsService } from './generated'
import type { Rev_governedassets } from './generated/models/Rev_governedassetsModel'
import type { Rev_assetscans } from './generated/models/Rev_assetscansModel'
import type { Rev_assetevents } from './generated/models/Rev_asseteventsModel'

export type Asset = Rev_governedassets
export type Scan = Rev_assetscans
export type AssetEvent = Rev_assetevents

// Stage choice values share one global choice; the last digit is the stage's position on the timeline.
export const STAGES = [
  { key: 'Active', label: 'Active', verb: 'Left alone' },
  { key: 'QuarantineWarning', label: 'Quarantine warning', verb: 'Warned of quarantine' },
  { key: 'Quarantine', label: 'Quarantine', verb: 'Quarantined' },
  { key: 'DeleteWarning', label: 'Delete warning', verb: 'Warned of deletion' },
  { key: 'Delete', label: 'Delete', verb: 'Deleted' },
  { key: 'Exempt', label: 'Exempt', verb: 'Exempt' },
] as const

export type StageKey = (typeof STAGES)[number]['key']

export function stageOf(value: unknown): StageKey | null {
  const n = Number(value)
  if (!Number.isFinite(n) || value === null || value === undefined) return null
  return STAGES[n % 10]?.key ?? null
}

export const stageLabel = (key: StageKey | null) => STAGES.find((s) => s.key === key)?.label ?? 'New'

export const typeOf = (a: Asset) => (Number(a.rev_assettype) % 10 === 1 ? 'Flow' : 'App')

export interface Snapshot {
  assets: Asset[]
  scans: Scan[]
  events: AssetEvent[]
}

async function unwrap<T>(p: Promise<{ data?: T[]; error?: { message?: string } }>, what: string): Promise<T[]> {
  const r = await p
  if (r.error) throw new Error(`${what}: ${r.error.message ?? 'request failed'}`)
  return r.data ?? []
}

export async function loadSnapshot(): Promise<Snapshot> {
  const [assets, scans, events] = await Promise.all([
    unwrap(Rev_governedassetsService.getAll({ filter: 'statecode eq 0', orderBy: ['rev_daysinactive desc'], top: 5000 }), 'Assets'),
    unwrap(Rev_assetscansService.getAll({ orderBy: ['rev_scanon desc'], top: 200 }), 'Scans'),
    unwrap(Rev_asseteventsService.getAll({ orderBy: ['rev_eventon desc'], top: 200 }), 'Events'),
  ])
  return { assets, scans, events }
}

export function fmtDate(iso?: string | null): string {
  if (!iso) return '—'
  const d = new Date(iso)
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' })
}

export function fmtDateTime(iso?: string | null): string {
  if (!iso) return '—'
  const d = new Date(iso)
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleString(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })
}
