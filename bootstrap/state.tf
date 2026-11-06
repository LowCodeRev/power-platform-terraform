# Remote state storage for every root module (including this one, after migration).
# Shared-key access is disabled: all access is Entra RBAC via `use_azuread_auth = true` in backend blocks.

resource "random_string" "state_suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "state" {
  name     = var.state_resource_group_name
  location = var.location

  tags = {
    purpose   = "terraform-state"
    managedBy = "terraform/bootstrap"
  }
}

resource "azurerm_storage_account" "state" {
  name                = "stlcrtfstate${random_string.state_suffix.result}"
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location

  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = azurerm_resource_group.state.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "state" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"

  depends_on = [azurerm_role_assignment.me_state]
}

# Data-plane access: the CI service principal and the bootstrapping admin.

resource "azurerm_role_assignment" "sp_state" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.terraform.object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "me_state" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azuread_client_config.current.object_id
  principal_type       = "User"
}

# The azurerm backend also lists the storage account via ARM, which needs a control-plane role.
resource "azurerm_role_assignment" "sp_state_reader" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.terraform.object_id
  principal_type       = "ServicePrincipal"
}
