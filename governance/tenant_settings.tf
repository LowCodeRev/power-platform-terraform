# Tenant-wide settings. Imported from the live tenant on 2026-11-06. Change a value here, open a PR, and the plan
# shows exactly what will flip.
#
# Policy (2026-11-06): environment creation of every kind (production, sandbox, trial, developer) and Power Pages
# site creation are admin-only. Makers request a personal developer environment through the ITSM portal and the
# request is provisioned from this repository (see environments/pde-requests). Environment routing stays off for
# the same reason: routing would auto-create developer environments on first use, bypassing the request process.
# Connections cannot be shared with "everyone".
#
# Attributes deprecated for provider v5 (disable_nps_comments_reachout, disable_survey_feedback,
# enable_open_ai_bot_publishing, disable_create_from_image, disable_create_from_figma) are intentionally unset.

resource "powerplatform_tenant_settings" "this" {
  walk_me_opt_out                                       = false
  disable_support_tickets_visible_by_all_users          = true
  disable_trial_environment_creation_by_non_admin_users = true
  disable_capacity_allocation_by_environment_admins     = false
  disable_environment_creation_by_non_admin_users       = true
  disable_portals_creation_by_non_admin_users           = true
  disable_newsletter_sendout                            = false

  power_platform = {
    search = {
      disable_docs_search       = true
      disable_community_search  = false
      disable_bing_video_search = false
    }

    teams_integration = {
      share_with_colleagues_user_limit = 10000
    }

    power_apps = {
      disable_share_with_everyone              = true
      enable_guests_to_make                    = false
      disable_maker_match                      = false
      disable_unused_license_assignment        = false
      disable_connection_sharing_with_everyone = true
    }

    power_automate = {
      disable_copilot = false
    }

    environments = {
      disable_preferred_data_location_for_teams_environment = false
    }

    governance = {
      disable_admin_digest                                      = false
      disable_developer_environment_creation_by_non_admin_users = true
      enable_default_environment_routing                        = false
      environment_routing_all_makers                            = false

      policy = {
        enable_desktop_flow_data_policy_management = false
      }
    }

    licensing = {
      disable_billing_policy_creation_by_non_admin_users    = false
      enable_tenant_capacity_report_for_environment_admins  = false
      storage_capacity_consumption_warning_threshold        = 85
      enable_tenant_licensing_report_for_environment_admins = false
      disable_use_of_unassigned_ai_builder_credits          = false
    }

    champions = {
      disable_champions_invitation_reachout    = false
      disable_skills_match_invitation_reachout = false
    }

    intelligence = {
      disable_copilot = false
    }

    model_experimentation = {
      enable_model_data_sharing = false
      disable_data_logging      = false
    }

    catalog_settings = {
      power_catalog_audience_setting = "All"
    }

    user_management_settings = {
      enable_delete_disabled_user_in_all_environments = false
    }
  }

  lifecycle {
    # Destroy semantics for tenant settings are undocumented. Never let Terraform remove this resource.
    prevent_destroy = true
  }
}
