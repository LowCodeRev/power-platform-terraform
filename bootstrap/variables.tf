variable "tenant_id" {
  description = "Entra tenant ID for lowcoderev.ai."
  type        = string
  default     = "19a0c33f-bf94-4ef0-b894-539351f7aa80"
}

variable "subscription_id" {
  description = "Azure subscription that hosts the Terraform state storage account."
  type        = string
  default     = "f8434e0f-a68e-4a64-890d-808b91cce3e6"
}

variable "location" {
  description = "Azure region for the state storage resources."
  type        = string
  default     = "westus"
}

variable "app_display_name" {
  description = "Display name of the app registration Terraform CI runs as."
  type        = string
  default     = "sp-terraform-powerplatform"
}

variable "state_resource_group_name" {
  description = "Resource group for the Terraform state storage account."
  type        = string
  default     = "rg-tf-state"
}

variable "github_repository" {
  description = "GitHub repository in owner/name form that is allowed to obtain tokens for the app via OIDC. Leave empty to skip GitHub federation."
  type        = string
  default     = ""

  validation {
    condition     = var.github_repository == "" || can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be in owner/name form."
  }
}

variable "github_owner_id" {
  description = "Numeric ID of the GitHub owner (user or org). GitHub embeds it in the OIDC subject as owner@id. `gh api users/<owner> --jq .id`"
  type        = number
  default     = null
}

variable "github_repository_id" {
  description = "Numeric ID of the GitHub repository. GitHub embeds it in the OIDC subject as repo@id. `gh api repos/<owner>/<repo> --jq .id`"
  type        = number
  default     = null
}

variable "github_apply_environment" {
  description = "Name of the GitHub Environment the apply workflow runs in. A federated credential is created for it so the approval gate cannot be bypassed."
  type        = string
  default     = "production"
}

variable "github_plan_environment" {
  description = "GitHub Environment (no protection rules) that read-only jobs bind to. Its federated credential lets plan, drift and adoption jobs authenticate from any branch, since the OIDC subject becomes environment:<name> instead of the branch ref."
  type        = string
  default     = "plan"
}

variable "ado_federation" {
  description = "Optional Azure DevOps workload identity federation. Fill from the service connection's 'Workload Identity federation (manual)' dialog."
  type = object({
    issuer  = string # https://vstoken.dev.azure.com/<org-guid>
    subject = string # sc://<org>/<project>/<service-connection-name>
  })
  default = null
}
