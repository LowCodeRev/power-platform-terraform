# One personal developer environment.
#
# Developer type: owned by the maker, no tenant capacity consumed, created by the provider in preview and
# documented as unsupported under service-principal auth (the first request is the test).
# Sandbox type: the fallback the service principal can always create. Consumes 1 GB of Dataverse capacity;
# the maker is added as System Administrator so the experience is equivalent.

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
  description  = "Personal developer environment. ITSM ${var.ticket}: requested by ${var.requester_upn} on ${var.requested_on}, approved by ${var.approved_by}. ${var.justification}"

  # Well-known Dataverse security role template id for System Administrator.
  system_administrator_role_id = "627090ff-40a3-4053-8790-584edc5be201"
}

resource "powerplatform_environment" "this" {
  display_name         = local.display_name
  description          = local.description
  environment_type     = var.environment_type
  owner_id             = local.is_developer ? var.requester_object_id : null
  location             = var.location
  cadence              = "Frequent"
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
