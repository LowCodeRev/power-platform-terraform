# Power Platform Terraform Provider: Stand-up Plan for the lowcoderev.ai dev tenant

Research date: 2026-11-05. Provider version at time of research: **v4.2.1** (released 2026-10-19).

Goal: manage the lowcoderev.ai tenant's Power Platform governance (tenant settings, DLP, tenant isolation,
environment groups and rules, managed environments) and environment lifecycle as code, with Terraform,
run from CI with no long-lived secrets.

---

## 1. Where things stand today

| Item | State |
|---|---|
| Project folder | `C:\Users\Andy Ricchiuto\projects\lcr\terraforom` holds only this plan, not a git repo |
| Azure CLI | Installed (2.86.0), logged in as Andy@lowcoderev.ai |
| Terraform CLI | **v1.17.0 installed via winget** (restart the shell to pick up PATH) |
| PAC CLI | Not installed (optional for this work) |
| Power Platform PowerShell modules | Not installed (optional; provider replaces the key cmdlet) |
| Tenant | lowcoderev.ai, tenant ID `19a0c33f-bf94-4ef0-b894-539351f7aa80`, you hold Global Administrator |
| Azure subscription in tenant | **Yes**: "Azure subscription 1" `f8434e0f-a68e-4a64-890d-808b91cce3e6`, you are Owner, no storage accounts yet |

### Tenant inventory (captured 2026-11-05 via the admin APIs, read-only)

**Environments (2)**

| Name | ID | Type | Region | Dataverse | Managed | Environment group |
|---|---|---|---|---|---|---|
| Low Code Rev (default) | `Default-19a0c33f-bf94-4ef0-b894-539351f7aa80` | Default | unitedstates / westus | **none** | No | none |
| LowCodeRev | `50b383ee-e3db-ed10-983d-376a576cd404` | **Developer** | unitedstates / westus | `https://lowcoderev.crm.dynamics.com/` (v9.2.26104, lang 1033, no security group) | Yes (protection level Standard) | Low Code Rev R+D |

**Environment groups (2)**

| Name | ID | Notes |
|---|---|---|
| Default Environment Group | `84659ecc-12e6-4adf-817b-d50b8f634e03` | Microsoft-managed, created 2026-09-11, carries a Microsoft-managed sharing rule set (`db6d24a7-...`). Do not try to own it in Terraform. |
| Low Code Rev R+D | `a11f3e78-0fb1-40a6-a2d5-9fc369765c2a` | Created by you 2026-08-05, contains the LowCodeRev env. Import target. |

**Governance state**

- DLP policies: **none**. Phase 4 starts from a blank slate, nothing to import.
- Tenant isolation: API reports `isDisabled = false` with an empty allowed-tenants list. Confirm in the admin
  center whether cross-tenant connections are actually blocked before importing; the import must match reality.
- Admin management applications registered: **none**. Phase 1 step 4 is required.
- Tenant settings worth noting (current values): environment, trial, developer and Teams environment creation by
  non-admins all **allowed**; default environment routing **off**; share-with-everyone **disabled**; connection
  sharing with everyone allowed; storage warning threshold 85; Copilot features on. Full JSON captured in the
  session scratchpad; re-read via `data.powerplatform_tenant_settings` during Phase 3.

**Licensing (subscribedSkus)**: Business Premium + Microsoft 365 Copilot (1 seat), Power Automate Free, Power
Apps viral/trial. No standalone premium Power Apps or Power Automate plan. Managed Environments is already enabled
on the Developer env, so the API accepts it, but enforcement for regular users depends on premium licensing.
Treat environment groups and rule sets as usable for configuration in this dev tenant.

**Identity**: the first-party service principals needed for API permissions all exist in the tenant
(Power Platform API, PowerApps Service, Dataverse). One app registration named `sp-power-platform`
(`0cb5c736-8ed7-4019-a65f-966cb1bc332a`, created 2026-09-09) exists but is effectively empty: only Graph
`User.Read`, no secrets, no certificates, no federated credentials, no owners, no admin consent, not registered
with Power Platform. Either adopt it in the bootstrap via an `import` block or leave it and create a fresh
`sp-terraform-powerplatform`. Recommendation: create fresh, delete the stray one later.

---

## 2. What the provider is (facts that shape the design)

- Registry source `microsoft/power-platform`, maintained by Microsoft on GitHub. Semantic versioning.
  v4.2.1 is current. **v5.0.0 is announced** and will remove `powerplatform_rest` and `powerplatform_solution`
  (replaced by `powerplatform_managed_solution`) and several deprecated `tenant_settings` attributes. Pin `~> 4.2`.
- Still carries preview labels on: `analytics_data_exports`, `copilot_studio_application_insights`,
  `environment` (only the Developer type), `environment_wave`.
- Auth methods: Azure CLI (local), client secret, client certificate, **OIDC / workload identity federation**
  (GitHub Actions, Azure DevOps), managed identity, Azure Developer CLI. Docs recommend OIDC for CI, CLI for local.
- The identity that runs Terraform must be a **Power Platform admin**. For a service principal that means the app
  must be *registered as an admin management application* in Power Platform. A service principal cannot register
  itself. An admin user must do it, either via the provider's own `powerplatform_admin_management_application`
  resource (run as you, with `use_cli = true`) or via `New-PowerAppManagementApp` in PowerShell.
- Once registered, the SPN behaves like a user holding the Power Platform Administrator role. Granular scoping is
  not possible. Treat the SPN as a tenant admin credential.
- Service principal limits per Microsoft docs: works for environment management, tenant settings, and Power Apps
  management. Power Automate APIs only where no license is required. **Developer-type environment creation is not
  supported with SPN auth.**
- Dataverse-level resources (solutions, data records, security role assignments, environment variables) need the
  SPN to be an **application user** inside that environment. Environments the SPN creates get this automatically.
  Imported environments need `powerplatform_environment_application_admin`.

### Resources available (v4.2.1)

Governance and tenant: `tenant_settings`, `tenant_isolation_policy`, `data_loss_prevention_policy`,
`environment_group`, `environment_group_rule_set`, `managed_environment`, `enterprise_policy`,
`admin_management_application`, `billing_policy`, `billing_policy_environment`, `analytics_data_exports`.

Environment lifecycle: `environment`, `environment_settings`, `environment_wave`,
`environment_disaster_recovery`, `environment_application_package_install`, `environment_application_admin`.

Dataverse and ALM: `publisher`, `managed_solution`, `solution` (deprecated), `data_record`, `environment_variable_value`,
`security_role_assignment`, `rbac_role_assignment`, `application_user`, `user`, `connection`, `connection_share`,
`copilot_studio_application_insights`, `rest` (deprecated escape hatch).

Data sources worth using: `connectors` (full connector catalogue with `unblockable` flag, used to build DLP policies),
`environments`, `environment_templates`, `locations`, `languages`, `currencies`, `tenant`, `tenant_capacity`,
`tenant_settings`, `data_loss_prevention_policies`, `security_roles`, `solution_checker_rules`.

---

## 3. Target architecture

```
GitHub repo (this folder)
├── bootstrap/            run ONCE, as you (az login, use_cli). Local or Azure state.
│   ├── identity.tf       azuread app + SPN + API permissions + admin consent
│   ├── pp_admin.tf       powerplatform_admin_management_application
│   ├── federation.tf     GitHub OIDC federated credentials (main branch + PR + environment)
│   └── state.tf          (optional) Azure RG + storage account + container for remote state
├── governance/           tenant-wide, one state file, applied by CI via OIDC
│   ├── tenant_settings.tf
│   ├── tenant_isolation.tf
│   ├── dlp.tf            policies built from data.powerplatform_connectors
│   ├── env_groups.tf     groups + rule sets
│   └── imports.tf        import blocks for pre-existing policies/settings
├── environments/         environment lifecycle, one state file (or one per env later)
│   ├── default.tf        imported default env, prevent_destroy
│   ├── dev.tf / test.tf  existing envs imported, new ones created
│   └── managed.tf        managed_environment per env not in a group
├── modules/
│   └── pp-environment/   display_name, type, location, dataverse, group, managed settings
└── pipelines/            Azure DevOps YAML (chosen 2026-11-06; GitHub Actions equivalents noted in section 9)
    ├── plan.yml          PR build validation: fmt, validate, checkov, terraform plan, plan summary on the PR
    ├── apply.yml         on main: apply, gated by an ADO Environment with required approver
    └── drift.yml         scheduled plan -detailed-exitcode, create a work item on drift
```

Identity model:

| Context | Identity | Provider config |
|---|---|---|
| Bootstrap and emergency local runs | You (andy@lowcoderev.ai, Global Admin) via `az login --allow-no-subscriptions` | `use_cli = true` |
| CI (Azure DevOps) | App registration `sp-terraform-powerplatform` behind an ARM service connection using **workload identity federation** | `use_oidc = true`, `tenant_id`, `client_id`, plus `POWER_PLATFORM_AZDO_SERVICE_CONNECTION_ID` and the `System.OidcRequestUri` / `System.AccessToken` env vars |
| Fallback if OIDC blocked | Same app, client certificate (not secret) | `client_certificate_file_path` |

State backend options, pick one in Phase 2:

1. **Azure Storage blob backend** (recommended if the tenant has any Azure subscription). SSE at rest, blob locking,
   versioning, OIDC access from CI with the `Storage Blob Data Contributor` role. Cheapest and the same pattern as
   the rest of your Azure IaC.
2. **HCP Terraform free tier** if there is no Azure subscription. Remote state, locking, run history. Requires an
   HCP account and token in GitHub secrets.
3. Local state **only** for `bootstrap/` and only until option 1 or 2 exists. Commit nothing from `.terraform/` or `*.tfstate`.

---

## 4. Phased plan

### Phase 0: Workstation and tenant prerequisites (30 min)

1. Install Terraform: `winget install HashiCorp.Terraform` (or `tfenv`-style pinning via `.terraform-version`).
   Target Terraform `>= 1.9` so `import` blocks, `removed` blocks and provider-defined functions all work.
2. Optional: `winget install Microsoft.PowerAppsCLI` for `pac admin list`, `pac admin list-tenant-settings`,
   `pac admin dlp-policy list`. Useful to capture current state before importing.
3. Log in to the tenant: `az login --allow-no-subscriptions --tenant lowcoderev.ai`. Record the tenant ID with
   `az account show --query tenantId`.
4. Confirm whether an Azure subscription exists: `az account list -o table`. This decides the state backend.
5. `git init` this folder, add a `.gitignore` for `.terraform/`, `*.tfstate*`, `*.tfvars` (except `*.auto.tfvars.example`),
   `crash.log`, `.terraform.lock.hcl` **is** committed.
6. Inventory current tenant state so the import phase has ground truth: environment IDs, types, regions, security
   groups, existing DLP policy IDs, current tenant settings. Capture via `pac admin list --json`,
   `pac admin dlp-policy list`, and `pac admin list-tenant-settings`, or via the provider data sources in a throwaway
   read-only root module using `use_cli = true`.

### Phase 1: Bootstrap the Terraform identity (1 to 2 hours, run as you)

Run once from `bootstrap/` with `use_cli = true` on both the `azuread` and `powerplatform` providers.

1. **App registration** `sp-terraform-powerplatform` (single tenant) via `azuread_application` plus
   `azuread_service_principal`. Set yourself as owner.
2. **API permissions** (delegated scopes, as documented by the provider). Resource app IDs:
   - Power Platform API `8578e004-a5c6-46e7-913e-12f58912df43`:
     `AppManagement.ApplicationPackages.Install`, `AppManagement.ApplicationPackages.Read`,
     `Licensing.Allocations.ReadWrite`, `Licensing.BillingPolicies.ReadWrite`, `PowerApps.Apps.Play`,
     `PowerApps.Apps.Read`, `EnvironmentManagement.Environments.Read`, `EnvironmentManagement.Groups.ReadWrite`,
     `EnvironmentManagement.Settings.ReadWrite`.
   - PowerApps Service `475226c6-020e-4fb2-8a90-7a972cbfc1d4`: `User`.
   - Dynamics CRM `00000007-0000-0000-c000-000000000000`: `user_impersonation`.
   Resolve scope IDs at plan time from `azuread_service_principal` data sources (`oauth2_permission_scope_ids`)
   rather than hardcoding GUIDs, exactly as the archived Microsoft quickstart bootstrap did.
   If "Power Platform API" is missing from the tenant's service principals, create it first with
   `azuread_service_principal` `client_id = "8578e004-..."`, `use_existing = true`.
3. **Admin consent**: `azuread_service_principal_delegated_permission_grant` for each resource API, or one
   `az ad app permission admin-consent --id <app>` after apply. Note the provider mostly requests `.default`
   scopes, so consent is what matters, not the per-scope list.
4. **Register as Power Platform admin app**: `powerplatform_admin_management_application { id = <client_id> }`.
   This is the step only an admin user can do. It replaces `New-PowerAppManagementApp`.
5. **Federated credential for Azure DevOps.** Create the ARM service connection in ADO first with
   "Workload Identity federation (manual)" pointing at this app's client ID. ADO then shows the issuer
   (`https://vstoken.dev.azure.com/<org-guid>`) and subject (`sc://<org>/<project>/<service-connection-name>`).
   Put those into `azuread_application_federated_identity_credential` with audience `api://AzureADTokenExchange`
   and apply. Alternatively let ADO's "automatic" mode create its own app registration and skip steps 1 and 5,
   then run steps 2 to 4 against that app's client ID. Manual mode keeps the identity in Terraform, so prefer it.
   The service connection also needs the `Contributor` or `Storage Blob Data Contributor` scope on the state
   storage account (Phase 2) so the `azurerm` backend can use the same federated token.
6. No client secret. If a secret is unavoidable for a short period, give it a 30-day expiry and store it only in
   GitHub Encrypted Secrets. Prefer a certificate over a secret for any non-OIDC path.
7. Verify as the SPN before moving on. From a shell:
   `az login --service-principal -u <client_id> --federated-token ...` is awkward locally, so instead run a tiny
   CI job (Phase 5 skeleton) that does `terraform plan` against a `data "powerplatform_environments" "all" {}`
   root module. Success proves registration, consent, and federation.

Chicken-and-egg note: `bootstrap/` state contains the app object ID and federated credential IDs. Keep it in the
remote backend once Phase 2 exists (migrate with `terraform init -migrate-state`).

### Phase 2: Remote state (30 min)

If an Azure subscription exists:

1. In `bootstrap/state.tf`: resource group `rg-tf-state`, storage account (GRS or LRS, TLS 1.2, public blob access
   off, blob versioning + soft delete on, Defender for Storage optional), container `tfstate`.
2. Role assignments: you and the SPN get `Storage Blob Data Contributor` on the container. In ADO the `azurerm`
   backend authenticates with the pipeline's federated token: `use_azuread_auth = true` and `use_oidc = true` in
   the backend block, plus `ARM_CLIENT_ID`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`,
   `ARM_ADO_PIPELINE_SERVICE_CONNECTION_ID` and `ARM_OIDC_REQUEST_TOKEN` / `ARM_OIDC_REQUEST_URL` set from
   `$(System.AccessToken)` and `$(System.OidcRequestUri)` in the pipeline. Terraform 1.17 supports this natively.
3. Backend block per root module with distinct keys: `bootstrap.tfstate`, `governance.tfstate`, `environments.tfstate`.

If not, create an HCP Terraform organization and workspace per root module, set `TF_API_TOKEN` in GitHub secrets,
and use the `cloud {}` block.

### Phase 3: Import what already exists (2 to 3 hours)

Nothing new gets created until the plan against existing resources is clean. Order:

1. **Tenant settings**: `import { to = powerplatform_tenant_settings.this, id = "<tenant_id>" }`. Write the resource
   to match the current values (use `data.powerplatform_tenant_settings` first to read them). Goal is a no-op plan.
   This resource writes tenant-wide state; the docs do not define destroy behaviour, so add `prevent_destroy`.
2. **Default environment**: import by environment ID with `environment_type = "Default"`, `prevent_destroy = true`.
   `location` and `azure_region` changes force replacement, so copy them exactly.
3. **Existing environments** (the "couple" you have): same pattern. If any is a Developer environment, keep it
   imported but expect limits under SPN auth. For each imported env that Terraform will later touch at the
   Dataverse level, add `powerplatform_environment_application_admin`.
4. **Existing DLP policies**: import by policy GUID. Rebuild the three connector sets from
   `data.powerplatform_connectors` as in the provider example so the config is maintainable.
5. **Existing environment groups / managed environment settings**, if any.
6. Use `terraform plan -generate-config-out=generated.tf` for a first draft of each, then hand-clean. Expect to
   delete read-only attributes from the generated output.

Exit criterion: `terraform plan` in both `governance/` and `environments/` reports **no changes**.

### Phase 4: Governance baseline as code (half a day, iterate)

Decide and encode the policy. Suggested dev-tenant baseline, all adjustable:

1. **Tenant settings**: disable trial and production environment creation by non-admins, disable developer
   environment creation by non-admins (or leave on and route them), disable "share with everyone" for apps,
   disable connection sharing with everyone, enable default environment routing to a "Personal dev" environment
   group, set a storage warning threshold. Skip the attributes marked deprecated for v5.
2. **Tenant isolation**: `is_disabled = false` with an explicit allow list (start with just your own tenant, or
   `"*"` outbound only) so cross-tenant connectors are controlled.
3. **DLP**:
   - `Baseline - all environments`: `environment_type = "AllEnvironments"`, default classification `Blocked`,
     business group = Dataverse, Office 365 (Outlook, Users, Groups), SharePoint, Teams, Approvals, Power Platform
     for Admins style first-party connectors; non-business = remaining unblockable connectors; everything else blocked.
     Add `custom_connectors_patterns` with your own domain allowed and `*` blocked.
   - `Default environment - restrictive`: `OnlyEnvironments` targeting the default env, with a tighter business set.
   - Environment-specific exceptions use `ExceptEnvironments` on the baseline plus `OnlyEnvironments` policies.
   The `powerplatform_connectors` data source makes "everything not listed is blocked" expressible in HCL rather
   than as a hand-maintained list.
4. **Environment groups + rule sets** (requires Managed Environments, which requires premium licensing on the
   tenant; confirm the dev tenant's license state first):
   - `Personal dev` group: sharing limited, usage insights on, solution checker warn, backup 7 days, maker welcome
     content with your onboarding markdown.
   - `Team sandboxes` group: solution checker block, 28-day backup, CSP enabled for canvas/code apps.
   Managed environment settings on an env are ignored once it belongs to a group, so pick one mechanism per env.
5. **Managed environments** for the few envs outside groups (`powerplatform_managed_environment`).
6. Add `enable_continuous_access_evaluation = true` on the provider in CI.

### Phase 5: CI/CD and guardrails (half a day)

0. ADO setup: create the organization at dev.azure.com connected to the lowcoderev.ai tenant, one project
   (for example `platform-governance`), Azure Repos git repo, the ARM service connection from Phase 1 step 5.
   **Gotcha:** new ADO orgs have zero Microsoft-hosted parallel jobs until you submit the free-grant request form
   (typically 2 to 3 business days). Until then either register this PC as a self-hosted agent or wait.
1. `pipelines/plan.yml` as a **build validation policy** on `main`: steps run inside `AzureCLI@2` with the service
   connection so `System.OidcRequestUri` and `System.AccessToken` are available. `terraform fmt -check`,
   `terraform validate`, `checkov -d .` (or `trivy config`), `terraform plan -out=tfplan`, publish the plan text
   as a pipeline artifact and a PR comment via the ADO REST API. Env vars: `POWER_PLATFORM_USE_OIDC=true`,
   `POWER_PLATFORM_CLIENT_ID`, `POWER_PLATFORM_TENANT_ID`, `POWER_PLATFORM_AZDO_SERVICE_CONNECTION_ID`,
   `POWER_PLATFORM_OIDC_REQUEST_URI=$(System.OidcRequestUri)`, `POWER_PLATFORM_OIDC_TOKEN=$(System.AccessToken)`,
   plus the `ARM_*` set from Phase 2 for the backend.
2. `pipelines/apply.yml` triggered on `main`, deployment job targeting an ADO **Environment** `production` with
   an Approvals check (you as approver). Run `governance/` first, then `environments/`.
3. `pipelines/drift.yml` on a nightly schedule: `terraform plan -detailed-exitcode`; exit code 2 creates or
   updates a "Drift detected" work item. This is the governance-as-code payoff: any portal ClickOps change
   surfaces within a day.
4. Branch policies on `main`: minimum one reviewer (you can self-approve in a one-person org), build validation
   required, no direct pushes.
5. Pin the provider (`~> 4.2`) and commit `.terraform.lock.hcl`. Review the CHANGELOG before any minor bump;
   watch for the v5 removals.

### Phase 6: Extend (later)

- `modules/pp-environment` to stamp Dev/Test/Prod sets for new projects, including group membership and
  application package installs (`environment_application_package_install`, e.g. Dataverse accelerators).
- Billing policies tied to an Azure subscription (pay-as-you-go), if Azure exists.
- Dataverse-level config: publishers, managed solution import, environment variable values, security role
  assignments for Entra groups. This is where Terraform meets ALM pipelines; keep solution *content* in pipelines
  and solution *deployment config* in Terraform.
- Enterprise policies (customer-managed keys, VNet injection, identity) need Azure resources and the `azapi`
  provider alongside this one.

---

## 5. Risks and gotchas to design around

- **The SPN is a tenant admin.** There is no least-privilege option inside Power Platform. Protect it with OIDC
  only, branch protection, and GitHub Environment approvals. Monitor Entra sign-in logs for the app.
- **`terraform destroy` is real.** `prevent_destroy` on the default environment, imported environments, tenant
  settings, and tenant isolation. Never run `destroy` from CI.
- **`location` / `azure_region` / `macro_region` changes recreate environments.** Data loss. Keep them stable and
  reviewed in plan output.
- **Tenant settings destroy behaviour is undocumented.** Treat the resource as permanent.
- **Managed Environments licensing.** Environment group rule sets and `managed_environment` need Managed
  Environments, which requires premium licensing. A dev tenant with only trial or developer licenses may reject
  these calls. Verify before Phase 4 step 4.
- **Developer environments under SPN.** Creation not supported; CI will fail. Create them as you, then import.
- **Power Automate licensing.** SPNs cannot hold licenses, so flow-related operations may fail. Out of scope for
  governance work anyway.
- **Preview resources** can change shape in a minor version. Avoid `environment_wave`, `analytics_data_exports`
  in the baseline unless needed.
- **v5.0.0 breaking changes** are announced: `powerplatform_rest`, `powerplatform_solution`, and several
  `tenant_settings` attributes go away. Do not build on them.
- **State contains IDs and possibly connection details.** Encrypted remote backend, restricted access, no local
  state committed.
- **Azure CLI `use_cli` scope issue.** The provider's app-registration guide mentions pre-authorising the Azure CLI
  client (`04b07795-8ddb-461a-bbee-02f9e1bf7b46`) against an exposed API scope. The archived Microsoft bootstrap
  used that pattern. Start with plain `az login --allow-no-subscriptions`; only if the provider reports a token
  or consent error for `api.powerplatform.com`, add the exposed API + pre-authorisation on the bootstrap app and
  log in with `--scope api://<identifier-uri>/.default`.
- **Doc inconsistencies** observed: `language_code` is documented as Number but exampled as a string; the rule
  set doc lists `warm` where `warn` is presumably meant; the empty security group example has a seven-zero GUID.
  Validate values against a real plan rather than trusting the generated docs.

---

## 6. Decisions

Resolved by the inventory:

1. **Azure subscription exists** and you are Owner. Phase 2 uses the Azure Storage backend.
4. **Managed Environments is already in use** on the Developer env, so environment groups and rule sets are
   usable now. Licensing enforcement for other users is a separate concern.

Decided 2026-11-06:

2. **Azure DevOps** for CI. No ADO organization exists for your account yet (no ADO profile found), so Phase 5
   step 0 creates one. Switching cost between ADO and GitHub is small; see section 9.
3. **Import both** the default environment and the LowCodeRev Developer environment. The service principal cannot
   create Developer environments but can manage this one once imported.
5. **Create a new app registration** `sp-terraform-powerplatform`. The stray `sp-power-platform` can be deleted
   after the new one is proven.

Still yours to make:

6. Naming: ADO org and project names, state resource group `rg-tf-state`, container `tfstate`.

---

## 7. Build status (2026-11-06)

CI decision revised: **GitHub Actions now** (no waiting period, OIDC works immediately), ADO org to be created
in parallel and federated later via `bootstrap/` variable `ado_federation`. Section 8 covers the switch.

Done:
- Repo scaffolded (`bootstrap/`, `governance/`, `environments/`, `.github/workflows/`), `git init` on `main`.
- `bootstrap/` validates; plan = 13 resources (app registration with the 11 delegated scopes, admin consent
  grants, Power Platform admin management registration, state RG + storage + container + RBAC).
- `governance/` imports tenant settings, tenant isolation policy and the R+D environment group. Tenant settings
  are written from live values; the provider's import does not populate attributes, so the first apply shows an
  in-place update with identical values, and the second plan must be clean.
- `environments/` imports both environments with zero changes. Two provider quirks handled in code: an
  environment without Dataverse cannot carry `environment_group_id` / `billing_policy_id`, and a Developer
  environment requires `owner_id` but never reads it back (handled with `ignore_changes`).
- Workflows written: `plan.yml` (lint, checkov, matrix plan, PR comment), `apply.yml` (gated by GitHub
  Environment `production`, governance then environments), `drift.yml` (nightly, opens a `drift` issue).

Applied 2026-11-06:
- `bootstrap/`: 16 resources. App `sp-terraform-powerplatform` client ID `261c6986-a969-482e-bb81-9ac85a166c26`,
  registered as a Power Platform admin management application (verified via the BAP adminApplications API),
  admin consent granted on all 11 scopes, 3 GitHub federated credentials for `LowCodeRev/power-platform-terraform`,
  state storage `rg-tf-state` / `stlcrtfstatesouxcw` / `tfstate`. Bootstrap state migrated into the same account.
- `governance/`: 3 imported (tenant settings, tenant isolation, R+D group), 1 no-op settings write. Second plan clean.
- `environments/`: 2 imported. Second plan clean.

Remaining for you:
1. Push this repo to `LowCodeRev/power-platform-terraform`, set the four repository Variables (README), create
   the GitHub Environment `production` with yourself as required reviewer, protect `main` with the `plan` check.
2. Open a trivial PR to prove the OIDC path end to end (the plan job authenticating as the SPN is the real test
   of the admin registration; local runs so far used your own identity).
3. Create the ADO organization at dev.azure.com when convenient; nothing depends on it yet.
4. Delete the stray `sp-power-platform` app registration (`0cb5c736-...`) once CI is proven.

Phase 4 in flight (2026-11-06): PR "Governance baseline: DLP policies and R+D rule set" adds two DLP policies
(tenant-wide baseline with consumer connectors blocked and Microsoft 365 as Business; default environment
locked to core Microsoft 365 with everything else blocked) and the Managed Environments rule set for the R+D
group (sharing limits, usage insights, Solution Checker warn, 7-day backups). Verified against the live
connector inventory so no existing app or flow is affected. Still to decide: tenant settings hardening
(non-admin environment creation, trial creation, portal creation, environment routing).

PDE request process (PR "Personal developer environments: request intake, module, group rules"): makers no
longer create environments. The ITSM portal (or an admin from the Actions tab) triggers the `pde-request`
workflow, which writes `environments/pde-requests/<TICKET>.json` and opens a PR; merge + approved apply
provisions a Developer environment owned by the maker (Sandbox fallback with the maker as System
Administrator) inside the "Personal Developer Environments" group. Decommission is the same path in reverse.
Process doc: docs/pde-process.md. First sample request: ticket REQ-0001 for Tony Stark, raised after merge.
Tenant settings hardening is PR #3 (all six options; developer environment creation also closed, no routing).

---

## 8. Switching between Azure DevOps and GitHub Actions

The Terraform code (`bootstrap/`, `governance/`, `environments/`, `modules/`) is identical on both. Only three
things differ, and each is a small, isolated change:

| Concern | Azure DevOps | GitHub Actions |
|---|---|---|
| Federated credential on the app | Issuer `https://vstoken.dev.azure.com/<org-guid>`, subject `sc://org/project/connection` | Issuer `https://token.actions.githubusercontent.com`, subjects `repo:org/repo:ref:refs/heads/main`, `repo:org/repo:pull_request`, `repo:org/repo:environment:<name>` |
| Provider auth env vars | `POWER_PLATFORM_USE_OIDC`, `POWER_PLATFORM_AZDO_SERVICE_CONNECTION_ID`, `POWER_PLATFORM_OIDC_REQUEST_URI`, `POWER_PLATFORM_OIDC_TOKEN` from pipeline system variables | `POWER_PLATFORM_USE_OIDC` only; GitHub sets `ACTIONS_ID_TOKEN_REQUEST_URL` / `ACTIONS_ID_TOKEN_REQUEST_TOKEN` and the job needs `permissions: id-token: write` |
| Backend env vars | `ARM_ADO_PIPELINE_SERVICE_CONNECTION_ID` plus `ARM_OIDC_REQUEST_TOKEN` / `ARM_OIDC_REQUEST_URL` | `ARM_USE_OIDC=true` and the same `ACTIONS_*` variables |
| Pipeline files | `pipelines/*.yml`, branch policies, Environment approvals | `.github/workflows/*.yml`, branch protection, Environment reviewers |

Migration is: add a second federated credential to the same app (an app can hold up to 20), port the YAML, point
the backend at the same storage account, delete the old credential. State, identity, and HCL are untouched. Budget
about half a day. Keep the federated credential block in `bootstrap/federation.tf` as a map keyed by CI system so
adding the other one is a one-line change.

## 9. Sources

- Provider docs index and guides: https://github.com/microsoft/terraform-provider-power-platform/tree/main/docs
  (index.md, guides/app_registration.md, guides/azure_cli.md, guides/client_secret.md, guides/oidc.md,
  guides/importing.md, guides/security_considerations.md, guides/continuous_access_evaluation.md)
- Resource docs used: environment, data_loss_prevention_policy, tenant_settings, tenant_isolation_policy,
  managed_environment, environment_group_rule_set, admin_management_application, environment_application_admin
- CHANGELOG (v4.2.1, 2026-10-14; v5 removals announced): https://github.com/microsoft/terraform-provider-power-platform/blob/main/CHANGELOG.md
- ROADMAP (public API migration, no dates): https://github.com/microsoft/terraform-provider-power-platform/blob/main/ROADMAP.md
- Terraform Registry: https://registry.terraform.io/providers/microsoft/power-platform/latest
- Microsoft Learn, provider overview: https://learn.microsoft.com/business-applications/playbook/enterprise-solutions/power-platform-terraform-provider
- Microsoft Learn, SPN registration via PowerShell (`New-PowerAppManagementApp`, SPN limits): https://learn.microsoft.com/power-platform/admin/powershell-create-service-principal
- Microsoft Learn, SPN registration via API (`PUT .../adminApplications/{clientId}`): https://learn.microsoft.com/power-platform/admin/powerplatform-api-create-service-principal
- Microsoft Learn, authentication for Power Platform APIs: https://learn.microsoft.com/power-platform/admin/programmability-authentication
- Archived Microsoft quickstarts (bootstrap pattern, API permission GUIDs): https://github.com/microsoft/power-platform-terraform-quickstarts
- Community module notes on immutability and group vs managed-env interaction: https://github.com/microsoftexpert/tf-mod-powerplatform-environment
