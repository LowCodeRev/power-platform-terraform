# Handoff: inactive asset policy and governance dashboard

Written 2026-11-18. Branch `feature/inactive-assets` (draft PR #7, base `feature/pde-requests`). Last commit is
`81e703f`; **everything described under "Uncommitted" is in the working tree only**.

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
| Policy | `policies/inactive-assets.json` | 90 / 14 / 90 / 14 days, `appLaunchSignal` added (uncommitted) |
| Scan | `scripts/inactive-assets/Invoke-InactiveAssetScan.ps1` | Apps + flows, launch signal added (uncommitted) |
| Logic + tests | `InactiveAssets.psm1`, `tests/` | 20 Pester tests pass locally |
| Dataverse schema | `Deploy-InactiveAssetSchema.ps1` | Deployed to https://lowcoderev.crm.dynamics.com, incl. the two new columns |
| Service principal access | `Grant-InactiveAssetAccess.ps1` (new, uncommitted) | Run and verified in the LowCodeRev environment |
| Workflow | `.github/workflows/inactive-assets.yml` | Daily 11:30 UTC; Dataverse URL variable wired (uncommitted) |
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

## Not yet verified

- **The audit query has never run with a permitted identity.** Andy's account gets 403 from the audit API (no
  Purview audit role, and the az CLI token lacks the scope). First real test is the workflow run after a push.
- **Launch event shape.** No real `LaunchPowerApp` event from this tenant has been seen. The scan logs event
  counts by operation; check them in the first CI run. If zero launches come back, check that auditing is turned
  on in the tenant and that the operation name contains "Launch".
- **Flow visibility for the service principal.** In CI the flow admin API returned 200 with 0 flows. The
  hypothesis is that the new application user (with read on workflows) fixes this. Unconfirmed.
- The dashboard was checked against mock data locally, not inside Power Apps. Light mode was never looked at.

## Next steps, in order

1. **Ask to commit and push** the working tree. The push triggers the workflow on PR #7.
2. **Set the repository variable** `INACTIVE_ASSETS_DATAVERSE_URL=https://lowcoderev.crm.dynamics.com`
   (`gh variable set`), or the CI scan will not write to Dataverse. Not done; ask first.
3. Read the CI run: launch counts, whether flows now appear, whether the Dataverse log step succeeds as the
   service principal. Then open the dashboard and check "Last launch" in an app's detail panel.
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
