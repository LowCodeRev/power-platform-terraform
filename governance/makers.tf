# Who may build.
#
# Membership of the PP-Makers security group is the approval for a personal developer environment. Environment
# routing (tenant_settings.tf) is scoped to this group: a member who opens Power Apps, Power Automate or Copilot
# Studio gets a managed developer environment created for them inside the "Personal Developer Environments" group.
# Everyone else lands in the default environment, where the restricted DLP policy applies.
#
# The ITSM request's only output is a pull request adding a UPN to makers.json. The reviewer on that PR is the
# approval record. Removing a UPN revokes routing for new environments; it does not delete an existing one
# (decommission that with the pde-decommission workflow).

locals {
  makers = jsondecode(file("${path.module}/makers.json")).members
}

data "azuread_user" "makers" {
  for_each            = toset(local.makers)
  user_principal_name = each.value
}

resource "azuread_group" "pp_makers" {
  display_name     = "PP-Makers"
  description      = "Approved Power Platform makers. Membership is managed from the power-platform-terraform repository (governance/makers.json) and drives environment routing."
  security_enabled = true
  mail_enabled     = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "azuread_group_member" "makers" {
  for_each = data.azuread_user.makers

  group_object_id  = azuread_group.pp_makers.object_id
  member_object_id = each.value.object_id
}

output "pp_makers_group_id" {
  value = azuread_group.pp_makers.object_id
}
