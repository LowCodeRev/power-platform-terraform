# Workload identity federation: lets CI obtain tokens for the app without any stored secret.
# GitHub Actions is the active CI system. Azure DevOps can be added later by setting `ado_federation`;
# both can coexist on the same app (limit is 20 federated credentials per app).

locals {
  # GitHub's OIDC subject claim qualifies both path segments with numeric IDs so a renamed or re-created
  # repository cannot inherit the trust: repo:<owner>@<owner_id>/<repo>@<repo_id>:<context>.
  # Entra matches subjects exactly, so the IDs are mandatory.
  github_owner = var.github_repository == "" ? "" : split("/", var.github_repository)[0]
  github_repo  = var.github_repository == "" ? "" : split("/", var.github_repository)[1]
  github_repo_segment = var.github_repository == "" ? "" : (
    var.github_owner_id == null || var.github_repository_id == null
    ? var.github_repository
    : "${local.github_owner}@${var.github_owner_id}/${local.github_repo}@${var.github_repository_id}"
  )

  github_subjects = var.github_repository == "" ? {} : {
    main         = "repo:${local.github_repo_segment}:ref:refs/heads/main"
    pull_request = "repo:${local.github_repo_segment}:pull_request"
    apply_env    = "repo:${local.github_repo_segment}:environment:${var.github_apply_environment}"
    plan_env     = "repo:${local.github_repo_segment}:environment:${var.github_plan_environment}"
  }
}

resource "azuread_application_federated_identity_credential" "github" {
  for_each = local.github_subjects

  application_id = azuread_application.terraform.id
  display_name   = "github-${each.key}"
  description    = "GitHub Actions OIDC for ${var.github_repository} (${each.key})"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = each.value
}

resource "azuread_application_federated_identity_credential" "ado" {
  count = var.ado_federation == null ? 0 : 1

  application_id = azuread_application.terraform.id
  display_name   = "azure-devops"
  description    = "Azure DevOps workload identity federation"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = var.ado_federation.issuer
  subject        = var.ado_federation.subject
}
