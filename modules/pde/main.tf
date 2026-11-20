# One personal developer environment.
#
# Normal path: environment routing creates a managed Developer environment for a PP-Makers member; the nightly
# pde-adopt workflow records it and this module imports it (see environments/pdes.tf). From then on Terraform
# owns it: settings, group membership, and eventual decommission.
#
# Exception path: a record without environment_id makes Terraform create the environment itself. Developer type
# is documented by the provider as unsupported under service-principal auth; Sandbox is the fallback the service
# principal can always create (1 GB of Dataverse capacity, maker made System Administrator).

terraform {
  required_providers {
    powerplatform = {
      source  = "microsoft/power-platform"
      version = "~> 4.2"
    }
  }
}

locals {
  is_developer = var.environment_type == "Developer"
  display_name = coalesce(var.display_name, "PDE - ${var.requester_name}")
  description = coalesce(
    var.description,
    "Personal developer environment. ${var.ticket}: ${var.requester_upn}, ${var.requested_on}, approved by ${var.approved_by}. ${var.justification}"
  )

  # Well-known Dataverse security role template id for System Administrator.
  system_administrator_role_id = "627090ff-40a3-4053-8790-584edc5be201"
}

resource "powerplatform_environment" "this" {
  display_name         = local.display_name
  description          = local.description
  environment_type     = var.environment_type
  owner_id             = local.is_developer ? var.requester_object_id : null
  location             = var.location
  azure_region         = var.azure_region
  cadence              = var.cadence
  release_cycle        = var.release_cycle
  environment_group_id = var.environment_group_id

  dataverse = merge(
    {
      language_code = var.language_code
      currency_code = var.currency_code
    },
    local.is_developer ? {} : { security_group_id = "00000000-0000-0000-0000-000000000000" }
  )

  lifecycle {
    # The provider never reads owner_id back, so any value would otherwise force replacement.
    ignore_changes = [owner_id]
  }
}

# Sandbox fallback: make the requester System Administrator of their environment.
resource "powerplatform_user" "requester" {
  count = local.is_developer ? 0 : 1

  environment_id = powerplatform_environment.this.id
  aad_id         = var.requester_object_id
  security_roles = [local.system_administrator_role_id]
}
