# Asset Governance dashboard

Power Apps code app (React + Vite) over the inactive asset policy log in Dataverse: `rev_governedasset`,
`rev_assetscan` and `rev_assetevent`, written by `scripts/inactive-assets/Invoke-InactiveAssetScan.ps1`.

```powershell
npm install
npx pa auth login --account <you>@lowcoderev.ai
npm run build
npx pa app push
```

Environment and app id are in `power.config.json`. Files under `src/generated/` and `.power/` are produced by
`pa app add data-source`; do not edit them by hand.
