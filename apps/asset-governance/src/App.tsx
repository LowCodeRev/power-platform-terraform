import { useEffect, useMemo, useState } from 'react'
import { motion } from 'motion/react'
import { AppWindow, ArrowRight, CalendarClock, Moon, Radar, RefreshCw, Search, Sun, Workflow } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Skeleton } from '@/components/ui/skeleton'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { ToggleGroup, ToggleGroupItem } from '@/components/ui/toggle-group'
import { TooltipProvider } from '@/components/ui/tooltip'
import { AssetSheet } from '@/components/asset-sheet'
import { Conveyor, CountUp, HealthGauge, STAGE_COLOR, StagePill, TrendChart } from '@/components/parts'
import type { Periods } from '@/components/parts'
import { cn } from '@/lib/utils'
import { STAGES, fmtDate, fmtDateTime, loadSnapshot, stageOf, typeOf } from './data'
import type { Asset, Snapshot, StageKey } from './data'

type StageFilter = StageKey | 'Flagged' | 'All'
const glass = 'glass border-white/10 bg-card'
const rise = (i: number) => ({ initial: { opacity: 0, y: 18 }, animate: { opacity: 1, y: 0 }, transition: { duration: 0.5, delay: 0.06 * i, ease: [0.16, 1, 0.3, 1] as const } })

function daysUntil(iso?: string): number | null {
  if (!iso) return null
  const t = new Date(iso).getTime()
  return Number.isNaN(t) ? null : Math.ceil((t - Date.now()) / 86400000)
}
const spaced = (s?: string) => (s ?? '').replace(/([a-z])([A-Z])/g, '$1 $2')

export default function App() {
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [stage, setStage] = useState<StageFilter>('Flagged')
  const [type, setType] = useState<'All' | 'App' | 'Flow'>('All')
  const [query, setQuery] = useState('')
  const [selected, setSelected] = useState<Asset | null>(null)
  const [dark, setDark] = useState(true)

  useEffect(() => { document.documentElement.classList.toggle('dark', dark) }, [dark])

  const refresh = () => {
    setLoading(true)
    loadSnapshot()
      .then((s) => { setSnapshot(s); setError(null) })
      .catch((e: unknown) => setError(e instanceof Error ? e.message : String(e)))
      .finally(() => setLoading(false))
  }
  useEffect(refresh, [])

  const assets = useMemo(() => snapshot?.assets ?? [], [snapshot])
  const counts = useMemo(() => {
    const c = Object.fromEntries(STAGES.map((s) => [s.key, 0])) as Record<StageKey, number>
    for (const a of assets) { const k = stageOf(a.rev_stage); if (k) c[k]++ }
    return c
  }, [assets])

  const rows = useMemo(() => {
    const q = query.trim().toLowerCase()
    return assets.filter((a) => {
      const k = stageOf(a.rev_stage)
      if (stage === 'Flagged' ? k === 'Active' || k === 'Exempt' : stage !== 'All' && k !== stage) return false
      if (type !== 'All' && typeOf(a) !== type) return false
      return !q || [a.rev_name, a.rev_ownername, a.rev_ownerupn, a.rev_environmentname].some((v) => v?.toLowerCase().includes(q))
    })
  }, [assets, stage, type, query])

  const upNext = useMemo(
    () => assets
      .map((a) => ({ a, days: daysUntil(a.rev_nextstageon) }))
      .filter((x): x is { a: Asset; days: number } => x.days !== null && x.days >= 0 && !!x.a.rev_nextstage && stageOf(x.a.rev_stage) !== 'Exempt')
      .sort((x, y) => x.days - y.days)
      .slice(0, 6),
    [assets],
  )

  const latest = snapshot?.scans[0]
  const periods: Periods = {
    inactive: latest?.rev_inactivedays ?? 90,
    warnQ: latest?.rev_quarantinewarningdays ?? 14,
    quarantined: latest?.rev_quarantineddays ?? 90,
    warnD: latest?.rev_deletewarningdays ?? 14,
  }
  const total = assets.length
  const healthy = counts.Active + counts.Exempt
  const flagged = total - healthy

  return (
    <TooltipProvider delayDuration={100}>
      <div className="aurora" aria-hidden><i /><i /><i /></div>
      <main className="mx-auto grid max-w-7xl gap-5 px-4 py-6 sm:px-6">
        <motion.header {...rise(0)} className="flex flex-wrap items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <div className="grid size-11 place-content-center rounded-2xl bg-gradient-to-br from-violet-500 to-cyan-400 text-white shadow-lg shadow-violet-500/30">
              <Radar className="size-6" />
            </div>
            <div>
              <h1 className="text-gradient text-2xl font-semibold tracking-tight sm:text-3xl">Asset Governance</h1>
              <p className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
                Inactive asset policy
                <Badge variant="outline" className="gap-1.5">
                  <span className="relative flex size-2"><span className="absolute inline-flex size-full animate-ping rounded-full bg-emerald-400 opacity-60" /><span className="relative inline-flex size-2 rounded-full bg-emerald-400" /></span>
                  Report only
                </Badge>
                {latest ? <span>Last scan {fmtDateTime(latest.rev_scanon)}</span> : snapshot && <span>No scans yet</span>}
              </p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Button variant="outline" size="icon" onClick={() => setDark((d) => !d)} aria-label={dark ? 'Switch to light mode' : 'Switch to dark mode'}>
              {dark ? <Sun /> : <Moon />}
            </Button>
            <Button variant="outline" onClick={refresh} disabled={loading}>
              <RefreshCw className={cn(loading && 'animate-spin')} /> Refresh
            </Button>
          </div>
        </motion.header>

        {error && (
          <Card className={cn(glass, 'border-destructive/50')}>
            <CardContent className="flex flex-wrap items-center justify-between gap-3">
              <p className="text-sm text-destructive">Could not load data. {error}</p>
              <Button variant="outline" onClick={refresh}>Retry</Button>
            </CardContent>
          </Card>
        )}

        {!snapshot && !error && (
          <div className="grid gap-5">
            <Skeleton className="h-64 rounded-xl" />
            <div className="grid grid-cols-2 gap-3 md:grid-cols-6">{STAGES.map((s) => <Skeleton key={s.key} className="h-24 rounded-xl" />)}</div>
            <Skeleton className="h-80 rounded-xl" />
          </div>
        )}

        {snapshot && (
          <>
            {latest?.rev_istest && (
              <p className="rounded-lg border px-3 py-2 text-sm" style={{ color: STAGE_COLOR.QuarantineWarning, borderColor: STAGE_COLOR.QuarantineWarning }}>
                The latest scan was a test run with overridden periods or date, so the stages below are simulated.
              </p>
            )}

            <motion.section {...rise(1)} className="grid gap-5 lg:grid-cols-[18rem_1fr]">
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
                    : <Conveyor assets={assets} periods={periods} onSelect={setSelected} />}
                </CardContent>
              </Card>
            </motion.section>

            <section className="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-6" aria-label="Assets by stage">
              {STAGES.map((s, i) => {
                const on = stage === s.key
                const color = STAGE_COLOR[s.key]
                return (
                  <motion.button key={s.key} type="button" {...rise(2 + i * 0.5)} whileHover={{ y: -4 }} whileTap={{ scale: 0.97 }}
                    onClick={() => setStage(on ? 'Flagged' : s.key)} aria-pressed={on}
                    className={cn('glass relative overflow-hidden rounded-xl border bg-card p-4 text-left outline-offset-2 focus-visible:outline-2', on ? 'border-transparent' : 'border-white/10')}
                    style={on ? { boxShadow: `0 0 0 1.5px ${color}, 0 12px 40px -12px ${color}` } : undefined}>
                    <span className="absolute -top-8 -right-8 size-24 rounded-full opacity-25 blur-2xl" style={{ background: color }} />
                    <div className="text-3xl font-semibold tracking-tight" style={{ color }}><CountUp value={counts[s.key]} /></div>
                    <div className="mt-1 text-sm font-medium">{s.label}</div>
                    <div className="text-xs text-muted-foreground">{s.verb}</div>
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
                <CardContent><TrendChart scans={snapshot.scans.filter((s) => !s.rev_istest)} /></CardContent>
              </Card>

              <Card className={glass}>
                <CardHeader>
                  <CardTitle className="flex items-center gap-2"><CalendarClock className="size-4" /> Up next</CardTitle>
                  <CardDescription>The next stage changes the policy would make</CardDescription>
                </CardHeader>
                <CardContent>
                  {upNext.length === 0 ? <p className="text-sm text-muted-foreground">Nothing scheduled.</p> : (
                    <ul className="grid gap-1">
                      {upNext.map(({ a, days }) => (
                        <li key={a.rev_governedassetid}>
                          <button type="button" onClick={() => setSelected(a)} className="flex w-full items-center gap-3 rounded-lg px-2 py-1.5 text-left text-sm hover:bg-muted/50 focus-visible:outline-2">
                            <span className="grid w-12 shrink-0 text-center leading-tight"><span className="text-lg font-semibold tabular-nums">{days}</span><span className="text-[10px] text-muted-foreground">{days === 1 ? 'day' : 'days'}</span></span>
                            <span className="min-w-0 flex-1"><span className="block truncate font-medium">{a.rev_name}</span><span className="flex items-center gap-1 text-xs text-muted-foreground"><ArrowRight className="size-3" />{spaced(a.rev_nextstage).toLowerCase()} on {fmtDate(a.rev_nextstageon)}</span></span>
                          </button>
                        </li>
                      ))}
                    </ul>
                  )}
                </CardContent>
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
                          const deleteAt = periods.inactive + periods.warnQ + periods.quarantined + periods.warnD
                          return (
                            <TableRow key={a.rev_governedassetid} tabIndex={0} className="cursor-pointer" onClick={() => setSelected(a)} onKeyDown={(e) => e.key === 'Enter' && setSelected(a)}>
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
                  <p className="mt-3 text-xs text-muted-foreground">Apps are judged on last modification only; app launches are not yet part of the signal.</p>
                </CardContent>
              </Card>
            </motion.section>
          </>
        )}
      </main>
      <AssetSheet asset={selected} events={snapshot?.events ?? []} onClose={() => setSelected(null)} />
    </TooltipProvider>
  )
}
