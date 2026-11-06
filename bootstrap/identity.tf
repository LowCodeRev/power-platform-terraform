# App registration and service principal that Terraform CI runs as.
#
# API permissions follow the provider's app_registration guide. All are delegated scopes; the provider
# requests `.default` and relies on admin consent (granted below). Scope IDs are resolved from the tenant's
# copies of the first-party service principals rather than hardcoded.

data "azuread_client_config" "current" {}

data "azuread_service_principal" "power_platform_api" {
  client_id = "8578e004-a5c6-46e7-913e-12f58912df43"
}

data "azuread_service_principal" "powerapps_service" {
  client_id = "475226c6-020e-4fb2-8a90-7a972cbfc1d4"
}

data "azuread_service_principal" "dynamics_crm" {
  client_id = "00000007-0000-0000-c000-000000000000"
}

locals {
  power_platform_api_scopes = [
    "AppManagement.ApplicationPackages.Install",
    "AppManagement.ApplicationPackages.Read",
    "Licensing.Allocations.ReadWrite",
    "Licensing.BillingPolicies.ReadWrite",
    "PowerApps.Apps.Play",
    "PowerApps.Apps.Read",
    "EnvironmentManagement.Environments.Read",
    "EnvironmentManagement.Groups.ReadWrite",
    "EnvironmentManagement.Settings.ReadWrite",
  ]
  powerapps_service_scopes = ["User"]
  dynamics_crm_scopes      = ["user_impersonation"]
}

resource "azuread_application" "terraform" {
  display_name     = var.app_display_name
  description      = "Identity used by Terraform (microsoft/power-platform provider) to manage Power Platform governance and environments. Registered as a Power Platform admin management application."
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.current.object_id]

  required_resource_access {
    resource_app_id = data.azuread_service_principal.power_platform_api.client_id

    dynamic "resource_access" {
      for_each = toset(local.power_platform_api_scopes)
      content {
        id   = data.azuread_service_principal.power_platform_api.oauth2_permission_scope_ids[resource_access.value]
        type = "Scope"
      }
    }
  }

  required_resource_access {
    resource_app_id = data.azuread_service_principal.powerapps_service.client_id

    dynamic "resource_access" {
      for_each = toset(local.powerapps_service_scopes)
      content {
        id   = data.azuread_service_principal.powerapps_service.oauth2_permission_scope_ids[resource_access.value]
        type = "Scope"
      }
    }
  }

  required_resource_access {
    resource_app_id = data.azuread_service_principal.dynamics_crm.client_id

    dynamic "resource_access" {
      for_each = toset(local.dynamics_crm_scopes)
      content {
        id   = data.azuread_service_principal.dynamics_crm.oauth2_permission_scope_ids[resource_access.value]
        type = "Scope"
      }
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "azuread_service_principal" "terraform" {
  client_id                    = azuread_application.terraform.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]

  lifecycle {
    prevent_destroy = true
  }
}

# Tenant-wide admin consent for the delegated scopes above.

resource "azuread_service_principal_delegated_permission_grant" "power_platform_api" {
  service_principal_object_id          = azuread_service_principal.terraform.object_id
  resource_service_principal_object_id = data.azuread_service_principal.power_platform_api.object_id
  claim_values                         = local.power_platform_api_scopes
}

resource "azuread_service_principal_delegated_permission_grant" "powerapps_service" {
  service_principal_object_id          = azuread_service_principal.terraform.object_id
  resource_service_principal_object_id = data.azuread_service_principal.powerapps_service.object_id
  claim_values                         = local.powerapps_service_scopes
}

resource "azuread_service_principal_delegated_permission_grant" "dynamics_crm" {
  service_principal_object_id          = azuread_service_principal.terraform.object_id
  resource_service_principal_object_id = data.azuread_service_principal.dynamics_crm.object_id
  claim_values                         = local.dynamics_crm_scopes
}
