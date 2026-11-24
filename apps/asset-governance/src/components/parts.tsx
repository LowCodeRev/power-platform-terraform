import { useEffect, useMemo } from 'react'
import { animate, motion, useMotionValue, useTransform } from 'motion/react'
import { Area, AreaChart, CartesianGrid, XAxis } from 'recharts'
import { ChartContainer, ChartTooltip, ChartTooltipContent } from '@/components/ui/chart'
import type { ChartConfig } from '@/components/ui/chart'
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'
import { cn } from '@/lib/utils'
import { fmtDate, stageLabel, stageOf, typeOf } from '@/data'
import type { Asset, Scan, StageKey } from '@/data'

export const STAGE_COLOR: Record<StageKey | 'New', string> = {
  Active: 'var(--stage-active)',
  QuarantineWarning: 'var(--stage-qwarn)',
  Quarantine: 'var(--stage-quar)',
  DeleteWarning: 'var(--stage-dwarn)',
  Delete: 'var(--stage-del)',
  Exempt: 'var(--stage-exempt)',
  New: 'var(--muted-foreground)',
}

export function CountUp({ value, className }: { value: number; className?: string }) {
  const mv = useMotionValue(0)
  const text = useTransform(mv, (v) => Math.round(v).toLocaleString())
  useEffect(() => {
    const controls = animate(mv, value, { duration: 1.1, ease: [0.16, 1, 0.3, 1] })
    return () => controls.stop()
  }, [mv, value])
  return <motion.span className={cn('tabular-nums', className)}>{text}</motion.span>
}

export function StagePill({ stage, className }: { stage: StageKey | null; className?: string }) {
  const color = STAGE_COLOR[stage ?? 'New']
  return (
    <span
      className={cn('inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-xs font-medium whitespace-nowrap', className)}
      style={{ color, borderColor: `color-mix(in oklch, ${color} 45%, transparent)`, background: `color-mix(in oklch, ${color} 12%, transparent)` }}
    >
      <span className="size-1.5 rounded-full" style={{ background: color, boxShadow: `0 0 8px ${color}` }} />
      {stageLabel(stage)}
    </span>
  )
}

/** Ring gauge: share of tracked assets that are active or exempt. */
export function HealthGauge({ healthy, total }: { healthy: number; total: number }) {
  const pct = total ? healthy / total : 0
  const r = 70
  const c = 2 * Math.PI * r
  return (
    <div className="relative mx-auto size-48">
      <svg viewBox="0 0 180 180" className="size-full -rotate-90" role="img" aria-label={`${Math.round(pct * 100)}% of assets are healthy`}>
        <defs>
          <linearGradient id="gauge" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stopColor="var(--stage-active)" />
            <stop offset="100%" stopColor="var(--stage-exempt)" />
          </linearGradient>
        </defs>
        <circle cx="90" cy="90" r={r} fill="none" stroke="currentColor" strokeWidth="12" className="text-muted/60" />
        <motion.circle
          cx="90" cy="90" r={r} fill="none" stroke="url(#gauge)" strokeWidth="12" strokeLinecap="round"
          strokeDasharray={c}
          initial={{ strokeDashoffset: c }}
          animate={{ strokeDashoffset: c * (1 - pct) }}
          transition={{ duration: 1.4, ease: [0.16, 1, 0.3, 1] }}
          style={{ filter: 'drop-shadow(0 0 10px var(--stage-active))' }}
        />
      </svg>
      <div className="absolute inset-0 grid place-content-center text-center">
        <div className="text-4xl font-semibold tracking-tight"><CountUp value={Math.round(pct * 100)} />%</div>
        <div className="text-xs text-muted-foreground">healthy</div>
      </div>
    </div>
  )
}

function hash(s: string): number {
  let h = 2166136261
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619) }
  // Final avalanche so ids that differ only in their last characters still spread across the track.
  h ^= h >>> 16; h = Math.imul(h, 2246822507); h ^= h >>> 13; h = Math.imul(h, 3266489909); h ^= h >>> 16
  return (h >>> 0) / 4294967295
}

export interface Periods { inactive: number; warnQ: number; quarantined: number; warnD: number }

/**
 * The lifecycle as a track. Each asset is a dot placed by days inactive, so it drifts right as it ages and
 * crosses into the next zone on the date the policy would act.
 */
export function Conveyor({ assets, periods, onSelect }: { assets: Asset[]; periods: Periods; onSelect: (a: Asset) => void }) {
  const zones = useMemo(() => {
    const deleteAt = periods.inactive + periods.warnQ + periods.quarantined + periods.warnD
    const tail = Math.max(deleteAt * 0.12, 1)
    const span = deleteAt + tail
    const raw: { key: StageKey; label: string; days: number; from: number }[] = [
      { key: 'Active', label: 'Active', days: periods.inactive, from: 0 },
      { key: 'QuarantineWarning', label: 'Warn', days: periods.warnQ, from: periods.inactive },
      { key: 'Quarantine', label: 'Quarantine', days: periods.quarantined, from: periods.inactive + periods.warnQ },
      { key: 'DeleteWarning', label: 'Warn', days: periods.warnD, from: periods.inactive + periods.warnQ + periods.quarantined },
      { key: 'Delete', label: 'Delete', days: tail, from: deleteAt },
    ]
    return { span, list: raw.map((z) => ({ ...z, left: (z.from / span) * 100, width: (z.days / span) * 100 })) }
  }, [periods])

  const dots = assets.slice(0, 800)
  return (
    <div>
      <div className="relative h-64 overflow-hidden rounded-xl border bg-background/40">
        {zones.list.map((z) => (
          <div
            key={z.key}
            className="absolute inset-y-0 border-r border-dashed last:border-r-0"
            style={{ left: `${z.left}%`, width: `${z.width}%`, background: `linear-gradient(to bottom, color-mix(in oklch, ${STAGE_COLOR[z.key]} 14%, transparent), transparent 80%)`, borderColor: `color-mix(in oklch, ${STAGE_COLOR[z.key]} 35%, transparent)` }}
          >
            <span className="absolute top-2 left-2 truncate text-[10px] font-semibold tracking-widest uppercase" style={{ color: STAGE_COLOR[z.key] }}>
              {z.width > 6 ? z.label : ''}
            </span>
          </div>
        ))}
        <div className="sweep pointer-events-none absolute inset-y-0 w-1/4 bg-gradient-to-r from-transparent via-white/[0.06] to-transparent" style={{ animation: 'sweep 7s linear infinite' }} />
        {dots.map((a, i) => {
          const stage = stageOf(a.rev_stage)
          const color = STAGE_COLOR[stage ?? 'New']
          const days = Math.min(a.rev_daysinactive ?? 0, zones.span)
          const x = 1.5 + (days / zones.span) * 97
          const y = 18 + hash(a.rev_governedassetid) * 72
          const flagged = stage !== 'Active' && stage !== 'Exempt'
          return (
            <Tooltip key={a.rev_governedassetid}>
              <TooltipTrigger asChild>
                <motion.button
                  type="button"
                  aria-label={`${a.rev_name}, ${stageLabel(stage)}, ${Math.floor(a.rev_daysinactive ?? 0)} days inactive`}
                  onClick={() => onSelect(a)}
                  className="absolute -ml-1.5 -mt-1.5 size-3 rounded-full outline-offset-4 focus-visible:outline-2"
                  style={{ top: `${y}%`, background: color, boxShadow: `0 0 12px 1px ${color}` }}
                  initial={{ left: '0%', opacity: 0, scale: 0 }}
                  animate={{ left: `${x}%`, opacity: 1, scale: 1 }}
                  transition={{ type: 'spring', stiffness: 40, damping: 14, delay: Math.min(i * 0.03, 1.2) }}
                  whileHover={{ scale: 1.8 }}
                >
                  {flagged && <span className="ping-soft absolute inset-0 rounded-full" style={{ background: color, animation: 'ping-soft 2.2s ease-out infinite' }} />}
                </motion.button>
              </TooltipTrigger>
              <TooltipContent>
                <div className="font-medium">{a.rev_name}</div>
                <div className="opacity-80">{typeOf(a)} · {Math.floor(a.rev_daysinactive ?? 0)} days inactive · {stageLabel(stage)}</div>
              </TooltipContent>
            </Tooltip>
          )
        })}
      </div>
      <div className="relative mt-1.5 h-4 text-[10px] text-muted-foreground tabular-nums">
        <span className="absolute left-0">day 0</span>
        {zones.list.slice(1).map((z) => (
          <span key={z.key} className="absolute -translate-x-1/2" style={{ left: `${z.left}%` }}>{Math.round(z.from)}</span>
        ))}
      </div>
      {assets.length > dots.length && <p className="mt-1 text-xs text-muted-foreground">Showing {dots.length} of {assets.length} assets.</p>}
    </div>
  )
}

const trendConfig = {
  tracked: { label: 'Tracked', color: 'var(--stage-exempt)' },
  flagged: { label: 'Flagged', color: 'var(--stage-quar)' },
} satisfies ChartConfig

export function TrendChart({ scans }: { scans: Scan[] }) {
  const data = [...scans].reverse().map((s) => ({
    when: s.rev_scanon ?? '',
    tracked: s.rev_totalcount ?? 0,
    flagged: (s.rev_totalcount ?? 0) - (s.rev_activecount ?? 0) - (s.rev_exemptcount ?? 0),
  }))
  if (data.length < 2) return <p className="grid h-72 place-content-center text-sm text-muted-foreground">The trend appears after the second scan.</p>
  return (
    <ChartContainer config={trendConfig} className="h-72 w-full">
      <AreaChart data={data} margin={{ left: 4, right: 4, top: 8 }}>
        <defs>
          {(['tracked', 'flagged'] as const).map((k) => (
            <linearGradient key={k} id={`fill-${k}`} x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor={`var(--color-${k})`} stopOpacity={0.5} />
              <stop offset="95%" stopColor={`var(--color-${k})`} stopOpacity={0.02} />
            </linearGradient>
          ))}
        </defs>
        <CartesianGrid vertical={false} strokeOpacity={0.2} />
        <XAxis dataKey="when" tickLine={false} axisLine={false} tickMargin={8} minTickGap={40} tickFormatter={(v: string) => fmtDate(v)} />
        <ChartTooltip content={<ChartTooltipContent labelFormatter={(v) => fmtDate(String(v))} />} />
        <Area dataKey="tracked" type="monotone" stroke="var(--color-tracked)" strokeWidth={2} fill="url(#fill-tracked)" />
        <Area dataKey="flagged" type="monotone" stroke="var(--color-flagged)" strokeWidth={2} fill="url(#fill-flagged)" />
      </AreaChart>
    </ChartContainer>
  )
}
