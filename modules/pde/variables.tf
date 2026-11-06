variable "ticket" {
  description = "ITSM ticket ID the environment was requested under (e.g. REQ-0001), or ROUTED for environments created by environment routing."
  type        = string
  validation {
    condition     = can(regex("^([A-Z]+-[0-9]+|ROUTED)$", var.ticket))
    error_message = "ticket must look like REQ-0001, or be ROUTED."
  }
}

variable "requester_upn" {
  type = string
}

variable "requester_object_id" {
  description = "Entra object ID of the maker. Owner of a Developer environment; System Administrator of a Sandbox."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.requester_object_id))
    error_message = "requester_object_id must be a lowercase GUID."
  }
}

variable "requester_name" {
  type = string
}

variable "display_name" {
  description = "Environment display name. Defaults to 'PDE - <requester name>'. Adopted environments keep the name routing gave them."
  type        = string
  default     = null
}

variable "description" {
  description = "Environment description. Defaults to a sentence built from the request record."
  type        = string
  default     = null
}

variable "justification" {
  type = string
}

variable "requested_on" {
  description = "ISO date the request was raised, or the environment's creation date when adopted."
  type        = string
}

variable "approved_by" {
  description = "UPN of the ITSM approver, or 'environment-routing' when the approval was PP-Makers membership."
  type        = string
}

variable "environment_type" {
  description = "Developer (preferred, no capacity cost, owned by the maker) or Sandbox (fallback, 1 GB capacity, maker is System Administrator)."
  type        = string
  default     = "Developer"
  validation {
    condition     = contains(["Developer", "Sandbox"], var.environment_type)
    error_message = "environment_type must be Developer or Sandbox."
  }
}

variable "environment_group_id" {
  description = "Environment group every PDE joins; its rule set carries the Managed Environments settings."
  type        = string
}

variable "location" {
  type    = string
  default = "unitedstates"
}

variable "azure_region" {
  description = "Set only for adopted environments, to match what routing chose. Changing it forces replacement."
  type        = string
  default     = null
}

variable "cadence" {
  type    = string
  default = "Frequent"
}

variable "release_cycle" {
  type    = string
  default = null
}

variable "language_code" {
  type    = number
  default = 1033
}

variable "currency_code" {
  type    = string
  default = "USD"
}
