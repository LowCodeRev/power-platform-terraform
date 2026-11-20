# Handoff: inactive asset policy and governance dashboard

Written 2026-11-18, updated 2026-11-20. Branch `feature/inactive-assets` (draft PR #7, base
`feature/pde-requests`). All work is committed and pushed.

**Start here:** the latest work is "Agent quarantine" below; what to do next is under "Next steps, in order".

## Ground rules from the user

- Work only in the **lowcoderev.ai** tenant (`19a0c33f-bf94-4ef0-b894-539351f7aa80`) with LowCodeRev accounts:
  az CLI and pa CLI as `Andy@lowcoderev.ai`, gh CLI as `LowCodeRev`. Never TrueTandem. The pa CLI has an
  inactive cached MngEnvMCAP account; do not use it.
- Commit and push only when asked. A commit and push attempted without being asked was blocked this session.
- Conditional Access blocks device-code sign-in; use browser login (`pa auth login --account ... -e <env>`).
- The policy is **report only** for apps and flows: nothing may quarantine, delete or notify them yet.
  Exception, asked for on 2026-11-20: **agents are quarantined** by the scan (see "Agent quarantine" below).

## What exists

| Piece | Where | State |
|---|---|---|
| Policy | `policies/inactive-assets.json` | 90 / 14 / 90 / 14 days, `appLaunchSignal`, agents, `enforcement.quarantineAgents: true` |
| Scan | `scripts/inactive-assets/Invoke-InactiveAssetScan.ps1` | Apps + flows + agents, launch signal, agent quarantine behind `-Enforce` |
| Logic + tests | `InactiveAssets.psm1`, `tests/` | 31 Pester tests pass locally |
| Dataverse schema | `Deploy-InactiveAssetSchema.ps1` | Deployed to https://lowcoderev.crm.dynamics.com, incl. the "Agent" asset type |
| Service principal access | `Grant-InactiveAssetAccess.ps1` | Run and verified in LowCodeRev **before** the agent privileges were added; not rerun since |
| Workflow | `.github/workflows/inactive-assets.yml` | Daily 11:30 UTC, enforces agent quarantine on schedule and on manual "enforce"; never on PRs |
| Dashboard | `apps/asset-governance` | "Power Platform Governance Dashboard"; the pushed version predates agents |

Dashboard URL:
https://apps.powerapps.com/play/e/50b383ee-e3db-ed10-983d-376a576cd404/app/83a74569-574c-4135-8056-52abf7b1d1f6?tenantId=19a0c33f-bf94-4ef0-b894-539351f7aa80

Service principal: `sp-terraform-powerplatform`, client id `261c6986-a969-482e-bb81-9ac85a166c26`, object id
`7f6ccab9-764d-4003-ae6a-7706f2b9962e`. It only signs in from GitHub Actions (OIDC), so nothing it can do is
testable locally except through Dataverse impersonation.

## Done this session

1. Dashboard reworked into a shell: sidebar, Overview page, Inactive assets as one report, "DLP policy drift" as
   a planned placeholder (`src/shell.ts`, `src/reports/`, `src/inactive.ts`). App renamed. Live.
2. `AuditLogsQuery.Read.All` (Graph, application) granted to the service principal through
   `bootstrap/graph.tf`, applied with `terraform apply -target` for that one resource. Verified on the principal.
3. App launch signal: the scan queries the Purview audit log (Graph `security/auditLog/queries`, record type
   `powerAppsApp`), keeps launch operations, and matches them to apps by finding a known app id anywhere in the
   event. Falls back to modification only if the query fails. Last launch is stored per app (`rev_lastlaunchon`);
   the audit window end is stored per scan (`rev_launchesthrough`) so later scans read only the new part.
4. Application user for the service principal in the LowCodeRev environment with a custom role
   "Inactive Asset Scan": create/read/write/append on the three log tables, metadata read, read on cloud flows.
   Verified by impersonation: reads and writes the log, denied on `accounts`.

## Results of the first CI runs (2026-11-19)

Commits `4d4c68e`, `3aeda13` and a follow-up fix are pushed. Repository variable
`INACTIVE_ASSETS_DATAVERSE_URL` is set. Run 44442721304 on PR #7 showed:

- **Dataverse logging as the service principal works.** The scheduled scan now feeds the dashboard.
- **App launches: blocked. Auditing is turned off in the tenant.** The audit API answers 400 with status
  `AuditingDisabledTenant`. The permission and the request are accepted; there is simply no audit log. The scan
  falls back to modification only, as designed.
- **Flows are still invisible to the service principal** (0 listed; Andy sees 4). The application user did not
  fix the flow admin API. The first run also retired the flow record a local scan had logged; fixed, an asset is
  now only marked gone when the listing for its environment and type returned something.

## Agent quarantine (2026-11-20)

- The quarantine API was tested by hand on "Test Agent for Quarantine" (bot `fb95d810-0507-4619-8d4d-1912d9f48b7c`,
  LowCodeRev): status, `SetAsQuarantined` and `SetAsUnquarantined` all answer 200 with a user token from the
  Power Platform CLI client (`9cee029c-...`), which carries `CopilotStudio.AdminActions.Invoke`. The Azure CLI
  token gets 403. The agent was left quarantined by hand at the user's request.
- Agents are a third asset type in the scan: read from each environment's Dataverse `bots` table, activity from
  `modifiedon`, `publishedon` and the latest conversation transcript. Schema redeployed (asset type choice gained
  "Agent"). A report-only local scan lists CAPCOM and the test agent.
- With `-Enforce` and `enforcement.quarantineAgents` (set to true in the policy) the scan quarantines agents at or
  past the Quarantine stage and releases the ones it quarantined when they are active again. The workflow passes
  `-Enforce` on the schedule and on a manual run with "enforce" ticked, never on pull requests.
- **Not verified:** the scan's own quarantine and release calls. The live round trip (`-Enforce -InteractiveSignIn
  -EnforceAssetId <test agent>`) timed out waiting for browser sign-ins and changed nothing.
- **Not verified:** whether the service principal can call the quarantine API. `CopilotStudio.AdminActions.Invoke`
  is delegated only (the Power Platform API exposes no application permission for it) and Microsoft's docs ask
  for a user token, so adding a scope to the app registration does not help a principal signing in as itself.
  App-only calls would have to be accepted through Power Platform RBAC, and the tenant-wide Contributor
  assignment in `bootstrap/pp_rbac.tf` is itself still unapplied (see open questions). On 401 or 403 the scan
  warns once and changes nothing. Settle it with a manual workflow run with "enforce".
- `Grant-InactiveAssetAccess.ps1` now also grants read on `bot` and `conversationtranscript`; it has **not** been
  rerun, so in CI agents are not listed yet (the scan warns and carries on).
- Owners are not notified, so quarantine happens with no warning sent. CAPCOM (last modified 2026-08-31) reaches
  Quarantine about 2026-12-13.
- Dashboard shows agents (type filter, icon, last conversation). Type-checks; not rebuilt or pushed to Power Apps.

## Not yet verified

- The audit query end to end, and the shape of a real launch event. Blocked on auditing being turned on.
- The dashboard inside Power Apps (checked against mock data only). Light mode was never looked at.

## Next steps, in order

Agent quarantine first (items A to E), then the older list.

A. **Prove the scan's own quarantine and release** on the test agent. The user must be at the browser: each run
   opens one sign-in, and the agent is currently quarantined by hand, so release it first or the scan reports
   "already quarantined, left as is".
   1. Release by hand (`SetAsUnquarantined`, see "Agent quarantine API by hand" below).
   2. `-InactiveDays 0.001 -QuarantineWarningDays 0.001 -QuarantinedDays 1000 -Enforce -InteractiveSignIn
      -EnforceAssetId fb95d810-0507-4619-8d4d-1912d9f48b7c -SkipLaunchSignal -DataverseUrl ...` should report
      "quarantined" and store platform state "Quarantined by policy".
   3. The same without the period overrides should report "released".
   4. Quarantine by hand again if the user still wants it left that way.
B. **Ask the user to confirm two defaults:** enforcement is switched on in the policy and on the daily run (it
   takes effect once this reaches `main`), and agents are quarantined with no warning sent to the owner.
C. **Rerun `Grant-InactiveAssetAccess.ps1`** for LowCodeRev, with the user's go-ahead: it adds read on agents and
   on conversation transcripts (content included) to the service principal's role. Without it CI lists no agents.
D. **Find out whether CI can quarantine:** manual workflow run with "enforce" ticked and short periods, then read
   the "Agent quarantine" table and warnings in the run summary. If the service principal is refused, the options
   are a licensed admin service account signing in through the Terraform app with the delegated scope, or keeping
   enforcement as a manual local run.
E. **Dashboard:** `npm run build` and push so agents show in Power Apps.

1. **Turn on auditing** (the user's call; tenant-wide). Purview portal > Audit > "Start recording user and admin
   activity", or Exchange Online PowerShell `Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true`.
   It can take an hour or more to take effect and only records events from then on, so every app will show "no
   launch" until someone opens it.
2. After that, launch an app, wait for the event (up to a day), rerun the workflow and read the `audit:` lines
   in the Scan step. Confirm launches match apps and "Last launch" shows in the dashboard.
3. **Flow visibility in CI.** Option to try: read cloud flows from the Dataverse `workflow` table (category 5)
   as the application user, which already has read on it. This needs each environment's Dataverse URL and an
   application user per environment, and gives no run history, so it is a design decision, not a quick fix.
   Until then only local scans see flows.
4. Still unbuilt from the original ask: owner notification from a SendAs mailbox, the "keep this asset" request,
   enforcement for apps and flows (quarantine and delete) and agent deletion, and DLP alignment and drift
   through Terraform.

## Open questions for the user

- Should the 14-day warning start at day 90 (current) or day 76, so quarantine lands on day 90?
- `bootstrap` has a pending, unapplied change from commit `e0f95b7`: a tenant-wide "Power Platform Contributor"
  role assignment for the service principal. A full `terraform apply` there would create it. Apply or remove?
- The DLP placeholder in the dashboard is an assumption; keep or hide unbuilt reports?
- App folder is still `apps/asset-governance` and the solution `InactiveAssetGovernance`; rename or leave?

## Useful commands

```powershell
# Local scan, logging to Dataverse (as Andy; launch signal will warn and fall back)
./scripts/inactive-assets/Invoke-InactiveAssetScan.ps1 -DataverseUrl https://lowcoderev.crm.dynamics.com

# Test scan with short periods (marked as a test run in the dashboard)
./scripts/inactive-assets/Invoke-InactiveAssetScan.ps1 -InactiveDays 30 -QuarantineWarningDays 7 -QuarantinedDays 30 -DeleteWarningDays 7 -DataverseUrl https://lowcoderev.crm.dynamics.com

# Dashboard
cd apps/asset-governance; npm run build; npx --no-install pa app push --non-interactive
```

Agent quarantine API by hand (needs a user token with `CopilotStudio.AdminActions.Invoke`; the scan's
`Get-BrowserToken` shows how to get one through the browser):

```
GET  https://api.powerplatform.com/copilotstudio/environments/{envId}/bots/{botId}/api/botQuarantine?api-version=1
POST .../api/botQuarantine/SetAsQuarantined?api-version=1
POST .../api/botQuarantine/SetAsUnquarantined?api-version=1
```

LowCodeRev environment id `50b383ee-e3db-ed10-983d-376a576cd404`. Agents there: "Test Agent for Quarantine"
(`fb95d810-0507-4619-8d4d-1912d9f48b7c`) and CAPCOM (`68438ef7-e684-4760-b7ce-3bd4670aa6fc`, a real agent: do not
enforce against it in tests; use `-EnforceAssetId`).

Local quirks:

- Only Windows PowerShell 5.1 is installed (no `pwsh`). Run the scan with `& .\scripts\...ps1`; through
  `powershell -File` with a relative path `$PSScriptRoot` is empty in the parameter defaults.
- `@($list)` on a `List[object]` throws "Argument types do not match" in 5.1; use `.ToArray()`.
- Pester 5 is not installed (only 3.4) and `Save-Module` needs a NuGet prompt. Download the package from
  `https://www.powershellgallery.com/api/v2/package/Pester/5.7.1`, unzip it and import `Pester.psd1`; CI also
  runs the tests.
- Editing PowerShell through a bash heredoc fails on quoting: write patch scripts to a file first.
- The installed `pac` (2.7.4) is too old for `pac copilot-studio` and has no LowCodeRev profile.
