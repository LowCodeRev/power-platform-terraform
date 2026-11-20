output "environment" {
  description = "Identity and URL of the provisioned environment, plus the request metadata for the record."
  value = {
    id            = powerplatform_environment.this.id
    display_name  = powerplatform_environment.this.display_name
    type          = var.environment_type
    dataverse_url = try(powerplatform_environment.this.dataverse.url, null)
    ticket        = var.ticket
    requester     = var.requester_upn
    approved_by   = var.approved_by
    requested_on  = var.requested_on
  }
}
