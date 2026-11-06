# Personal developer environments (PDEs), one per request file in ./pde-requests.
#
# Lifecycle, end to end:
#   1. A maker raises a request in the ITSM portal. The portal (or an admin via "Run workflow") triggers the
#      pde-request GitHub workflow with the ticket details.
#   2. The workflow writes pde-requests/<TICKET>.json on a branch and opens a pull request. That file is the
#      record: who asked, who approved, when, and why.
#   3. The plan comment on the PR shows the environment that will be created. Merging and approving the apply
#      provisions it. The PR, the commit and the file are the audit trail.
#   4. Decommissioning is the reverse: the workflow (action=decommission) deletes the file and opens a PR whose
#      plan shows the environment being destroyed. Nothing is destroyed without that approval.
#
# PDEs are intentionally NOT protected with prevent_destroy; their whole point is to be disposable.

data "terraform_remote_state" "governance" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-tf-state"
    storage_account_name = "stlcrtfstatesouxcw"
    container_name       = "tfstate"
    key                  = "governance.tfstate"
    use_azuread_auth     = true
  }
}

locals {
  pde_request_files = fileset("${path.module}/pde-requests", "*.json")
  pde_requests = {
    for f in local.pde_request_files :
    trimsuffix(f, ".json") => jsondecode(file("${path.module}/pde-requests/${f}"))
  }
}

module "pde" {
  source   = "../modules/pde"
  for_each = local.pde_requests

  ticket              = each.value.ticket
  requester_upn       = each.value.requester_upn
  requester_object_id = each.value.requester_object_id
  requester_name      = each.value.requester_name
  display_name        = try(each.value.display_name, null)
  justification       = each.value.justification
  requested_on        = each.value.requested_on
  approved_by         = each.value.approved_by
  environment_type    = try(each.value.environment_type, "Developer")

  environment_group_id = data.terraform_remote_state.governance.outputs.environment_group_ids.pde
}

output "pdes" {
  description = "Provisioned personal developer environments keyed by ticket."
  value       = { for k, m in module.pde : k => m.environment }
}
