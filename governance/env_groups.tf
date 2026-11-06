# Environment groups and their rule sets.
# The Microsoft-managed "Default Environment Group" is owned by the platform and is not managed here.

resource "powerplatform_environment_group" "rnd" {
  display_name = "Low Code Rev R+D"
  description  = "LowCodeRev Research and Development group"
}

# Every personal developer environment (PDE) provisioned from environments/pde-requests lands here.
resource "powerplatform_environment_group" "pde" {
  display_name = "Personal Developer Environments"
  description  = "Requested through the ITSM portal and provisioned from the power-platform-terraform repository. One per maker."
}

output "environment_group_ids" {
  description = "Consumed by the environments root through terraform_remote_state."
  value = {
    rnd = powerplatform_environment_group.rnd.id
    pde = powerplatform_environment_group.pde.id
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

# Personal developer environments are for one maker's own work. Sharing is tightly capped so a PDE cannot
# become a de facto team environment; anything worth sharing moves to a project environment via a solution.
resource "powerplatform_environment_group_rule_set" "pde" {
  environment_group_id = powerplatform_environment_group.pde.id

  rules = {
    sharing_controls = {
      share_mode      = "exclude sharing with security groups"
      share_max_limit = 5
    }

    usage_insights = {
      insights_enabled = true
    }

    solution_checker_enforcement = {
      solution_checker_mode = "warn"
      send_emails_enabled   = true
    }

    backup_retention = {
      period_in_days = 7
    }
  }
}
