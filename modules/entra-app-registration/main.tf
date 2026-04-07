locals {
  full_name       = "DG-${var.app_name}"
  secret_end_date = timeadd(time_static.now.rfc3339, "${var.client_secret_expiry_days * 24}h")

  # Derive which redirect URI block to populate based on flow type
  is_web            = var.flow_type == "web"
  is_spa            = var.flow_type == "spa"
  is_mobile_desktop = var.flow_type == "mobile_desktop"
  # daemon flow has no redirect URIs
}

resource "time_static" "now" {}

# ---------------------------------------------------------------------------
# Application registration
# ---------------------------------------------------------------------------

data "azuread_client_config" "current" {}

resource "azuread_application" "this" {
  display_name     = local.full_name
  sign_in_audience = "AzureADMyOrg"
  notes            = var.notes

  owners = distinct(concat(
    [data.azuread_client_config.current.object_id],
    var.owners
  ))

  # Web / server-side app
  dynamic "web" {
    for_each = local.is_web ? [1] : []
    content {
      redirect_uris = var.redirect_uris
      logout_url    = var.logout_url

      implicit_grant {
        access_token_issuance_enabled = var.access_token_issuance_enabled
        id_token_issuance_enabled     = var.id_token_issuance_enabled
      }
    }
  }

  # Single-page application
  dynamic "single_page_application" {
    for_each = local.is_spa ? [1] : []
    content {
      redirect_uris = var.redirect_uris
    }
  }

  # Native / mobile / desktop (public client)
  dynamic "public_client" {
    for_each = local.is_mobile_desktop ? [1] : []
    content {
      redirect_uris = var.redirect_uris
    }
  }

  # App roles this app exposes
  dynamic "app_role" {
    for_each = var.app_roles
    content {
      id                   = app_role.value.id
      display_name         = app_role.value.display_name
      description          = app_role.value.description
      value                = app_role.value.value
      allowed_member_types = app_role.value.allowed_member_types
      enabled              = app_role.value.enabled
    }
  }

  # Permissions this app requests from other APIs
  dynamic "required_resource_access" {
    for_each = var.required_resource_access
    content {
      resource_app_id = required_resource_access.value.resource_app_id

      dynamic "resource_access" {
        for_each = required_resource_access.value.resource_access
        content {
          id   = resource_access.value.id
          type = resource_access.value.type
        }
      }
    }
  }

  # Feature tags control portal visibility
  feature_tags {
    enterprise = var.feature_tags.enterprise
    hide       = var.feature_tags.hide
  }

  lifecycle {
    ignore_changes = [display_name]
  }
}

# ---------------------------------------------------------------------------
# Service principal
# ---------------------------------------------------------------------------

resource "azuread_service_principal" "this" {
  count = var.create_service_principal ? 1 : 0

  client_id = azuread_application.this.client_id
  tags      = var.tags

  feature_tags {
    enterprise = var.feature_tags.enterprise
    hide       = var.feature_tags.hide
  }

  owners = distinct(concat(
    [data.azuread_client_config.current.object_id],
    var.owners
  ))
}

# ---------------------------------------------------------------------------
# Client secret
# ---------------------------------------------------------------------------

resource "azuread_application_password" "this" {
  count = var.client_secret_enabled ? 1 : 0

  application_id = azuread_application.this.id
  display_name   = var.client_secret_display_name
  end_date       = local.secret_end_date
}

# ---------------------------------------------------------------------------
# Client certificate
# ---------------------------------------------------------------------------

resource "azuread_application_certificate" "this" {
  count = var.client_certificate_enabled ? 1 : 0

  application_id = azuread_application.this.id
  type           = "AsymmetricX509Cert"
  value          = var.client_certificate_value
  end_date       = var.client_certificate_expiry
}

# ---------------------------------------------------------------------------
# Federated identity credentials (workload identity / OIDC)
# ---------------------------------------------------------------------------

resource "azuread_application_federated_identity_credential" "this" {
  for_each = {
    for fc in var.federated_credentials :
    fc.name => fc
  }

  application_id = azuread_application.this.id
  display_name   = each.value.name
  description    = each.value.description
  issuer         = each.value.issuer
  subject        = each.value.subject
  audiences      = each.value.audiences
}
