terraform {
  required_version = ">= 1.9"

  required_providers {
    powerplatform = {
      source  = "microsoft/power-platform"
      version = "~> 4.2"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }

  # Partial backend configuration. Values come from bootstrap output `backend_hcl`, passed at init time:
  #   terraform init -backend-config=backend.hcl   (local; file is git-ignored)
  #   terraform init -backend-config="storage_account_name=..." ...   (CI, from repository variables)
  backend "azurerm" {
    key = "governance.tfstate"
  }
}

# Credentials come from environment variables only, so the same code runs locally and in CI:
#   local: POWER_PLATFORM_USE_CLI=true          (after `az login --allow-no-subscriptions`)
#   CI:    POWER_PLATFORM_USE_OIDC=true + POWER_PLATFORM_CLIENT_ID + POWER_PLATFORM_TENANT_ID
provider "powerplatform" {}

# Entra ID, for the PP-Makers security group. Azure CLI locally; ARM_USE_OIDC + ARM_CLIENT_ID + ARM_TENANT_ID in CI.
provider "azuread" {}
