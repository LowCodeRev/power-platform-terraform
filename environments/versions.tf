terraform {
  required_version = ">= 1.9"

  required_providers {
    powerplatform = {
      source  = "microsoft/power-platform"
      version = "~> 4.2"
    }
  }

  backend "azurerm" {
    key = "environments.tfstate"
  }
}

provider "powerplatform" {}
