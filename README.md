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
| `.github/workflows/` | | | Plan on PR, gated apply on main, nightly drift detection |

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
