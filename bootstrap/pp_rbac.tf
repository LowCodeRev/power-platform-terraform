# Power Platform RBAC (preview). The admin management application registration (pp_admin.tf) covers the
# legacy BAP admin endpoints, but api.powerplatform.com and the tenant-scoped governance host authorize
# service principals through Power Platform RBAC role assignments. Without one the service principal gets a
# bare 403 on every governance call (environment group rule sets, rule-based policies, environment groups).
#
# Contributor: manage and read all resources, but cannot change role assignments. That keeps the robot
# from widening its own grant; role assignments stay a human (Global Admin) action in this root.
resource "powerplatform_rbac_role_assignment" "terraform_contributor" {
  scope_type           = "tenant"
  principal_id         = azuread_service_principal.terraform.object_id
  principal_type       = "ApplicationUser"
  role_definition_name = "Power Platform Contributor"

  depends_on = [powerplatform_admin_management_application.terraform]
}
