variable "location" {
  description = "Azure region where all resources will be created."
  type        = string
}

variable "name_prefix" {
  description = "Project prefix applied to resource names."
  type        = string
  default     = "acmekv"
}

variable "resource_group_name" {
  description = "Optional custom name for the resource group. If not provided, will be generated as '{name_prefix}-rg'."
  type        = string
  default     = null
}

variable "domains" {
  description = "List of domains that should receive Let's Encrypt certificates."
  type        = list(string)

  validation {
    condition     = length(var.domains) > 0
    error_message = "Provide at least one domain for certificate issuance."
  }
}

variable "acme_email" {
  description = "Contact email passed to Let's Encrypt during ACME registration."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.acme_email))
    error_message = "acme_email must be a valid email address."
  }
}

variable "acme_environment" {
  description = "ACME environment selector, either prod or staging."
  type        = string
  default     = "staging"

  validation {
    condition     = contains(["prod", "production", "staging", "stag"], lower(var.acme_environment))
    error_message = "acme_environment must be prod/production or staging/stag."
  }
}

variable "log_to_file" {
  description = "When true, ACME containers also persist logs to the shared Azure File share."
  type        = bool
  default     = true
}

variable "serving_image" {
  description = "Container image that exposes the ACME HTTP-01 challenge endpoint."
  type        = string
  default     = "docker.io/bicisteadm/acme-kv-serving:1.0.0"
}

variable "renewer_image" {
  description = "Container image responsible for issuing and renewing certificates."
  type        = string
  default     = "docker.io/bicisteadm/acme-kv-renewer:1.0.0"
}

variable "renewal_schedule" {
  description = "Cron expression for automatic certificate renewal. Default: monthly on 1st at 2 AM. Set to null for manual trigger only."
  type        = string
  default     = "0 2 1 * *"
}

variable "pfx_password" {
  description = "Password that protects generated PFX bundles before upload to Azure Key Vault."
  type        = string
  sensitive   = true
}

variable "container_apps_subnet_id" {
  description = "Optional resource ID of a delegated subnet for the Container Apps Environment."
  type        = string
  default     = null
}

variable "log_analytics_workspace_id" {
  description = "Optional Log Analytics workspace ID used for Container Apps diagnostics. Leave null to keep logs in Azure Monitor only."
  type        = string
  default     = null
}

variable "key_vault_name" {
  description = "Name of the Key Vault where certificates will be uploaded by the renewer job."
  type        = string
}

variable "tags" {
  description = "Additional tags applied to every resource created by the module."
  type        = map(string)
  default     = {}
}
