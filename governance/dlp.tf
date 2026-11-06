# Data loss prevention policies. The tenant has none today (verified 2026-11-05).
# Phase 4 baseline, to be enabled deliberately in its own PR:
#
# data "powerplatform_connectors" "all" {}
#
# locals {
#   business_connector_ids = [
#     "/providers/Microsoft.PowerApps/apis/shared_commondataservice",
#     "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps",
#     "/providers/Microsoft.PowerApps/apis/shared_office365",
#     "/providers/Microsoft.PowerApps/apis/shared_office365users",
#     "/providers/Microsoft.PowerApps/apis/shared_office365groups",
#     "/providers/Microsoft.PowerApps/apis/shared_sharepointonline",
#     "/providers/Microsoft.PowerApps/apis/shared_teams",
#     "/providers/Microsoft.PowerApps/apis/shared_approvals",
#   ]
#   business_connectors = toset([for id in local.business_connector_ids : {
#     id = id, default_action_rule_behavior = "", action_rules = [], endpoint_rules = []
#   }])
#   non_business_connectors = toset([for c in data.powerplatform_connectors.all.connectors : {
#     id = c.id, default_action_rule_behavior = "", action_rules = [], endpoint_rules = []
#   } if c.unblockable && !contains(local.business_connector_ids, c.id)])
#   blocked_connectors = toset([for c in data.powerplatform_connectors.all.connectors : {
#     id = c.id, default_action_rule_behavior = "", action_rules = [], endpoint_rules = []
#   } if !c.unblockable && !contains(local.business_connector_ids, c.id)])
# }
#
# resource "powerplatform_data_loss_prevention_policy" "baseline" {
#   display_name                      = "Baseline - all environments"
#   default_connectors_classification = "Blocked"
#   environment_type                  = "AllEnvironments"
#   environments                      = []
#   business_connectors               = local.business_connectors
#   non_business_connectors           = local.non_business_connectors
#   blocked_connectors                = local.blocked_connectors
#   custom_connectors_patterns = toset([
#     { order = 1, host_url_pattern = "https://*.lowcoderev.ai", data_group = "Business" },
#     { order = 2, host_url_pattern = "*", data_group = "Blocked" },
#   ])
# }
