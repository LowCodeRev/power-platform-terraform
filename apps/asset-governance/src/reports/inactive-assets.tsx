import { useMemo, useState } from 'react'
import { motion } from 'motion/react'
import { AppWindow, ArrowRight, CalendarClock, Search, Workflow } from 'lucide-react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { ToggleGroup, ToggleGroupItem } from '@/components/ui/toggle-group'
import { Conveyor, CountUp, HealthGauge, STAGE_COLOR, StagePill, TrendChart } from '@/components/parts'
import { cn } from '@/lib/utils'
import { STAGES, fmtDate, stageOf, typeOf } from '@/data'
import type { Asset, Scan, StageKey } from '@/data'
import { spaced } from '@/inactive'
import type { InactiveSummary } from '@/inactive'
import { glass, rise } from '@/shell'

type StageFilter = StageKey | 'Flagged' | 'All'

export function InactiveAssetsReport({ s, scans, onSelect }: { s: InactiveSummary; scans: Scan[]; onSelect: (a: Asset) => void }) {
  const [stage, setStage] = useState<StageFilter>('Flagged')
  const [type, setType] = useState<'All' | 'App' | 'Flow'>('All')
  const [query, setQuery] = useState('')
  const { assets, counts, periods, total, healthy, flagged } = s
  const deleteAt = periods.inactive + periods.warnQ + periods.quarantined + periods.warnD

  const rows = useMemo(() => {
    const q = query.trim().toLowerCase()
    return assets.filter((a) => {
      const k = stageOf(a.rev_stage)
      if (stage === 'Flagged' ? k === 'Active' || k === 'Exempt' : stage !== 'All' && k !== stage) return false
      if (type !== 'All' && typeOf(a) !== type) return false
      return !q || [a.rev_name, a.rev_ownername, a.rev_ownerupn, a.rev_environmentname].some((v) => v?.toLowerCase().includes(q))
    })
  }, [assets, stage, type, query])

  return (
    <div className="grid gap-5">
      <motion.section {...rise(1)} className="grid gap-5 xl:grid-cols-[18rem_1fr]">
        <Card className={glass}>
          <CardHeader>
            <CardTitle>Fleet health</CardTitle>
            <CardDescription>Active or exempt, of everything tracked</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-3">
            <HealthGauge healthy={healthy} total={total} />
            <div className="grid grid-cols-2 gap-2 text-center text-sm">
              <div className="rounded-lg bg-muted/40 p-2"><div className="text-xl font-semibold"><CountUp value={total} /></div><div className="text-xs text-muted-foreground">tracked</div></div>
              <div className="rounded-lg bg-muted/40 p-2"><div className="text-xl font-semibold" style={{ color: flagged ? STAGE_COLOR.Quarantine : undefined }}><CountUp value={flagged} /></div><div className="text-xs text-muted-foreground">flagged</div></div>
            </div>
          </CardContent>
        </Card>

        <Card className={glass}>
          <CardHeader>
            <CardTitle>Lifecycle track</CardTitle>
            <CardDescription>Every asset by days inactive. It drifts right as it ages and changes stage at each line. Select a dot for detail.</CardDescription>
          </CardHeader>
          <CardContent>
            {total === 0 ? <p className="grid h-64 place-content-center text-sm text-muted-foreground">No assets tracked yet. Run the scan with a Dataverse URL.</p>
              : <Conveyor assets={assets} periods={periods} onSelect={onSelect} />}
          </CardContent>
        </Card>
      </motion.section>

      <section className="grid grid-cols-2 gap-3 md:grid-cols-3 2xl:grid-cols-6" aria-label="Assets by stage">
        {STAGES.map((st, i) => {
          const on = stage === st.key
          const color = STAGE_COLOR[st.key]
          return (
            <motion.button key={st.key} type="button" {...rise(2 + i * 0.5)} whileHover={{ y: -4 }} whileTap={{ scale: 0.97 }}
              onClick={() => setStage(on ? 'Flagged' : st.key)} aria-pressed={on}
              className={cn('glass relative overflow-hidden rounded-xl border bg-card p-4 text-left outline-offset-2 focus-visible:outline-2', on ? 'border-transparent' : 'border-white/10')}
              style={on ? { boxShadow: `0 0 0 1.5px ${color}, 0 12px 40px -12px ${color}` } : undefined}>
              <span className="absolute -top-8 -right-8 size-24 rounded-full opacity-25 blur-2xl" style={{ background: color }} />
              <div className="text-3xl font-semibold tracking-tight" style={{ color }}><CountUp value={counts[st.key]} /></div>
              <div className="mt-1 text-sm font-medium">{st.label}</div>
              <div className="text-xs text-muted-foreground">{st.verb}</div>
            </motion.button>
          )
        })}
      </section>

      <motion.section {...rise(5)} className="grid gap-5 lg:grid-cols-3">
        <Card className={cn(glass, 'lg:col-span-2')}>
          <CardHeader>
            <CardTitle>Trend</CardTitle>
            <CardDescription>Tracked and flagged assets at each scan</CardDescription>
          </CardHeader>
          <CardContent><TrendChart scans={scans.filter((x) => !x.rev_istest)} /></CardContent>
        </Card>

        <Card className={glass}>
          <CardHeader>
            <CardTitle className="flex items-center gap-2"><CalendarClock className="size-4" /> Up next</CardTitle>
            <CardDescription>The next stage changes the policy would make</CardDescription>
          </CardHeader>
          <CardContent><UpNextList items={s.upNext.slice(0, 6)} onSelect={onSelect} /></CardContent>
        </Card>
      </motion.section>

      <motion.section {...rise(6)}>
        <Card className={glass}>
          <CardHeader>
            <div className="flex flex-wrap items-center gap-3">
              <CardTitle className="mr-auto">Assets <span className="font-normal text-muted-foreground">({rows.length})</span></CardTitle>
              <div className="relative w-full sm:w-64">
                <Search className="pointer-events-none absolute top-1/2 left-2.5 size-4 -translate-y-1/2 text-muted-foreground" />
                <Input type="search" placeholder="Search name, owner, environment" value={query} onChange={(e) => setQuery(e.target.value)} className="pl-8" aria-label="Search assets" />
              </div>
              <ToggleGroup type="single" variant="outline" value={type} onValueChange={(v) => v && setType(v as typeof type)} aria-label="Asset type">
                <ToggleGroupItem value="All">All</ToggleGroupItem>
                <ToggleGroupItem value="App"><AppWindow /> Apps</ToggleGroupItem>
                <ToggleGroupItem value="Flow"><Workflow /> Flows</ToggleGroupItem>
              </ToggleGroup>
              <ToggleGroup type="single" variant="outline" value={stage === 'Flagged' || stage === 'All' ? stage : ''} onValueChange={(v) => v && setStage(v as StageFilter)} aria-label="Stage scope">
                <ToggleGroupItem value="Flagged">Flagged</ToggleGroupItem>
                <ToggleGroupItem value="All">Everything</ToggleGroupItem>
              </ToggleGroup>
            </div>
          </CardHeader>
          <CardContent>
            {rows.length === 0 ? <p className="py-6 text-center text-sm text-muted-foreground">No assets match.</p> : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Name</TableHead><TableHead>Environment</TableHead><TableHead>Owner</TableHead><TableHead>Last activity</TableHead>
                    <TableHead className="w-44">Days inactive</TableHead><TableHead>Stage</TableHead><TableHead>Next step</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {rows.map((a) => {
                    const k = stageOf(a.rev_stage)
                    const days = a.rev_daysinactive ?? 0
                    return (
                      <TableRow key={a.rev_governedassetid} tabIndex={0} className="cursor-pointer" onClick={() => onSelect(a)} onKeyDown={(e) => e.key === 'Enter' && onSelect(a)}>
                        <TableCell className="font-medium">
                          <span className="flex items-center gap-2">
                            {typeOf(a) === 'Flow' ? <Workflow className="size-4 shrink-0 text-muted-foreground" aria-label="Flow" /> : <AppWindow className="size-4 shrink-0 text-muted-foreground" aria-label="App" />}
                            {a.rev_name}
                          </span>
                        </TableCell>
                        <TableCell>{a.rev_environmentname}</TableCell>
                        <TableCell>{a.rev_ownername || a.rev_ownerupn || '—'}</TableCell>
                        <TableCell>{fmtDate(a.rev_lastactivityon)}</TableCell>
                        <TableCell>
                          <span className="flex items-center gap-2">
                            <span className="w-8 text-right tabular-nums">{Math.floor(days)}</span>
                            <span className="h-1.5 flex-1 overflow-hidden rounded-full bg-muted">
                              <motion.span className="block h-full rounded-full" style={{ background: STAGE_COLOR[k ?? 'New'] }}
                                initial={{ width: 0 }} animate={{ width: `${Math.min(100, (days / deleteAt) * 100)}%` }} transition={{ duration: 0.9, ease: 'easeOut' }} />
                            </span>
                          </span>
                        </TableCell>
                        <TableCell><StagePill stage={k} /></TableCell>
                        <TableCell className="text-muted-foreground">{a.rev_nextstage ? `${spaced(a.rev_nextstage).toLowerCase()} on ${fmtDate(a.rev_nextstageon)}` : '—'}</TableCell>
                      </TableRow>
                    )
                  })}
                </TableBody>
              </Table>
            )}
            {assets.some((a) => typeOf(a) === 'App' && a.rev_usagesignal !== 'audit-log') && (
              <p className="mt-3 text-xs text-muted-foreground">App launches were not read on the latest scan, so apps are judged on last modification only.</p>
            )}
          </CardContent>
        </Card>
      </motion.section>
    </div>
  )
}

export function UpNextList({ items, onSelect }: { items: InactiveSummary['upNext']; onSelect: (a: Asset) => void }) {
  if (items.length === 0) return <p className="text-sm text-muted-foreground">Nothing scheduled.</p>
  return (
    <ul className="grid gap-1">
      {items.map(({ a, days }) => (
        <li key={a.rev_governedassetid}>
          <button type="button" onClick={() => onSelect(a)} className="flex w-full items-center gap-3 rounded-lg px-2 py-1.5 text-left text-sm hover:bg-muted/50 focus-visible:outline-2">
            <span className="grid w-12 shrink-0 text-center leading-tight"><span className="text-lg font-semibold tabular-nums">{days}</span><span className="text-[10px] text-muted-foreground">{days === 1 ? 'day' : 'days'}</span></span>
            <span className="min-w-0 flex-1"><span className="block truncate font-medium">{a.rev_name}</span><span className="flex items-center gap-1 text-xs text-muted-foreground"><ArrowRight className="size-3" />{spaced(a.rev_nextstage).toLowerCase()} on {fmtDate(a.rev_nextstageon)}</span></span>
          </button>
        </li>
      ))}
    </ul>
  )
}
