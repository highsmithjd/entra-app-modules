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
# Key Vault
# ---------------------------------------------------------------------------

variable "create_key_vault" {
  description = <<-EOT
    When true, creates a dedicated Azure Key Vault for this app.
    The vault is named 'kv-dg-<app_name>'. Client secrets are automatically
    written to the vault when client_secret_enabled is also true.
    The vault is destroyed when the app is destroyed.
  EOT
  type        = bool
  default     = false
}

variable "key_vault_resource_group_name" {
  description = <<-EOT
    Name of the resource group to place the Key Vault in. When set, the module
    uses this existing resource group instead of creating one. Recommended: use a
    shared resource group per app (e.g. 'rg-dg-compms') so dev and prod vaults
    land in the same group and are destroyed together when the app is retired.
    When null, a resource group named 'rg-dg-<app_name>' is created automatically.
  EOT
  type        = string
  default     = null
}

variable "key_vault_location" {
  description = "Azure region for the Key Vault and resource group. Only used when create_key_vault is true."
  type        = string
  default     = "centralus"
}

variable "key_vault_soft_delete_retention_days" {
  description = "Days to retain soft-deleted vault objects (7-90). Only used when create_key_vault is true."
  type        = number
  default     = 90

  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "key_vault_soft_delete_retention_days must be between 7 and 90."
  }
}

variable "key_vault_purge_protection_enabled" {
  description = "Prevent permanent deletion of the vault during the soft delete retention period. Only used when create_key_vault is true."
  type        = bool
  default     = true
}

variable "key_vault_secret_readers" {
  description = "List of Entra object IDs granted Key Vault Secrets User (read-only) on the app vault. Only used when create_key_vault is true."
  type        = list(string)
  default     = []
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
# Key Vault-managed certificate
# ---------------------------------------------------------------------------

variable "create_key_vault_certificate" {
  description = <<-EOT
    When true, generates a self-signed RSA certificate in the app's Key Vault and
    uploads the public key to Entra as an application credential. The PFX (including
    private key) can be exported from Key Vault and sent to the consuming application.
    Requires create_key_vault = true. Cannot be combined with client_certificate_enabled.
  EOT
  type    = bool
  default = false
}

variable "key_vault_certificate_slots" {
  description = <<-EOT
    Named slots for Key Vault-managed certificates. Each slot creates an independent
    certificate in Key Vault and registers its public key in Entra. All slots are
    valid simultaneously, enabling zero-downtime rotation.

    Normal operation (single cert):
      key_vault_certificate_slots = ["primary"]

    During rotation (both certs active — give the vendor the new cert first):
      key_vault_certificate_slots = ["primary", "secondary"]

    After vendor confirms the new cert works (remove the old one):
      key_vault_certificate_slots = ["secondary"]

    Slot names become part of the Key Vault certificate name:
      "primary"   → <app_slug>-cert-primary
      "secondary" → <app_slug>-cert-secondary

    Requires create_key_vault_certificate = true.
  EOT
  type    = list(string)
  default = ["primary"]

  validation {
    condition     = length(var.key_vault_certificate_slots) > 0
    error_message = "key_vault_certificate_slots must have at least one entry."
  }
}

variable "key_vault_certificate_subject" {
  description = "Subject DN for the generated certificate. Defaults to 'CN=DG-<app_name>'."
  type        = string
  default     = null
}

variable "key_vault_certificate_validity_months" {
  description = "Validity period for the generated certificate in months."
  type        = number
  default     = 12

  validation {
    condition     = var.key_vault_certificate_validity_months > 0 && var.key_vault_certificate_validity_months <= 120
    error_message = "key_vault_certificate_validity_months must be between 1 and 120."
  }
}

variable "key_vault_certificate_key_size" {
  description = "RSA key size for the generated certificate. Must be 2048 or 4096."
  type        = number
  default     = 2048

  validation {
    condition     = contains([2048, 4096], var.key_vault_certificate_key_size)
    error_message = "key_vault_certificate_key_size must be 2048 or 4096."
  }
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

variable "notification_email_addresses" {
  description = "List of email addresses to notify when a Key Vault certificate or client secret is near expiry."
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


variable "create_service_principal" {
  description = "Whether to create a service principal for this app registration. Set false if you only need the app registration object (e.g. for a pure API definition)."
  type        = bool
  default     = true
}
