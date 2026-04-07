# ---------------------------------------------------------------------------
# Required
# ---------------------------------------------------------------------------

variable "app_name" {
  description = "Short name for the app. Will be prefixed with 'DG-' automatically (e.g. 'MyAPI' becomes 'DG-MyAPI')."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9 _-]*$", var.app_name))
    error_message = "app_name must start with a letter or number and contain only letters, numbers, spaces, hyphens, or underscores."
  }
}

# ---------------------------------------------------------------------------
# OAuth / OIDC Flow Configuration
# ---------------------------------------------------------------------------

variable "flow_type" {
  description = <<-EOT
    The OAuth 2.0 / OIDC flow this app uses. Controls which redirect URI and token settings are configured.
      - "web"             : Server-side web app (authorization code with client secret/cert)
      - "spa"             : Single-page app (authorization code with PKCE, no secret)
      - "daemon"          : Service / daemon (client credentials — no user interaction)
      - "mobile_desktop"  : Native / mobile client (public client flows)
  EOT
  type    = string
  default = "web"

  validation {
    condition     = contains(["web", "spa", "daemon", "mobile_desktop"], var.flow_type)
    error_message = "flow_type must be one of: web, spa, daemon, mobile_desktop."
  }
}

variable "redirect_uris" {
  description = "Redirect URIs for the app. Required for web and spa flows; not used for daemon."
  type        = list(string)
  default     = []
}

variable "logout_url" {
  description = "Front-channel logout URL. Used for web flows."
  type        = string
  default     = null
}

variable "access_token_issuance_enabled" {
  description = "Allow implicit access token issuance. Only enable for legacy apps that require it."
  type        = bool
  default     = false
}

variable "id_token_issuance_enabled" {
  description = "Allow implicit ID token issuance. Set true for OIDC implicit flows (not recommended for new apps)."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Client Secret
# ---------------------------------------------------------------------------

variable "client_secret_enabled" {
  description = "Whether to create a client secret. Recommended for web and daemon flows."
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
# Client Certificate
# ---------------------------------------------------------------------------

variable "client_certificate_enabled" {
  description = "Whether to upload a client certificate for authentication (preferred over secrets for production)."
  type        = bool
  default     = false
}

variable "client_certificate_value" {
  description = "Base64-encoded PEM or DER certificate value to upload. Required when client_certificate_enabled is true."
  type        = string
  default     = null
  sensitive   = true
}

variable "client_certificate_display_name" {
  description = "Display name for the client certificate."
  type        = string
  default     = "terraform-managed"
}

variable "client_certificate_expiry" {
  description = "Expiry date for the certificate in RFC3339 format (e.g. '2027-01-01T00:00:00Z'). Required when client_certificate_enabled is true."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# API Permissions (Microsoft Graph and other APIs)
# ---------------------------------------------------------------------------

variable "required_resource_access" {
  description = <<-EOT
    List of API permissions to request. Each entry maps to a resource app (e.g. Microsoft Graph).
    Example:
      [{
        resource_app_id = "00000003-0000-0000-c000-000000000000"  # Microsoft Graph
        resource_access = [
          { id = "<permission-guid>", type = "Scope" },   # Delegated
          { id = "<permission-guid>", type = "Role" }     # Application
        ]
      }]
    Note: This declares the permissions; admin consent must be granted separately.
  EOT
  type = list(object({
    resource_app_id = string
    resource_access = list(object({
      id   = string
      type = string
    }))
  }))
  default = []
}

# ---------------------------------------------------------------------------
# App Roles (roles this app exposes to other apps or users)
# ---------------------------------------------------------------------------

variable "app_roles" {
  description = <<-EOT
    App roles this application exposes. Each role needs a unique ID (use uuidv5 or a pre-generated GUID).
    Example:
      [{
        id                   = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
        display_name         = "Reader"
        description          = "Can read data"
        value                = "Reader"
        allowed_member_types = ["User", "Application"]
        enabled              = true
      }]
  EOT
  type = list(object({
    id                   = string
    display_name         = string
    description          = string
    value                = string
    allowed_member_types = list(string)
    enabled              = optional(bool, true)
  }))
  default = []
}

# ---------------------------------------------------------------------------
# Federated Identity Credentials (OIDC — no secrets needed)
# ---------------------------------------------------------------------------

variable "federated_credentials" {
  description = <<-EOT
    Federated identity credentials for workload identity federation (e.g. GitHub Actions, AKS).
    Allows external OIDC tokens to authenticate without a secret or certificate.
    Example for GitHub Actions:
      [{
        name        = "github-actions-main"
        issuer      = "https://token.actions.githubusercontent.com"
        subject     = "repo:my-org/my-repo:ref:refs/heads/main"
        description = "GitHub Actions on main branch"
        audiences   = ["api://AzureADTokenExchange"]
      }]
  EOT
  type = list(object({
    name        = string
    issuer      = string
    subject     = string
    description = optional(string, "")
    audiences   = optional(list(string), ["api://AzureADTokenExchange"])
  }))
  default = []
}

# ---------------------------------------------------------------------------
# Portal & Visibility
# ---------------------------------------------------------------------------

variable "feature_tags" {
  description = <<-EOT
    Controls how the app appears in the Entra portal and My Apps.
    - enterprise: Show in Enterprise Applications list (default false for app registrations)
    - hide:       Hide from My Apps and O365 launcher
  EOT
  type = object({
    enterprise = optional(bool, false)
    hide       = optional(bool, true)
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

variable "create_service_principal" {
  description = "Whether to create a service principal for this app registration. Set false if you only need the app registration object (e.g. for a pure API definition)."
  type        = bool
  default     = true
}
