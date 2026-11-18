import { useEffect, useMemo, useState } from 'react'
import './App.css'
import { STAGES, fmtDate, fmtDateTime, loadSnapshot, stageLabel, stageOf, typeOf } from './data'
import type { Asset, Scan, Snapshot, StageKey } from './data'

type StageFilter = StageKey | 'Flagged' | 'All'

const scanCount = (s: Scan, key: StageKey): number =>
  ({
    Active: s.rev_activecount,
    QuarantineWarning: s.rev_quarantinewarningcount,
    Quarantine: s.rev_quarantinecount,
    DeleteWarning: s.rev_deletewarningcount,
    Delete: s.rev_deletecount,
    Exempt: s.rev_exemptcount,
  })[key] ?? 0

function StagePill({ stage }: { stage: StageKey | null }) {
  return <span className={`pill s-${stage ?? 'New'}`}>{stageLabel(stage)}</span>
}

function Trend({ scans }: { scans: Scan[] }) {
  // Oldest to newest; flagged = everything that is not active or exempt.
  const points = [...scans].reverse().map((s) => ({
    when: s.rev_scanon,
    flagged: (s.rev_totalcount ?? 0) - (s.rev_activecount ?? 0) - (s.rev_exemptcount ?? 0),
    total: s.rev_totalcount ?? 0,
  }))
  if (points.length < 2) return <p className="muted">The trend appears after the second scan.</p>
  const w = 600, h = 120, pad = 6
  const max = Math.max(1, ...points.map((p) => p.total))
  const x = (i: number) => pad + (i * (w - 2 * pad)) / (points.length - 1)
  const y = (v: number) => h - pad - (v * (h - 2 * pad)) / max
  const line = (get: (p: (typeof points)[number]) => number) => points.map((p, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)},${y(get(p)).toFixed(1)}`).join(' ')
  const last = points[points.length - 1]
  return (
    <div>
      <svg viewBox={`0 0 ${w} ${h}`} className="trend" role="img" aria-label={`Flagged assets over ${points.length} scans; latest ${last.flagged} of ${last.total}`}>
        <path d={line((p) => p.total)} className="trend-total" />
        <path d={line((p) => p.flagged)} className="trend-flagged" />
      </svg>
      <div className="legend">
        <span><i className="swatch total" /> Tracked ({last.total})</span>
        <span><i className="swatch flagged" /> Flagged ({last.flagged})</span>
        <span className="muted">{fmtDate(points[0].when)} to {fmtDate(last.when)}</span>
      </div>
    </div>
  )
}

function Detail({ asset, snapshot, onClose }: { asset: Asset; snapshot: Snapshot; onClose: () => void }) {
  const events = snapshot.events.filter((e) => e._rev_asset_value === asset.rev_governedassetid)
  const stage = stageOf(asset.rev_stage)
  const steps: [string, string | undefined][] = [
    ['Last activity', asset.rev_lastactivityon],
    ['Quarantine warning', asset.rev_quarantinewarningon],
    ['Quarantine', asset.rev_quarantineon],
    ['Delete warning', asset.rev_deletewarningon],
    ['Delete', asset.rev_deleteon],
  ]
  const now = Date.now()
  return (
    <aside className="drawer" aria-label="Asset detail">
      <header>
        <div>
          <h2>{asset.rev_name}</h2>
          <p className="muted">{typeOf(asset)}{asset.rev_subtype ? ` · ${asset.rev_subtype}` : ''} · {asset.rev_environmentname}</p>
        </div>
        <button className="ghost" onClick={onClose} aria-label="Close">✕</button>
      </header>
      <StagePill stage={stage} />
      <dl>
        <dt>Owner</dt><dd>{asset.rev_ownername || asset.rev_ownerupn || asset.rev_ownerobjectid || '—'}</dd>
        <dt>Days inactive</dt><dd>{asset.rev_daysinactive ?? '—'}</dd>
        <dt>Last activity from</dt><dd>{asset.rev_lastactivitysource ?? '—'}</dd>
        <dt>Last modified</dt><dd>{fmtDate(asset.rev_lastmodifiedon)}</dd>
        <dt>Last run</dt><dd>{fmtDate(asset.rev_lastrunon)}</dd>
        <dt>Usage signal</dt><dd>{asset.rev_usagesignal ?? '—'}</dd>
        {asset.rev_platformstate && (<><dt>Platform state</dt><dd>{asset.rev_platformstate}</dd></>)}
        {asset.rev_exemptreason && (<><dt>Exempt reason</dt><dd>{asset.rev_exemptreason}</dd></>)}
        <dt>Asset ID</dt><dd className="mono">{asset.rev_assetid}</dd>
      </dl>
      <h3>Timeline</h3>
      <ol className="timeline">
        {steps.map(([label, when]) => (
          <li key={label} className={when && new Date(when).getTime() <= now ? 'past' : ''}>
            <span>{label}</span><span>{fmtDate(when)}</span>
          </li>
        ))}
      </ol>
      <h3>Stage changes</h3>
      {events.length === 0 ? <p className="muted">None recorded.</p> : (
        <ul className="events">
          {events.map((e) => (
            <li key={e.rev_asseteventid}>
              <span>{stageLabel(stageOf(e.rev_fromstage))} → {stageLabel(stageOf(e.rev_tostage))}</span>
              <span className="muted">{fmtDateTime(e.rev_eventon)}</span>
            </li>
          ))}
        </ul>
      )}
    </aside>
  )
}

export default function App() {
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [stage, setStage] = useState<StageFilter>('Flagged')
  const [type, setType] = useState<'All' | 'App' | 'Flow'>('All')
  const [query, setQuery] = useState('')
  const [selected, setSelected] = useState<Asset | null>(null)

  const refresh = () => {
    setLoading(true)
    loadSnapshot()
      .then((s) => { setSnapshot(s); setError(null) })
      .catch((e: unknown) => setError(e instanceof Error ? e.message : String(e)))
      .finally(() => setLoading(false))
  }
  useEffect(refresh, [])

  const counts = useMemo(() => {
    const c = Object.fromEntries(STAGES.map((s) => [s.key, 0])) as Record<StageKey, number>
    for (const a of snapshot?.assets ?? []) { const k = stageOf(a.rev_stage); if (k) c[k]++ }
    return c
  }, [snapshot])

  const rows = useMemo(() => {
    const q = query.trim().toLowerCase()
    return (snapshot?.assets ?? []).filter((a) => {
      const k = stageOf(a.rev_stage)
      if (stage === 'Flagged' ? k === 'Active' || k === 'Exempt' : stage !== 'All' && k !== stage) return false
      if (type !== 'All' && typeOf(a) !== type) return false
      if (q && ![a.rev_name, a.rev_ownername, a.rev_ownerupn, a.rev_environmentname].some((v) => v?.toLowerCase().includes(q))) return false
      return true
    })
  }, [snapshot, stage, type, query])

  if (error) return <main className="center"><p className="error">Could not load data. {error}</p><button onClick={refresh}>Retry</button></main>
  if (!snapshot) return <main className="center"><p className="muted">Loading…</p></main>

  const latest = snapshot.scans[0]
  const realScans = snapshot.scans.filter((s) => !s.rev_istest)
  const total = snapshot.assets.length
  const flagged = total - counts.Active - counts.Exempt

  return (
    <main>
      <header className="top">
        <div>
          <h1>Asset Governance</h1>
          <p className="muted">
            Inactive asset policy · <span className="badge">Report only</span>
            {latest ? <> · last scan {fmtDateTime(latest.rev_scanon)}</> : ' · no scans yet'}
          </p>
        </div>
        <button onClick={refresh} disabled={loading}>{loading ? 'Refreshing…' : 'Refresh'}</button>
      </header>

      {latest?.rev_istest && (
        <p className="notice">The latest scan was a test run with overridden periods or date, so the stages below are simulated.</p>
      )}

      <section className="tiles" aria-label="Assets by stage">
        <button className={`tile ${stage === 'Flagged' ? 'on' : ''}`} onClick={() => setStage('Flagged')}>
          <span className="num">{flagged}</span><span>Flagged</span><span className="muted">of {total} tracked</span>
        </button>
        {STAGES.map((s) => (
          <button key={s.key} className={`tile s-${s.key} ${stage === s.key ? 'on' : ''}`} onClick={() => setStage(s.key)}>
            <span className="num">{counts[s.key]}</span><span>{s.label}</span>
            <span className="muted">{latest ? `${scanCount(latest, s.key)} at last scan` : ''}</span>
          </button>
        ))}
      </section>

      <section className="grid">
        <div className="card">
          <h2>Trend</h2>
          <Trend scans={realScans} />
        </div>
        <div className="card">
          <h2>Policy periods</h2>
          {latest ? (
            <dl className="periods">
              <dt>Inactive after</dt><dd>{latest.rev_inactivedays} days</dd>
              <dt>Quarantine warning</dt><dd>{latest.rev_quarantinewarningdays} days</dd>
              <dt>Quarantined for</dt><dd>{latest.rev_quarantineddays} days</dd>
              <dt>Delete warning</dt><dd>{latest.rev_deletewarningdays} days</dd>
            </dl>
          ) : <p className="muted">No scan recorded.</p>}
        </div>
        <div className="card">
          <h2>Recent stage changes</h2>
          {snapshot.events.length === 0 ? <p className="muted">None recorded.</p> : (
            <ul className="events">
              {snapshot.events.slice(0, 6).map((e) => (
                <li key={e.rev_asseteventid}><span>{e.rev_name}</span><span className="muted">{fmtDateTime(e.rev_eventon)}</span></li>
              ))}
            </ul>
          )}
        </div>
      </section>

      <section className="card">
        <div className="toolbar">
          <h2>Assets <span className="muted">({rows.length})</span></h2>
          <input type="search" placeholder="Search name, owner, environment" value={query} onChange={(e) => setQuery(e.target.value)} aria-label="Search assets" />
          <select value={type} onChange={(e) => setType(e.target.value as typeof type)} aria-label="Asset type">
            <option value="All">Apps and flows</option><option value="App">Apps</option><option value="Flow">Flows</option>
          </select>
          <select value={stage} onChange={(e) => setStage(e.target.value as StageFilter)} aria-label="Stage">
            <option value="Flagged">Flagged</option><option value="All">All stages</option>
            {STAGES.map((s) => <option key={s.key} value={s.key}>{s.label}</option>)}
          </select>
        </div>
        {rows.length === 0 ? <p className="muted empty">No assets match.</p> : (
          <div className="scroll">
            <table>
              <thead><tr><th>Name</th><th>Type</th><th>Environment</th><th>Owner</th><th>Last activity</th><th className="r">Days inactive</th><th>Stage</th><th>Next step</th></tr></thead>
              <tbody>
                {rows.map((a) => (
                  <tr key={a.rev_governedassetid} onClick={() => setSelected(a)} tabIndex={0} onKeyDown={(e) => e.key === 'Enter' && setSelected(a)}>
                    <td className="name">{a.rev_name}</td>
                    <td>{typeOf(a)}</td>
                    <td>{a.rev_environmentname}</td>
                    <td>{a.rev_ownername || a.rev_ownerupn || '—'}</td>
                    <td>{fmtDate(a.rev_lastactivityon)}</td>
                    <td className="r">{a.rev_daysinactive != null ? Math.floor(a.rev_daysinactive) : '—'}</td>
                    <td><StagePill stage={stageOf(a.rev_stage)} /></td>
                    <td>{a.rev_nextstage ? `${a.rev_nextstage.replace(/([a-z])([A-Z])/g, '$1 $2').toLowerCase()} on ${fmtDate(a.rev_nextstageon)}` : '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <p className="muted foot">Apps are judged on last modification only; app launches are not yet part of the signal.</p>
      </section>

      {selected && <><div className="scrim" onClick={() => setSelected(null)} /><Detail asset={selected} snapshot={snapshot} onClose={() => setSelected(null)} /></>}
    </main>
  )
}
