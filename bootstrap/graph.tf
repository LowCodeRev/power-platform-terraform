# Microsoft Graph application permissions for the Terraform identity.
# Needed by the governance root to manage the PP-Makers security group (environment routing scope) and to
# resolve maker UPNs to object IDs. Granted as app-role assignments, which is the actual consent; no secret.

data "azuread_service_principal" "msgraph" {
  client_id = "00000003-0000-0000-c000-000000000000"
}

locals {
  graph_app_roles = [
    "Group.ReadWrite.All", # create PP-Makers and manage its membership
    "User.Read.All",       # look up makers by UPN
    # Read app launch events from the Purview audit log for the inactive asset scan. Read-only, but it
    # covers the whole tenant audit log, not just Power Platform; Graph has no narrower Power Apps scope.
    "AuditLogsQuery.Read.All",
  ]
}

resource "azuread_app_role_assignment" "graph" {
  for_each = toset(local.graph_app_roles)

  app_role_id         = data.azuread_service_principal.msgraph.app_role_ids[each.value]
  principal_object_id = azuread_service_principal.terraform.object_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
}
