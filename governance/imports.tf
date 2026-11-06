# Pre-existing tenant-level resources adopted into state on first apply.
# These blocks are harmless once imported (Terraform ignores an import whose target is already in state)
# but can be deleted after the first successful apply.

locals {
  tenant_id = "19a0c33f-bf94-4ef0-b894-539351f7aa80"
}

import {
  to = powerplatform_tenant_settings.this
  id = local.tenant_id
}

import {
  to = powerplatform_tenant_isolation_policy.this
  id = local.tenant_id
}

# "Low Code Rev R+D" environment group, created 2026-08-05 in the admin center.
# The Microsoft-managed "Default Environment Group" (84659ecc-...) is deliberately NOT imported.
import {
  to = powerplatform_environment_group.rnd
  id = "a11f3e78-0fb1-40a6-a2d5-9fc369765c2a"
}
