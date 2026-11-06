# Registers the service principal as a Power Platform admin management application.
# Equivalent to `New-PowerAppManagementApp -ApplicationId <client_id>`.
# Must be applied by a human Power Platform administrator; a service principal cannot register itself.
# After this, the SPN is treated like a user holding the Power Platform Administrator role.

resource "powerplatform_admin_management_application" "terraform" {
  id = azuread_application.terraform.client_id

  depends_on = [azuread_service_principal.terraform]
}
