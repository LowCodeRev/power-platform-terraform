output "client_id" {
  description = "Client ID of the Terraform CI app registration. Set as PP_CLIENT_ID in GitHub repository variables."
  value       = azuread_application.terraform.client_id
}

output "service_principal_object_id" {
  value = azuread_service_principal.terraform.object_id
}

output "tenant_id" {
  value = var.tenant_id
}

output "subscription_id" {
  value = var.subscription_id
}

output "state_storage_account_name" {
  description = "Set as TF_STATE_STORAGE_ACCOUNT in GitHub repository variables."
  value       = azurerm_storage_account.state.name
}

output "state_resource_group_name" {
  value = azurerm_resource_group.state.name
}

output "state_container_name" {
  value = azurerm_storage_container.state.name
}

output "backend_hcl" {
  description = "Partial backend config. Save as backend.hcl in each root module and run `terraform init -backend-config=backend.hcl`."
  value       = <<-EOT
    resource_group_name  = "${azurerm_resource_group.state.name}"
    storage_account_name = "${azurerm_storage_account.state.name}"
    container_name       = "${azurerm_storage_container.state.name}"
    use_azuread_auth     = true
  EOT
}
