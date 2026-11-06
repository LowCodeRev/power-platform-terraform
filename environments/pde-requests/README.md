# PDE records

One JSON file per personal developer environment. Files are written by the `pde-adopt` workflow (environments
created by routing) and removed by the `pde-decommission` workflow. Hand-written records are for exceptions
only and go through a normal PR.

Adopted (the usual case; `environment_id` present means import, not create):

```json
{
  "ticket": "ROUTED",
  "source": "environment-routing",
  "environment_id": "11111111-2222-3333-4444-555555555555",
  "requester_upn": "tony@lowcoderev.ai",
  "requester_object_id": "c86297e4-4aca-4bbe-b9f0-4f476e7d8b51",
  "requester_name": "Tony Stark",
  "display_name": "Tony Stark's Environment",
  "justification": "Personal developer environment created by environment routing (PP-Makers membership).",
  "requested_on": "2026-11-07",
  "approved_by": "environment-routing",
  "environment_type": "Developer",
  "location": "unitedstates",
  "azure_region": "westus",
  "cadence": "Frequent",
  "release_cycle": "Standard"
}
```

Exception (no `environment_id`: Terraform creates it; `Sandbox` is the type the service principal can create):

```json
{
  "ticket": "REQ-0001",
  "requester_upn": "someone@lowcoderev.ai",
  "requester_object_id": "00000000-0000-0000-0000-000000000000",
  "requester_name": "Someone Example",
  "justification": "Needs a Sandbox because the work requires a security-group-restricted environment.",
  "requested_on": "2026-11-06",
  "approved_by": "approver@lowcoderev.ai",
  "environment_type": "Sandbox"
}
```
