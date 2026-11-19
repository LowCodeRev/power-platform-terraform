import { motion } from 'motion/react'
import { Activity, ArrowRight, CalendarClock } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { CountUp, STAGE_COLOR, StagePill } from '@/components/parts'
import { cn } from '@/lib/utils'
import { STAGES, fmtDateTime, stageOf } from '@/data'
import type { Asset, AssetEvent } from '@/data'
import { spaced } from '@/inactive'
import type { InactiveSummary } from '@/inactive'
import { REPORTS, glass, rise } from '@/shell'
import type { ViewId } from '@/shell'
import { UpNextList } from './inactive-assets'

function Kpi({ label, hint, color, children }: { label: string; hint: string; color?: string; children: React.ReactNode }) {
  return (
    <div className={cn(glass, 'relative overflow-hidden rounded-xl border p-4')}>
      {color && <span className="absolute -top-8 -right-8 size-24 rounded-full opacity-20 blur-2xl" style={{ background: color }} />}
      <div className="text-xs font-medium tracking-wide text-muted-foreground uppercase">{label}</div>
      <div className="mt-1 text-3xl font-semibold tracking-tight" style={{ color }}>{children}</div>
      <div className="mt-0.5 truncate text-xs text-muted-foreground">{hint}</div>
    </div>
  )
}

function StageBar({ s }: { s: InactiveSummary }) {
  if (s.total === 0) return <div className="h-2 rounded-full bg-muted" />
  return (
    <div className="flex h-2 gap-0.5 overflow-hidden rounded-full" role="img"
      aria-label={STAGES.map((st) => `${s.counts[st.key]} ${st.label}`).join(', ')}>
      {STAGES.filter((st) => s.counts[st.key] > 0).map((st) => (
        <motion.span key={st.key} className="h-full rounded-full" style={{ background: STAGE_COLOR[st.key] }}
          initial={{ flexGrow: 0 }} animate={{ flexGrow: s.counts[st.key] }} transition={{ duration: 0.9, ease: 'easeOut' }} />
      ))}
    </div>
  )
}

export function Overview({ s, events, onOpen, onSelect }: { s: InactiveSummary; events: AssetEvent[]; onOpen: (v: ViewId) => void; onSelect: (a: Asset) => void }) {
  const next = s.upNext[0]
  const byId = new Map(s.assets.map((a) => [a.rev_governedassetid, a]))
  const recent = events.slice(0, 6)
  const pct = s.total ? Math.round((s.healthy / s.total) * 100) : 0

  return (
    <div className="grid gap-5">
      <motion.section {...rise(1)} className="grid grid-cols-2 gap-3 xl:grid-cols-4" aria-label="Key figures">
        <Kpi label="Assets tracked" hint="Apps and cloud flows under policy"><CountUp value={s.total} /></Kpi>
        <Kpi label="Healthy" hint="Active or exempt" color={STAGE_COLOR.Active}><CountUp value={pct} />%</Kpi>
        <Kpi label="Flagged" hint="Past the inactivity threshold" color={s.flagged ? STAGE_COLOR.Quarantine : undefined}><CountUp value={s.flagged} /></Kpi>
        <Kpi label="Next action" hint={next ? `${next.a.rev_name}: ${spaced(next.a.rev_nextstage).toLowerCase()}` : 'Nothing scheduled'} color={next ? STAGE_COLOR.QuarantineWarning : undefined}>
          {next ? <><CountUp value={next.days} /><span className="ml-1 text-base font-normal text-muted-foreground">{next.days === 1 ? 'day' : 'days'}</span></> : '—'}
        </Kpi>
      </motion.section>

      <motion.section {...rise(2)} aria-labelledby="reports-heading">
        <h2 id="reports-heading" className="mb-3 text-xs font-semibold tracking-widest text-muted-foreground uppercase">Reports</h2>
        <div className="grid gap-4 md:grid-cols-2 2xl:grid-cols-3">
          {REPORTS.map((r) => {
            const Icon = r.icon
            if (!r.id) {
              return (
                <div key={r.label} className="rounded-xl border border-dashed p-5 text-muted-foreground">
                  <div className="flex items-center gap-2 font-medium"><Icon className="size-4" />{r.label}<Badge variant="outline" className="ml-auto">Planned</Badge></div>
                  <p className="mt-2 text-sm">{r.blurb}</p>
                </div>
              )
            }
            const id = r.id
            return (
              <motion.button key={r.label} type="button" onClick={() => onOpen(id)} whileHover={{ y: -3 }} whileTap={{ scale: 0.99 }}
                className={cn(glass, 'group rounded-xl border p-5 text-left outline-offset-2 focus-visible:outline-2')}>
                <div className="flex items-center gap-2 font-medium"><Icon className="size-4" />{r.label}<Badge variant="outline" className="ml-auto">Report only</Badge></div>
                <p className="mt-2 text-sm text-muted-foreground">{r.blurb}</p>
                <div className="mt-4"><StageBar s={s} /></div>
                <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground">
                  {STAGES.filter((st) => s.counts[st.key] > 0).map((st) => (
                    <span key={st.key} className="flex items-center gap-1.5"><span className="size-2 rounded-full" style={{ background: STAGE_COLOR[st.key] }} />{s.counts[st.key]} {st.label.toLowerCase()}</span>
                  ))}
                  {s.total === 0 && <span>No scan results yet</span>}
                </div>
                <div className="mt-4 flex items-center gap-1 text-sm font-medium">Open report <ArrowRight className="size-4 transition-transform group-hover:translate-x-1" /></div>
              </motion.button>
            )
          })}
        </div>
      </motion.section>

      <motion.section {...rise(3)} className="grid gap-5 lg:grid-cols-2">
        <Card className={glass}>
          <CardHeader>
            <CardTitle className="flex items-center gap-2"><CalendarClock className="size-4" /> Up next</CardTitle>
            <CardDescription>The next stage changes the inactive asset policy would make</CardDescription>
          </CardHeader>
          <CardContent><UpNextList items={s.upNext.slice(0, 5)} onSelect={onSelect} /></CardContent>
        </Card>

        <Card className={glass}>
          <CardHeader>
            <CardTitle className="flex items-center gap-2"><Activity className="size-4" /> Recent activity</CardTitle>
            <CardDescription>Stage changes recorded by the latest scans</CardDescription>
          </CardHeader>
          <CardContent>
            {recent.length === 0 ? <p className="text-sm text-muted-foreground">No stage changes recorded.</p> : (
              <ul className="grid gap-1">
                {recent.map((e) => {
                  const a = e._rev_asset_value ? byId.get(e._rev_asset_value) : undefined
                  const body = (
                    <>
                      <span className="min-w-0 flex-1">
                        <span className="block truncate font-medium">{a?.rev_name ?? 'Removed asset'}</span>
                        <span className="text-xs text-muted-foreground">{fmtDateTime(e.rev_eventon)}</span>
                      </span>
                      <StagePill stage={stageOf(e.rev_tostage)} />
                    </>
                  )
                  return (
                    <li key={e.rev_asseteventid}>
                      {a ? <button type="button" onClick={() => onSelect(a)} className="flex w-full items-center gap-3 rounded-lg px-2 py-1.5 text-left text-sm hover:bg-muted/50 focus-visible:outline-2">{body}</button>
                        : <div className="flex items-center gap-3 px-2 py-1.5 text-sm">{body}</div>}
                    </li>
                  )
                })}
              </ul>
            )}
          </CardContent>
        </Card>
      </motion.section>
    </div>
  )
}
