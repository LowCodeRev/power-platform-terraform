terraform {
  required_version = ">= 1.9"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    powerplatform = {
      source  = "microsoft/power-platform"
      version = "~> 4.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # First apply runs with local state (backend_override.tf forces `backend "local"`). After the storage account
  # exists: delete backend_override.tf and run `terraform init -migrate-state -backend-config=backend.hcl`.
  backend "azurerm" {
    key = "bootstrap.tfstate"
  }
}

# All three providers authenticate as the signed-in Azure CLI user. This root is run interactively by a
# Global Administrator; it is the only place where a human identity is required (a service principal cannot
# register itself as a Power Platform admin management application).

provider "azuread" {
  tenant_id = var.tenant_id
}

provider "azurerm" {
  subscription_id                 = var.subscription_id
  tenant_id                       = var.tenant_id
  storage_use_azuread             = true # the state storage account has shared-key access disabled
  resource_provider_registrations = "none"
  features {}
}

provider "powerplatform" {
  use_cli = true
}
