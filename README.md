# lowcoderev.ai Power Platform governance as code

Terraform configuration for the lowcoderev.ai tenant using the
[microsoft/power-platform](https://registry.terraform.io/providers/microsoft/power-platform/latest) provider.
See `PLAN.md` for the research, phased plan, and tenant inventory.

## Layout

| Folder | State | Run as | Purpose |
|---|---|---|---|
| `bootstrap/` | local, then migrated to Azure Storage | you, interactively | App registration, Power Platform admin registration, CI federation, state storage |
| `governance/` | Azure Storage `governance.tfstate` | CI (OIDC) or you | Tenant settings, tenant isolation, DLP, environment groups and rule sets |
| `environments/` | Azure Storage `environments.tfstate` | CI (OIDC) or you | Environment lifecycle and managed environment settings |
| `.github/workflows/` | | | Plan on PR, gated apply on main, nightly drift detection, nightly PDE adoption, PDE decommission |
| `modules/pde/` | | | One personal developer environment per record; adopted from environment routing nightly. See [docs/pde-process.md](docs/pde-process.md) |
| `policies/`, `scripts/inactive-assets/` | none | CI (OIDC) or you | Inactive asset policy scan; report only except agent quarantine. See below |

## Local runs

```powershell
az login --allow-no-subscriptions --tenant lowcoderev.ai
$env:POWER_PLATFORM_USE_CLI = "true"
$env:ARM_USE_AZUREAD = "true"            # only needed once the azurerm backend is configured
cd governance
terraform init
terraform plan
```

Every root module reads provider credentials from environment variables only, so the same code runs locally
with Azure CLI auth and in GitHub Actions with OIDC.

## One-time setup runbook

**Status 2026-11-06: steps 1 to 4 are done.** Bootstrap applied (16 resources), all three states live in
`stlcrtfstatesouxcw/tfstate`, both import roots applied and plan clean. Remaining: step 5 (GitHub side).

Reference, in case it ever has to be redone from a shell where `az login --allow-no-subscriptions --tenant lowcoderev.ai` is active:

```powershell
# 1. Identity + Power Platform admin registration + state storage (as you, Global Admin)
cd bootstrap
cp terraform.tfvars.example terraform.tfvars   # set github_repository = "<owner>/<repo>"
terraform apply
terraform output -raw backend_hcl | Out-File -Encoding ascii backend.hcl
Copy-Item backend.hcl ..\governance\backend.hcl
Copy-Item backend.hcl ..\environments\backend.hcl

# 2. Move bootstrap's own state into the storage account
Remove-Item backend_override.tf
terraform init -migrate-state -backend-config=backend.hcl

# 3. Adopt existing tenant settings, isolation policy, env group (first apply writes identical settings values)
cd ..\governance
Remove-Item backend_override.tf
$env:POWER_PLATFORM_USE_CLI = "true"
terraform init -backend-config=backend.hcl
terraform apply
terraform plan        # must report "No changes"

# 4. Adopt the two environments (import only, no changes)
cd ..\environments
Remove-Item backend_override.tf
terraform init -backend-config=backend.hcl
terraform apply
terraform plan        # must report "No changes"

# 5. GitHub: create the repo, push, set the four repository Variables below, create Environment "production"
#    with yourself as required reviewer, enable branch protection on main requiring the "plan" check.
```

If `terraform apply` in step 1 fails on the admin management application with a consent or scope error, run
`az login --allow-no-subscriptions --tenant lowcoderev.ai --scope https://api.powerplatform.com/.default` and retry.

The service principal needs two separate Power Platform grants, both in bootstrap: the admin management application
registration (`pp_admin.tf`, covers the legacy BAP admin API) and a Power Platform RBAC role assignment
(`pp_rbac.tf`, Contributor at tenant scope, covers `api.powerplatform.com` and the governance host). Missing the
second one shows up as a bare `403 Forbidden` on environment group rule sets and rule-based policies.

## CI variables (GitHub repository settings, Variables not Secrets, nothing here is secret)

| Variable | Value |
|---|---|
| `PP_CLIENT_ID` | `261c6986-a969-482e-bb81-9ac85a166c26` |
| `PP_TENANT_ID` | `19a0c33f-bf94-4ef0-b894-539351f7aa80` |
| `ARM_SUBSCRIPTION_ID` | `f8434e0f-a68e-4a64-890d-808b91cce3e6` |
| `TF_STATE_STORAGE_ACCOUNT` | `stlcrtfstatesouxcw` |

Repository: `LowCodeRev/power-platform-terraform`. The federated credentials on the app trust exactly:
`refs/heads/main`, pull requests, and the GitHub Environment `production`. Create that Environment with
yourself as a required reviewer before the first apply run, and protect `main` so the `plan` check must pass.

First PR: exercises the plan workflow and the service principal OIDC path.

## Inactive asset policy (report only, except agent quarantine)

`scripts/inactive-assets/Invoke-InactiveAssetScan.ps1` lists every app, cloud flow and Copilot Studio agent and
reports where each one sits on the lifecycle timeline. Apps and flows are never changed. The `inactive-assets`
workflow runs it daily and publishes the result as the run summary and an artifact (JSON, CSV, Markdown).

Agent quarantine is the one action the scan takes. It needs both `enforcement.quarantineAgents` in the policy and
`-Enforce` on the run (the daily run and a manual run with "enforce" ticked pass it; pull request runs never do).
An agent at or past the Quarantine stage is quarantined through the Power Platform API
(`copilotstudio/.../botQuarantine/SetAsQuarantined`). An agent this policy quarantined is released when it is
active again or exempt; one quarantined by anyone else is left alone. Without `-Enforce` the report lists what
would be done.

```powershell
# Pilot: enforce for one agent only, signing in to the Power Platform API through the browser
./scripts/inactive-assets/Invoke-InactiveAssetScan.ps1 -DataverseUrl https://lowcoderev.crm.dynamics.com -Enforce -InteractiveSignIn -EnforceAssetId <bot id>
```

Timeline, in days since the last modification or use, from `policies/inactive-assets.json`:

| Stage | Starts at (defaults) |
|---|---|
| Quarantine warning | 90 (`inactiveDays`) |
| Quarantine | 104 (+ `quarantineWarningDays` 14) |
| Delete warning | 194 (+ `quarantinedDays` 90) |
| Delete | 208 (+ `deleteWarningDays` 14) |

Testing without waiting: override any period for one run, or move "today".

```powershell
az login --allow-no-subscriptions --tenant lowcoderev.ai
./scripts/inactive-assets/Invoke-InactiveAssetScan.ps1 -InactiveDays 1 -QuarantineWarningDays 1 -QuarantinedDays 1 -DeleteWarningDays 1
./scripts/inactive-assets/Invoke-InactiveAssetScan.ps1 -AsOf 2027-06-01
```

The same overrides are inputs on the workflow's manual run. Exempt an asset by adding
`{ "assetId": "<id>", "reason": "...", "expires": "2027-01-31" }` to `exemptions` (`expires` is optional).

Known limits:

- App launches come from the Purview audit log (Graph `security/auditLog/queries`), which needs
  `AuditLogsQuery.Read.All` (granted to the service principal in `bootstrap/graph.tf`) and auditing turned on
  in the tenant. The query is slow and asynchronous; `appLaunchSignal` in the policy sets how far back it looks
  and how long the scan waits. If it cannot be read the scan still completes and apps fall back to last
  modification only, so an app that is used but not edited shows as inactive.
- The audit log is kept for a limited time. With `-DataverseUrl` the last launch seen for each app is stored, so
  it keeps counting after it ages out; without Dataverse each run only knows what is still in the log.
- Flow run history is kept by the platform for about 28 days, so a flow's last run older than that is invisible.
- Flows and agents from managed solutions are skipped (`excludeManaged`). Model-driven apps are not scanned.
- Agents are read from each environment's Dataverse (`bots`, `conversationtranscripts`), so the scan's identity
  needs read access there (`Grant-InactiveAssetAccess.ps1` per environment for the service principal).
  Transcripts are kept about 30 days; with `-DataverseUrl` the last conversation seen is stored.
- The quarantine API wants a user token carrying `CopilotStudio.AdminActions.Invoke`, a delegated permission.
  The Azure CLI's own sign-in does not carry it (403), hence `-InteractiveSignIn` locally. Whether the service
  principal can call it from CI is not yet proven; if it cannot, the run reports one warning and changes nothing.
- Releasing needs `-DataverseUrl`: "quarantined by this policy" is remembered in the asset's platform state.
- The stage is a projection from last activity, and owners are not notified yet. Agent quarantine therefore
  happens without a warning having been sent. Enforcement should count each warning period from the date the
  owner was actually notified once notification exists.
