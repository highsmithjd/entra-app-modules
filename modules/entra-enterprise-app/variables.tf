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
# SAML Claims
# ---------------------------------------------------------------------------

variable "saml_group_claim" {
  description = <<-EOT
    Configure the groups claim emitted in the SAML token.

    scope — which groups to include:
      "ApplicationGroup"  Groups assigned to this application only (recommended)
      "SecurityGroup"     All security groups the user is a member of
      "DirectoryRole"     Azure AD directory roles
      "All"               All groups and directory roles
      "None"              No group claim

    format — the value emitted for each group (additional_properties):
      []                                        Object ID / GUID (default)
      ["sam_account_name"]                      sAMAccountName (on-prem synced)
      ["netbios_domain_and_sam_account_name"]   NETBIOS\sAMAccountName (on-prem)
      ["dns_domain_and_sam_account_name"]       DNS\sAMAccountName (on-prem)
      ["cloud_displayname"]                     Display name (cloud-only groups)
  EOT
  type = object({
    enabled = optional(bool, false)
    scope   = optional(string, "ApplicationGroup")
    format  = optional(list(string), [])
  })
  default = {}

  validation {
    condition = contains(
      ["None", "SecurityGroup", "DirectoryRole", "ApplicationGroup", "All"],
      var.saml_group_claim.scope
    )
    error_message = "saml_group_claim.scope must be one of: None, SecurityGroup, DirectoryRole, ApplicationGroup, All."
  }
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

variable "notification_email_addresses" {
  description = "List of email addresses to notify when the SAML signing certificate is near expiry."
  type        = list(string)
  default     = []
}

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

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

variable "use_powershell_provisioner" {
  description = "Deprecated — the module now auto-detects Windows. This variable is accepted but ignored."
  type        = bool
  default     = false
}
