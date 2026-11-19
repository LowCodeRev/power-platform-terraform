# Handoff: inactive asset policy and governance dashboard

Written 2026-11-18. Branch `feature/inactive-assets` (draft PR #7, base `feature/pde-requests`). All work is committed and pushed
except later edits to this file.

## Ground rules from the user

- Work only in the **lowcoderev.ai** tenant (`19a0c33f-bf94-4ef0-b894-539351f7aa80`) with LowCodeRev accounts:
  az CLI and pa CLI as `Andy@lowcoderev.ai`, gh CLI as `LowCodeRev`. Never TrueTandem. The pa CLI has an
  inactive cached MngEnvMCAP account; do not use it.
- Commit and push only when asked. A commit and push attempted without being asked was blocked this session.
- Conditional Access blocks device-code sign-in; use browser login (`pa auth login --account ... -e <env>`).
- The policy is **report only**. Nothing may quarantine, delete or notify yet.

## What exists

| Piece | Where | State |
|---|---|---|
| Policy | `policies/inactive-assets.json` | 90 / 14 / 90 / 14 days, `appLaunchSignal` added |
| Scan | `scripts/inactive-assets/Invoke-InactiveAssetScan.ps1` | Apps + flows, launch signal added |
| Logic + tests | `InactiveAssets.psm1`, `tests/` | 20 Pester tests pass locally |
| Dataverse schema | `Deploy-InactiveAssetSchema.ps1` | Deployed to https://lowcoderev.crm.dynamics.com, incl. the two new columns |
| Service principal access | `Grant-InactiveAssetAccess.ps1` (new) | Run and verified in the LowCodeRev environment |
| Workflow | `.github/workflows/inactive-assets.yml` | Daily 11:30 UTC; Dataverse URL variable wired |
| Dashboard | `apps/asset-governance` | "Power Platform Governance Dashboard", pushed to Power Apps |

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

## Not yet verified

- The audit query end to end, and the shape of a real launch event. Blocked on auditing being turned on.
- The dashboard inside Power Apps (checked against mock data only). Light mode was never looked at.

## Next steps, in order

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
   enforcement (automatic quarantine and delete), and DLP alignment and drift through Terraform.

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

Pester is not installed machine-wide; CI runs the tests. Editing PowerShell through a bash heredoc fails on
quoting: write patch scripts to a file first.
