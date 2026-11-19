import { useEffect, useMemo, useState } from 'react'
import { Moon, Radar, RefreshCw, Sun } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Skeleton } from '@/components/ui/skeleton'
import { TooltipProvider } from '@/components/ui/tooltip'
import { AssetSheet } from '@/components/asset-sheet'
import { STAGE_COLOR } from '@/components/parts'
import { cn } from '@/lib/utils'
import { fmtDateTime, loadSnapshot } from './data'
import type { Asset, Snapshot } from './data'
import { summarize } from './inactive'
import { InactiveAssetsReport } from './reports/inactive-assets'
import { Overview } from './reports/overview'
import { OVERVIEW, REPORTS, glass } from './shell'
import type { ReportDef, ViewId } from './shell'

const APP_NAME = 'Power Platform Governance'

function NavItem({ r, active, onOpen }: { r: ReportDef; active: boolean; onOpen: (v: ViewId) => void }) {
  const Icon = r.icon
  const id = r.id
  if (!id) {
    return (
      <span className="flex shrink-0 items-center gap-2.5 rounded-lg px-3 py-2 text-sm text-muted-foreground/70" aria-disabled>
        <Icon className="size-4 shrink-0" /><span className="whitespace-nowrap">{r.label}</span>
        <span className="ml-auto rounded-full border px-1.5 text-[10px]">Soon</span>
      </span>
    )
  }
  return (
    <button type="button" onClick={() => onOpen(id)} aria-current={active ? 'page' : undefined}
      className={cn('flex shrink-0 items-center gap-2.5 rounded-lg px-3 py-2 text-left text-sm font-medium outline-offset-2 transition-colors focus-visible:outline-2',
        active ? 'bg-primary/10 text-foreground shadow-[inset_2px_0_0_var(--glow)]' : 'text-muted-foreground hover:bg-muted/50 hover:text-foreground')}>
      <Icon className="size-4 shrink-0" /><span className="whitespace-nowrap">{r.label}</span>
    </button>
  )
}

export default function App() {
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [view, setView] = useState<ViewId>('overview')
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

  const summary = useMemo(() => summarize(snapshot), [snapshot])
  const latest = summary.latest
  const current = [OVERVIEW, ...REPORTS].find((r) => r.id === view) ?? OVERVIEW

  return (
    <TooltipProvider delayDuration={100}>
      <div className="aurora" aria-hidden><i /><i /><i /></div>
      <div className="flex min-h-svh flex-col lg:flex-row">
        <aside className="glass z-10 flex shrink-0 flex-col gap-4 border-b border-white/10 bg-card p-3 lg:sticky lg:top-0 lg:h-svh lg:w-64 lg:border-r lg:border-b-0 lg:p-4">
          <div className="flex items-center gap-3 px-1">
            <div className="grid size-9 shrink-0 place-content-center rounded-xl bg-gradient-to-br from-violet-500 to-cyan-400 text-white shadow-lg shadow-violet-500/30">
              <Radar className="size-5" />
            </div>
            <div className="leading-tight">
              <div className="text-gradient font-semibold tracking-tight">{APP_NAME}</div>
              <div className="text-xs text-muted-foreground">Dashboard</div>
            </div>
          </div>
          <nav aria-label="Reports" className="flex gap-1 overflow-x-auto [scrollbar-width:none] lg:flex-col lg:overflow-visible">
            <NavItem r={OVERVIEW} active={view === 'overview'} onOpen={setView} />
            <div className="hidden px-3 pt-4 pb-1 text-[10px] font-semibold tracking-widest text-muted-foreground uppercase lg:block">Reports</div>
            {REPORTS.map((r) => <NavItem key={r.label} r={r} active={view === r.id} onOpen={setView} />)}
          </nav>
          <div className="mt-auto hidden px-3 text-xs text-muted-foreground lg:block">
            {latest ? <>Last scan<br /><span className="text-foreground">{fmtDateTime(latest.rev_scanon)}</span></> : snapshot && 'No scans yet'}
          </div>
        </aside>

        <main className="grid min-w-0 flex-1 content-start gap-5 px-4 py-5 sm:px-6">
          <header className="flex flex-wrap items-center justify-between gap-3">
            <div className="min-w-0">
              <h1 className="flex flex-wrap items-center gap-2 text-2xl font-semibold tracking-tight">
                {current.label}
                {view === 'inactive-assets' && (
                  <Badge variant="outline" className="gap-1.5">
                    <span className="relative flex size-2"><span className="absolute inline-flex size-full animate-ping rounded-full bg-emerald-400 opacity-60" /><span className="relative inline-flex size-2 rounded-full bg-emerald-400" /></span>
                    Report only
                  </Badge>
                )}
              </h1>
              <p className="text-sm text-muted-foreground">{current.blurb}</p>
            </div>
            <div className="flex items-center gap-2">
              <Button variant="outline" size="icon" onClick={() => setDark((d) => !d)} aria-label={dark ? 'Switch to light mode' : 'Switch to dark mode'}>
                {dark ? <Sun /> : <Moon />}
              </Button>
              <Button variant="outline" onClick={refresh} disabled={loading}>
                <RefreshCw className={cn(loading && 'animate-spin')} /> Refresh
              </Button>
            </div>
          </header>

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
              <div className="grid grid-cols-2 gap-3 xl:grid-cols-4">{[0, 1, 2, 3].map((i) => <Skeleton key={i} className="h-24 rounded-xl" />)}</div>
              <Skeleton className="h-48 rounded-xl" />
              <Skeleton className="h-72 rounded-xl" />
            </div>
          )}

          {snapshot && (
            <>
              {latest?.rev_istest && (
                <p className="rounded-lg border px-3 py-2 text-sm" style={{ color: STAGE_COLOR.QuarantineWarning, borderColor: STAGE_COLOR.QuarantineWarning }}>
                  The latest inactive asset scan was a test run with overridden periods or date, so its stages are simulated.
                </p>
              )}
              {view === 'overview'
                ? <Overview key="overview" s={summary} events={snapshot.events} onOpen={setView} onSelect={setSelected} />
                : <InactiveAssetsReport key="inactive" s={summary} scans={snapshot.scans} onSelect={setSelected} />}
            </>
          )}
        </main>
      </div>
      <AssetSheet asset={selected} events={snapshot?.events ?? []} onClose={() => setSelected(null)} />
    </TooltipProvider>
  )
}
