# Workload identity federation: lets CI obtain tokens for the app without any stored secret.
# GitHub Actions is the active CI system. Azure DevOps can be added later by setting `ado_federation`;
# both can coexist on the same app (limit is 20 federated credentials per app).

locals {
  github_subjects = var.github_repository == "" ? {} : {
    main         = "repo:${var.github_repository}:ref:refs/heads/main"
    pull_request = "repo:${var.github_repository}:pull_request"
    apply_env    = "repo:${var.github_repository}:environment:${var.github_apply_environment}"
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
