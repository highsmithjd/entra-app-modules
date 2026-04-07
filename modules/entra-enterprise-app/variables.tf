# ---------------------------------------------------------------------------
# Required
# ---------------------------------------------------------------------------

variable "app_name" {
  description = "Short name for the app. Will be prefixed with 'DG-' automatically (e.g. 'MyApp' becomes 'DG-MyApp')."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9 _-]*$", var.app_name))
    error_message = "app_name must start with a letter or number and contain only letters, numbers, spaces, hyphens, or underscores."
  }
}

variable "saml_metadata_url" {
  description = "URL of the SAML metadata document provided by the service provider, OR set to null and supply saml_* variables manually."
  type        = string
  default     = null
}

variable "saml_identifier_uris" {
  description = "List of SAML entity IDs / identifier URIs (Audience URIs) for the service provider."
  type        = list(string)
  default     = []
}

variable "saml_reply_urls" {
  description = "List of Assertion Consumer Service (ACS) URLs the IdP will POST SAML responses to."
  type        = list(string)
  default     = []
}

variable "saml_logout_url" {
  description = "Single logout URL for the service provider. Optional."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# SAML Signing Certificate
# ---------------------------------------------------------------------------

variable "saml_signing_certificate_enabled" {
  description = "Whether to create a self-signed SAML token signing certificate managed by Entra."
  type        = bool
  default     = true
}

variable "saml_certificate_display_name" {
  description = "Display name for the SAML signing certificate. Defaults to 'CN=<app_name>'."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Client Secret (uncommon for SAML but occasionally needed for back-channel calls)
# ---------------------------------------------------------------------------

variable "client_secret_enabled" {
  description = "Whether to create a client secret for back-channel API access. Not typical for pure SAML flows."
  type        = bool
  default     = false
}

variable "client_secret_display_name" {
  description = "Display name for the client secret."
  type        = string
  default     = "terraform-managed"
}

variable "client_secret_expiry_days" {
  description = "Number of days until the client secret expires. Max 730 (2 years)."
  type        = number
  default     = 365

  validation {
    condition     = var.client_secret_expiry_days > 0 && var.client_secret_expiry_days <= 730
    error_message = "client_secret_expiry_days must be between 1 and 730."
  }
}

# ---------------------------------------------------------------------------
# App Role Assignments (who can access this app)
# ---------------------------------------------------------------------------

variable "app_role_assignments" {
  description = <<-EOT
    List of user or group object IDs to assign to the app's default access role.
    Each entry is a map with:
      - principal_object_id: The object ID of the user, group, or service principal
      - principal_type: "User", "Group", or "ServicePrincipal"
  EOT
  type = list(object({
    principal_object_id = string
    principal_type      = string
  }))
  default = []

  validation {
    condition = alltrue([
      for a in var.app_role_assignments :
      contains(["User", "Group", "ServicePrincipal"], a.principal_type)
    ])
    error_message = "principal_type must be one of: User, Group, ServicePrincipal."
  }
}

# ---------------------------------------------------------------------------
# Portal & Visibility
# ---------------------------------------------------------------------------

variable "feature_tags" {
  description = <<-EOT
    Controls how the app appears in the Entra portal and My Apps.
    - enterprise: Show in Enterprise Applications list (default true)
    - gallery:    Show in the app gallery (default false)
    - hide:       Hide from My Apps and O365 launcher (default false)
  EOT
  type = object({
    enterprise = optional(bool, true)
    gallery    = optional(bool, false)
    hide       = optional(bool, false)
  })
  default = {}
}

# ---------------------------------------------------------------------------
# Metadata / Documentation
# ---------------------------------------------------------------------------

variable "notes" {
  description = "Free-text notes stored on the application object. Useful for owner, team, ticket references, etc."
  type        = string
  default     = null
}

variable "owners" {
  description = "List of Entra object IDs to set as application owners. The caller's identity is always added automatically."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Flat list of string tags on the service principal (e.g. ['platform-team', 'production']). Not key-value pairs — Entra does not support those."
  type        = list(string)
  default     = []
}
