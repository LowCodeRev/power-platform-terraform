# Tenant default environment. No Dataverse. Imported 2026-11-06.
# location / azure_region changes force replacement; prevent_destroy guards against any destroy path.

resource "powerplatform_environment" "default" {
  display_name     = "Low Code Rev (default)"
  environment_type = "Default"
  location         = "unitedstates"
  azure_region     = "westus"
  cadence          = "Frequent"
  release_cycle    = "Standard"

  allow_bing_search                = true
  allow_flex_routing               = false
  allow_microsoft_365_services     = true
  allow_moving_data_across_regions = false

  # billing_policy_id / environment_group_id are not settable on an environment without Dataverse.

  lifecycle {
    prevent_destroy = true
  }
}
