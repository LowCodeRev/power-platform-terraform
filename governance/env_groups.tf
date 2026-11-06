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

# Rules applied to every environment in the R+D group (today: the LowCodeRev developer environment).
# These are the Managed Environments settings; an environment in a group takes its settings from here,
# not from a powerplatform_managed_environment resource.
resource "powerplatform_environment_group_rule_set" "rnd" {
  environment_group_id = powerplatform_environment_group.rnd.id

  rules = {
    # Apps can be shared with individuals and groups, but not with "everyone" style security groups,
    # and not with more than 20 people at a time. Keeps R+D prototypes from quietly becoming production.
    sharing_controls = {
      share_mode      = "exclude sharing with security groups"
      share_max_limit = 20
    }

    # Weekly usage digest for the environment admins.
    usage_insights = {
      insights_enabled = true
    }

    # Run Solution Checker on every solution import; warn rather than block while the team's standards settle.
    # Flip to "block" once the deterministic checks in the solution pipeline are trusted.
    solution_checker_enforcement = {
      solution_checker_mode = "warn"
      send_emails_enabled   = true
    }

    # R+D data is disposable; keep the shortest retention.
    backup_retention = {
      period_in_days = 7
    }
  }
}
