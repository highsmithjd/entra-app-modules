locals {
  full_name            = "DG-${var.app_name}"
  cert_display_name    = coalesce(var.saml_certificate_display_name, "CN=${local.full_name}")
  secret_end_date      = timeadd(time_static.now.rfc3339, "${var.client_secret_expiry_days * 24}h")
}

# Used to calculate a stable expiry date at apply time without perpetual drift
resource "time_static" "now" {}

# ---------------------------------------------------------------------------
# Application registration
# ---------------------------------------------------------------------------

data "azuread_client_config" "current" {}

resource "azuread_application" "this" {
  display_name     = local.full_name
  identifier_uris  = var.saml_identifier_uris
  sign_in_audience = "AzureADMyOrg"
  notes            = var.notes

  # Caller is always an owner; additional owners are appended
  owners = distinct(concat(
    [data.azuread_client_config.current.object_id],
    var.owners
  ))

  # SAML configuration lives under the web block
  web {
    redirect_uris = var.saml_reply_urls

    implicit_grant {
      access_token_issuance_enabled = false
      id_token_issuance_enabled     = false
    }
  }

  # Mark this as a SAML application
  feature_tags {
    enterprise = var.feature_tags.enterprise
    gallery    = var.feature_tags.gallery
    hide       = var.feature_tags.hide
    custom_single_sign_on = true
  }

  lifecycle {
    # Prevent accidental rename which would break SSO
    ignore_changes = [display_name]
  }
}

# ---------------------------------------------------------------------------
# Service principal (the instance of the app in your tenant)
# ---------------------------------------------------------------------------

resource "azuread_service_principal" "this" {
  client_id                    = azuread_application.this.client_id
  app_role_assignment_required = length(var.app_role_assignments) > 0
  preferred_single_sign_on_mode = "saml"
  notification_email_addresses = []

  feature_tags {
    enterprise            = var.feature_tags.enterprise
    gallery               = var.feature_tags.gallery
    hide                  = var.feature_tags.hide
    custom_single_sign_on = true
  }

  tags = var.tags

  owners = distinct(concat(
    [data.azuread_client_config.current.object_id],
    var.owners
  ))
}

# ---------------------------------------------------------------------------
# SAML logout URL (set via service principal, not application)
# ---------------------------------------------------------------------------

resource "azuread_service_principal_claims_mapping_policy_assignment" "logout" {
  count = var.saml_logout_url != null ? 1 : 0

  # The logout URL is set via the SLO URL on the SAML config; this is a placeholder
  # for where you'd attach a claims mapping policy if needed.
  # Use azuread_service_principal directly for slo_url when provider supports it.
  claims_mapping_policy_id = ""
  service_principal_id     = azuread_service_principal.this.id

  lifecycle {
    ignore_changes = [claims_mapping_policy_id]
  }
}

# ---------------------------------------------------------------------------
# SAML signing certificate (self-signed, managed by Entra)
# ---------------------------------------------------------------------------

resource "azuread_service_principal_token_signing_certificate" "this" {
  count = var.saml_signing_certificate_enabled ? 1 : 0

  service_principal_id = azuread_service_principal.this.id
  display_name         = local.cert_display_name
}

# ---------------------------------------------------------------------------
# Client secret (optional, uncommon for SAML)
# ---------------------------------------------------------------------------

resource "azuread_application_password" "this" {
  count = var.client_secret_enabled ? 1 : 0

  application_id = azuread_application.this.id
  display_name   = var.client_secret_display_name
  end_date       = local.secret_end_date
}

# ---------------------------------------------------------------------------
# App role assignments
# ---------------------------------------------------------------------------

resource "azuread_app_role_assignment" "this" {
  for_each = {
    for a in var.app_role_assignments :
    a.principal_object_id => a
  }

  app_role_id         = "00000000-0000-0000-0000-000000000000" # Default access role
  principal_object_id = each.value.principal_object_id
  resource_object_id  = azuread_service_principal.this.object_id
}
