# "LowCodeRev" Developer environment with Dataverse (https://lowcoderev.crm.dynamics.com). Imported 2026-11-06.
# Developer environments cannot be created by a service principal; this one exists and is only managed here.
# It belongs to the "Low Code Rev R+D" environment group, so managed-environment settings come from the
# group's rule set (governance root), not from a powerplatform_managed_environment resource.

locals {
  andy_object_id           = "581ed6bb-0894-41ba-9923-812dd1e69fc7" # Andy@lowcoderev.ai
  environment_group_rnd_id = "a11f3e78-0fb1-40a6-a2d5-9fc369765c2a" # governance: powerplatform_environment_group.rnd
}

resource "powerplatform_environment" "lowcoderev" {
  display_name     = "LowCodeRev"
  environment_type = "Developer"
  owner_id         = local.andy_object_id
  location         = "unitedstates"
  azure_region     = "westus"
  cadence          = "Frequent"
  release_cycle    = "Early"

  allow_bing_search                = true
  allow_flex_routing               = false
  allow_microsoft_365_services     = true
  allow_moving_data_across_regions = false

  billing_policy_id    = "00000000-0000-0000-0000-000000000000"
  environment_group_id = local.environment_group_rnd_id

  dataverse = {
    language_code                = 1033
    currency_code                = "USD"
    domain                       = "lowcoderev"
    administration_mode_enabled  = false
    background_operation_enabled = true
  }

  lifecycle {
    prevent_destroy = true
    # The provider requires owner_id for Developer environments but never reads it back from the API, so any
    # value would otherwise force a destroy/recreate. The owner is fixed at creation time anyway.
    ignore_changes = [owner_id]
  }
}

output "lowcoderev" {
  value = {
    id            = powerplatform_environment.lowcoderev.id
    dataverse_url = powerplatform_environment.lowcoderev.dataverse.url
  }
}
