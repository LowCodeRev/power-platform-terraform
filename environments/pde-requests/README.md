# PDE request records

One JSON file per personal developer environment, named `<TICKET>.json`. Files are written by the
`pde-request` GitHub workflow, never by hand. Deleting a file (through the same workflow with
`action=decommission`) destroys the environment on the next approved apply.

```json
{
  "ticket": "REQ-0001",
  "requester_upn": "someone@lowcoderev.ai",
  "requester_object_id": "00000000-0000-0000-0000-000000000000",
  "requester_name": "Someone Example",
  "display_name": "PDE - Someone Example",
  "justification": "Building a prototype for the Q1 intake form.",
  "requested_on": "2026-11-06",
  "approved_by": "approver@lowcoderev.ai",
  "environment_type": "Developer"
}
```

`environment_type` is `Developer` by default. `Sandbox` is the fallback when a Developer environment
cannot be created for the requester (no Developer Plan on the user, or a service-principal limitation);
a Sandbox consumes 1 GB of tenant Dataverse capacity and the requester is made System Administrator of it.
