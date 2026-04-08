# ---------------------------------------------------------------------------
# Required
# ---------------------------------------------------------------------------

variable "team_name" {
  description = "Short team name used to name the resource group and key vault (e.g. 'compms'). Will be prefixed with 'dg-'. Must be lowercase letters, numbers, and hyphens only."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.team_name))
    error_message = "team_name must be lowercase letters, numbers, and hyphens only."
  }
}

# ---------------------------------------------------------------------------
# Optional — sensible defaults for all teams
# ---------------------------------------------------------------------------

variable "location" {
  description = "Azure region for the resource group and key vault."
  type        = string
  default     = "centralus"
}

variable "soft_delete_retention_days" {
  description = <<-EOT
    Number of days soft-deleted secrets and certificates are retained before
    they can be purged. Min 7, max 90.
    DR note: with purge_protection enabled, a deleted vault cannot be recreated
    with the same name until this retention period expires or the vault is
    manually purged by an authorized identity.
  EOT
  type        = number
  default     = 90

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "soft_delete_retention_days must be between 7 and 90."
  }
}

variable "purge_protection_enabled" {
  description = "Prevent permanent deletion of the vault and its objects during the soft delete retention period. Recommended for production."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Access — who can read secrets from this vault
# ---------------------------------------------------------------------------

variable "secret_readers" {
  description = <<-EOT
    List of Entra object IDs (users, groups, or service principals) that should
    be granted the Key Vault Secrets User role — read-only access to secret values.
    Typically the service principal or managed identity that your app runs as.
  EOT
  type        = list(string)
  default     = []
}

variable "secret_officers" {
  description = <<-EOT
    List of Entra object IDs granted the Key Vault Secrets Officer role —
    can create, update, and delete secrets. Typically the Terraform SP and
    the platform team. The Terraform caller is always granted this role automatically.
  EOT
  type        = list(string)
  default     = []
}

variable "certificate_users" {
  description = "List of Entra object IDs granted the Key Vault Certificate User role — read-only access to certificates."
  type        = list(string)
  default     = []
}

variable "certificate_officers" {
  description = "List of Entra object IDs granted the Key Vault Certificates Officer role — can create and manage certificates."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Metadata
# ---------------------------------------------------------------------------

variable "tags" {
  description = "Azure resource tags to apply to the resource group and key vault."
  type        = map(string)
  default     = {}
}
