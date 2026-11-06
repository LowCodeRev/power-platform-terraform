# Cross-tenant connection policy. Live state on import (2026-11-06): policy enabled with an empty allow list,
# which blocks all inbound and outbound cross-tenant connections. Add entries to allow specific tenants.

resource "powerplatform_tenant_isolation_policy" "this" {
  is_disabled     = false
  allowed_tenants = []

  lifecycle {
    prevent_destroy = true
  }
}
