import { motion } from 'motion/react'
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { Separator } from '@/components/ui/separator'
import { STAGE_COLOR, StagePill } from '@/components/parts'
import { fmtDate, fmtDateTime, stageLabel, stageOf, typeOf } from '@/data'
import type { Asset, AssetEvent, StageKey } from '@/data'

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-baseline justify-between gap-4 text-sm">
      <span className="shrink-0 text-muted-foreground">{label}</span>
      <span className="min-w-0 text-right break-words">{children}</span>
    </div>
  )
}

export function AssetSheet({ asset, events, onClose }: { asset: Asset | null; events: AssetEvent[]; onClose: () => void }) {
  const mine = asset ? events.filter((e) => e._rev_asset_value === asset.rev_governedassetid) : []
  const stage = asset ? stageOf(asset.rev_stage) : null
  const now = Date.now()
  const steps: { label: string; when?: string; key: StageKey }[] = asset
    ? [
        { label: 'Last activity', when: asset.rev_lastactivityon, key: 'Active' },
        { label: 'Quarantine warning', when: asset.rev_quarantinewarningon, key: 'QuarantineWarning' },
        { label: 'Quarantine', when: asset.rev_quarantineon, key: 'Quarantine' },
        { label: 'Delete warning', when: asset.rev_deletewarningon, key: 'DeleteWarning' },
        { label: 'Delete', when: asset.rev_deleteon, key: 'Delete' },
      ]
    : []

  return (
    <Sheet open={!!asset} onOpenChange={(open) => !open && onClose()}>
      <SheetContent className="w-full gap-0 overflow-y-auto sm:max-w-md">
        {asset && (
          <>
            <SheetHeader>
              <SheetTitle className="text-xl break-words">{asset.rev_name}</SheetTitle>
              <SheetDescription>
                {typeOf(asset)}{asset.rev_subtype ? ` · ${asset.rev_subtype}` : ''} · {asset.rev_environmentname}
              </SheetDescription>
              <div className="pt-1"><StagePill stage={stage} /></div>
            </SheetHeader>

            <div className="grid gap-5 px-4 pb-8">
              <div className="grid gap-2">
                <Field label="Owner">{asset.rev_ownername || asset.rev_ownerupn || asset.rev_ownerobjectid || '—'}</Field>
                <Field label="Days inactive">{asset.rev_daysinactive ?? '—'}</Field>
                <Field label="Last activity from">{asset.rev_lastactivitysource ?? '—'}</Field>
                <Field label="Last modified">{fmtDate(asset.rev_lastmodifiedon)}</Field>
                {typeOf(asset) === 'Flow'
                  ? <Field label="Last run">{fmtDate(asset.rev_lastrunon)}</Field>
                  : <Field label="Last launch">{asset.rev_lastlaunchon ? fmtDate(asset.rev_lastlaunchon) : asset.rev_usagesignal === 'audit-log' ? 'None in the audit log' : 'Not read'}</Field>}
                <Field label="Usage signal">{asset.rev_usagesignal ?? '—'}</Field>
                {asset.rev_platformstate && <Field label="Platform state">{asset.rev_platformstate}</Field>}
                {asset.rev_exemptreason && <Field label="Exempt reason">{asset.rev_exemptreason}</Field>}
                <Field label="Asset ID"><span className="font-mono text-xs break-all">{asset.rev_assetid}</span></Field>
              </div>

              <Separator />

              <div>
                <h3 className="mb-3 text-xs font-semibold tracking-widest text-muted-foreground uppercase">Timeline</h3>
                <ol className="relative grid gap-4 pl-6">
                  <span className="absolute top-1.5 bottom-1.5 left-[5px] w-px bg-border" />
                  {steps.map((s, i) => {
                    const past = !!s.when && new Date(s.when).getTime() <= now
                    const color = STAGE_COLOR[s.key]
                    return (
                      <motion.li key={s.label} className="relative flex items-center justify-between gap-4 text-sm"
                        initial={{ opacity: 0, x: 12 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: 0.08 * i }}>
                        <span className="absolute -left-6 size-[11px] rounded-full border-2"
                          style={{ borderColor: color, background: past ? color : 'var(--background)', boxShadow: past ? `0 0 10px ${color}` : undefined }} />
                        <span className={past ? '' : 'text-muted-foreground'}>{s.label}</span>
                        <span className="text-muted-foreground tabular-nums">{fmtDate(s.when)}</span>
                      </motion.li>
                    )
                  })}
                </ol>
              </div>

              <Separator />

              <div>
                <h3 className="mb-3 text-xs font-semibold tracking-widest text-muted-foreground uppercase">Stage changes</h3>
                {mine.length === 0 ? <p className="text-sm text-muted-foreground">None recorded.</p> : (
                  <ul className="grid gap-2 text-sm">
                    {mine.map((e) => (
                      <li key={e.rev_asseteventid} className="flex justify-between gap-4">
                        <span>{stageLabel(stageOf(e.rev_fromstage))} → {stageLabel(stageOf(e.rev_tostage))}</span>
                        <span className="whitespace-nowrap text-muted-foreground">{fmtDateTime(e.rev_eventon)}</span>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            </div>
          </>
        )}
      </SheetContent>
    </Sheet>
  )
}
