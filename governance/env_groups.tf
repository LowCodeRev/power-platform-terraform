# Environment groups and their rule sets.
# The Microsoft-managed "Default Environment Group" is owned by the platform and is not managed here.

resource "powerplatform_environment_group" "rnd" {
  display_name = "Low Code Rev R+D"
  description  = "LowCodeRev Research and Development group"
}

output "environment_group_ids" {
  description = "Consumed by the environments root via remote state or copied by hand."
  value = {
    rnd = powerplatform_environment_group.rnd.id
  }
}

# Rule set for the R+D group. No rules exist today; uncomment and tune in Phase 4.
# resource "powerplatform_environment_group_rule_set" "rnd" {
#   environment_group_id = powerplatform_environment_group.rnd.id
#   rules = {
#     sharing_controls = {
#       share_mode      = "exclude sharing with security groups"
#       share_max_limit = 20
#     }
#     usage_insights = {
#       insights_enabled = true
#     }
#     solution_checker_enforcement = {
#       solution_checker_mode = "warn"
#       send_emails_enabled   = true
#     }
#     backup_retention = {
#       period_in_days = 7
#     }
#   }
# }
