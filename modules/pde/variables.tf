variable "ticket" {
  description = "ITSM ticket ID the environment was requested under, e.g. REQ-0001."
  type        = string
  validation {
    condition     = can(regex("^[A-Z]+-[0-9]+$", var.ticket))
    error_message = "ticket must look like REQ-0001."
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
  description = "Environment display name. Defaults to 'PDE - <requester name>'."
  type        = string
  default     = null
}

variable "justification" {
  type = string
}

variable "requested_on" {
  description = "ISO date the request was raised."
  type        = string
}

variable "approved_by" {
  description = "UPN of the ITSM approver."
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

variable "language_code" {
  type    = number
  default = 1033
}

variable "currency_code" {
  type    = string
  default = "USD"
}
