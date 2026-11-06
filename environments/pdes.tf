# Personal developer environments (PDEs), one per record in ./pde-requests.
#
# How an environment gets here:
#   Normal: a maker is added to PP-Makers (governance/makers.json, by PR). Environment routing creates their
#   developer environment inside the "Personal Developer Environments" group the first time they open a maker
#   portal. The nightly pde-adopt workflow finds it, writes pde-requests/routed-<id>.json with environment_id set,
#   and opens an auto-merging PR. The import block below brings it under management on the next apply.
#   Exception: an admin writes a record without environment_id (through pde-decommission's sibling inputs or by
#   hand in a PR) and Terraform creates the environment itself, Developer or Sandbox.
#
# How it leaves: pde-decommission removes the record and opens a PR whose plan shows the destroy. Nothing is
# destroyed without that approval. PDEs are intentionally NOT protected with prevent_destroy.

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
  # Records that point at an environment routing already created: adopt instead of create.
  pde_to_import = { for k, v in local.pde_requests : k => v if can(v.environment_id) }
}

import {
  for_each = local.pde_to_import
  to       = module.pde[each.key].powerplatform_environment.this
  id       = each.value.environment_id
}

module "pde" {
  source   = "../modules/pde"
  for_each = local.pde_requests

  ticket              = each.value.ticket
  requester_upn       = each.value.requester_upn
  requester_object_id = each.value.requester_object_id
  requester_name      = each.value.requester_name
  display_name        = try(each.value.display_name, null)
  description         = try(each.value.description, null)
  justification       = each.value.justification
  requested_on        = each.value.requested_on
  approved_by         = each.value.approved_by
  environment_type    = try(each.value.environment_type, "Developer")
  location            = try(each.value.location, "unitedstates")
  azure_region        = try(each.value.azure_region, null)
  cadence             = try(each.value.cadence, "Frequent")
  release_cycle       = try(each.value.release_cycle, null)
  language_code       = try(each.value.language_code, 1033)
  currency_code       = try(each.value.currency_code, "USD")

  environment_group_id = data.terraform_remote_state.governance.outputs.environment_group_ids.pde
}

output "pdes" {
  description = "Managed personal developer environments keyed by record name."
  value       = { for k, m in module.pde : k => m.environment }
}
