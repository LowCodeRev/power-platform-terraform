# Data loss prevention policies.
#
# Two policies. Power Platform applies all matching policies and the most restrictive classification wins.
#
#   1. "Baseline - all environments": tenant-wide. Microsoft 365 / Dataverse / Copilot Studio connectors are
#      Business; a short list of consumer storage and social connectors is Blocked; everything else is
#      Non-business so it can be used but never mixed with Business data in the same app or flow. New connectors
#      Microsoft releases default to Non-business ("General"). Custom connectors are allowed.
#   2. "Default environment - restricted": the default environment is where every licensed user lands and has
#      no Dataverse. Only core Microsoft 365 connectors are usable there; everything else is Blocked, including
#      custom connectors and any connector released in future.
#
# Connector sets are built from the live catalogue (data.powerplatform_connectors) so the three groups are always
# explicit and complete; the provider's own example uses the same pattern. `unblockable` connectors can never be
# placed in the Blocked group (the API rejects it), which the filters below respect.
#
# Verified 2026-11-06 against the live environments: the only connections in use are Dataverse, Office 365 Users
# and Copilot Studio, all of which are Business here, so no existing app or flow is affected.

data "powerplatform_connectors" "all" {}

locals {
  connector_prefix = "/providers/Microsoft.PowerApps/apis/"

  # Business: trusted first-party connectors that may touch organisational data.
  business_connector_names = [
    "shared_commondataservice",
    "shared_commondataserviceforapps",
    "shared_office365",
    "shared_office365users",
    "shared_office365groups",
    "shared_sharepointonline",
    "shared_teams",
    "shared_onedriveforbusiness",
    "shared_excelonlinebusiness",
    "shared_approvals",
    "shared_microsoftforms",
    "shared_planner",
    "shared_microsoftcopilotstudio",
    "shared_powerappsnotification",
    "shared_powerappsnotificationv2",
    "shared_flowpush",
  ]

  # Blocked tenant-wide: consumer storage, consumer mail and social connectors.
  blocked_connector_names = [
    "shared_gmail",
    "shared_googledrive",
    "shared_googlecalendar",
    "shared_googletasks",
    "shared_dropbox",
    "shared_box",
    "shared_twitter",
  ]

  # Default environment: a tighter Business list (no Dataverse there, no Copilot Studio).
  default_env_business_connector_names = [
    "shared_office365",
    "shared_office365users",
    "shared_office365groups",
    "shared_sharepointonline",
    "shared_teams",
    "shared_onedriveforbusiness",
    "shared_excelonlinebusiness",
    "shared_approvals",
    "shared_microsoftforms",
    "shared_planner",
    "shared_powerappsnotification",
    "shared_powerappsnotificationv2",
    "shared_flowpush",
  ]

  business_ids             = [for n in local.business_connector_names : "${local.connector_prefix}${n}"]
  blocked_ids              = [for n in local.blocked_connector_names : "${local.connector_prefix}${n}"]
  default_env_business_ids = [for n in local.default_env_business_connector_names : "${local.connector_prefix}${n}"]

  # Shape every connector entry the same way; no per-connector action or endpoint rules in the baseline.
  connector_entry = {
    default_action_rule_behavior = ""
    action_rules                 = []
    endpoint_rules               = []
  }

  all_connectors = data.powerplatform_connectors.all.connectors

  # --- Baseline (all environments) ---------------------------------------------------------------------------
  baseline_business = toset([for id in local.business_ids : merge(local.connector_entry, { id = id })])
  baseline_blocked  = toset([for id in local.blocked_ids : merge(local.connector_entry, { id = id })])
  baseline_non_business = toset([
    for c in local.all_connectors : merge(local.connector_entry, { id = c.id })
    if !contains(local.business_ids, c.id) && !contains(local.blocked_ids, c.id)
  ])

  # --- Default environment -------------------------------------------------------------------------------------
  default_env_business = toset([for id in local.default_env_business_ids : merge(local.connector_entry, { id = id })])
  default_env_non_business = toset([
    for c in local.all_connectors : merge(local.connector_entry, { id = c.id })
    if c.unblockable && !contains(local.default_env_business_ids, c.id)
  ])
  default_env_blocked = toset([
    for c in local.all_connectors : merge(local.connector_entry, { id = c.id })
    if !c.unblockable && !contains(local.default_env_business_ids, c.id)
  ])
}

resource "powerplatform_data_loss_prevention_policy" "baseline" {
  display_name                      = "Baseline - all environments"
  default_connectors_classification = "General"
  environment_type                  = "AllEnvironments"
  environments                      = []

  business_connectors     = local.baseline_business
  non_business_connectors = local.baseline_non_business
  blocked_connectors      = local.baseline_blocked

  custom_connectors_patterns = toset([
    {
      order            = 1
      host_url_pattern = "https://*.lowcoderev.ai"
      data_group       = "Business"
    },
    {
      order            = 2
      host_url_pattern = "*"
      data_group       = "Ignore"
    },
  ])
}

resource "powerplatform_data_loss_prevention_policy" "default_environment" {
  display_name                      = "Default environment - restricted"
  default_connectors_classification = "Blocked"
  environment_type                  = "OnlyEnvironments"
  environments                      = ["Default-${local.tenant_id}"]

  business_connectors     = local.default_env_business
  non_business_connectors = local.default_env_non_business
  blocked_connectors      = local.default_env_blocked

  custom_connectors_patterns = toset([
    {
      order            = 1
      host_url_pattern = "*"
      data_group       = "Blocked"
    },
  ])
}

output "dlp_policy_ids" {
  value = {
    baseline            = powerplatform_data_loss_prevention_policy.baseline.id
    default_environment = powerplatform_data_loss_prevention_policy.default_environment.id
  }
}
