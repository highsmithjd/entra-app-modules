locals {
  full_name         = "DG-${var.app_name}"
  cert_display_name = coalesce(var.saml_certificate_display_name, "CN=${local.full_name}")
  secret_end_date   = timeadd(time_static.now.rfc3339, "${var.client_secret_expiry_days * 24}h")
  # Key Vault naming — lowercase, hyphens only, max 24 chars total
  # Budget: "kv-" (3) + slug (≤16) + "-" (1) + 4-char hex suffix = max 24
  app_slug   = substr(lower(replace(var.app_name, " ", "-")), 0, 16)
  vault_name = var.create_key_vault ? "kv-${local.app_slug}-${random_id.kv_suffix[0].hex}" : null

  # Use the provided resource group name or auto-generate one
  rg_name   = coalesce(var.key_vault_resource_group_name, "rg-dg-${local.app_slug}")
  create_rg = var.create_key_vault && var.key_vault_resource_group_name == null
}

# Used to calculate a stable expiry date at apply time without perpetual drift
resource "time_static" "now" {}

# ---------------------------------------------------------------------------
# Application registration
# ---------------------------------------------------------------------------

data "azuread_client_config" "current" {}

resource "azuread_application" "this" {
  display_name     = local.full_name
  sign_in_audience = "AzureADMyOrg"
  notes            = var.notes

  # Caller is always an owner; additional owners are appended
  owners = distinct(concat(
    [data.azuread_client_config.current.object_id],
    var.owners
  ))

  # Group claim scope — controls which groups appear in the SAML token
  group_membership_claims = var.saml_group_claim.enabled ? [var.saml_group_claim.scope] : null

  # SAML configuration lives under the web block
  web {
    redirect_uris = var.saml_reply_urls
    logout_url    = var.saml_logout_url

    implicit_grant {
      access_token_issuance_enabled = false
      id_token_issuance_enabled     = false
    }
  }

  # Add groups claim to the SAML token when enabled
  dynamic "optional_claims" {
    for_each = var.saml_group_claim.enabled ? [1] : []
    content {
      saml2_token {
        name                  = "groups"
        additional_properties = var.saml_group_claim.format
      }
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

# Patch identifier URIs after creation via a direct Graph API call.
# The Graph API rejects vendor-supplied entity IDs (e.g. urn:vendor:app or
# https://app.vendor.com) at creation time because they don't match a
# verified domain. A subsequent PATCH bypasses this — matching what the
# portal does internally.
#
# The destroy provisioner clears identifierUris before the service principal
# is deleted — Entra blocks SP deletion when non-verified URIs are present.
# depends_on includes the SP so this resource is destroyed first (reverse order).

resource "null_resource" "app_identifier_uris" {
  count = length(var.saml_identifier_uris) > 0 ? 1 : 0

  triggers = {
    object_id       = azuread_application.this.object_id
    identifier_uris = jsonencode(var.saml_identifier_uris)
  }

  provisioner "local-exec" {
    # Works locally (az login --service-principal already done) and in GitLab CI
    # (ARM_OIDC_TOKEN / ARM_CLIENT_ID / ARM_TENANT_ID set by the OIDC job config).
    command = <<-EOT
      set -e
      if ! az account show > /dev/null 2>&1; then
        az login --service-principal \
          --federated-token "$ARM_OIDC_TOKEN" \
          --username "$ARM_CLIENT_ID" \
          --tenant "$ARM_TENANT_ID" \
          --allow-no-subscriptions > /dev/null
      fi
      az rest --method PATCH \
        --url "https://graph.microsoft.com/v1.0/applications/${azuread_application.this.object_id}" \
        --body '{"identifierUris": ${jsonencode(var.saml_identifier_uris)}}'
    EOT
  }

  provisioner "local-exec" {
    when = destroy
    command = <<-EOT
      set -e
      if ! az account show > /dev/null 2>&1; then
        az login --service-principal \
          --federated-token "$ARM_OIDC_TOKEN" \
          --username "$ARM_CLIENT_ID" \
          --tenant "$ARM_TENANT_ID" \
          --allow-no-subscriptions > /dev/null
      fi
      az rest --method PATCH \
        --url "https://graph.microsoft.com/v1.0/applications/${self.triggers.object_id}" \
        --body '{"identifierUris": []}'
    EOT
  }

  # SP is included so this resource is destroyed before the SP (reverse dep order),
  # giving the destroy provisioner a chance to clear identifierUris first.
  depends_on = [azuread_application.this, azuread_service_principal.this]
}

# ---------------------------------------------------------------------------
# Service principal (the instance of the app in your tenant)
# ---------------------------------------------------------------------------

resource "azuread_service_principal" "this" {
  client_id                     = azuread_application.this.client_id
  app_role_assignment_required  = length(var.app_role_assignments) > 0
  preferred_single_sign_on_mode = "saml"
  notification_email_addresses  = var.notification_email_addresses

  feature_tags {
    enterprise            = var.feature_tags.enterprise
    gallery               = var.feature_tags.gallery
    hide                  = var.feature_tags.hide
    custom_single_sign_on = true
  }

  owners = distinct(concat(
    [data.azuread_client_config.current.object_id],
    var.owners
  ))
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
# Key Vault — optional, one per app, co-located with the app
# ---------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

resource "random_id" "kv_suffix" {
  count       = var.create_key_vault ? 1 : 0
  byte_length = 2 # produces a 4-char hex string
}

resource "azurerm_resource_group" "this" {
  count    = local.create_rg ? 1 : 0
  name     = local.rg_name
  location = var.key_vault_location

  tags = {
    managed-by = "terraform"
    app        = local.full_name
  }
}

resource "azurerm_key_vault" "this" {
  count               = var.create_key_vault ? 1 : 0
  name                = local.vault_name
  resource_group_name = local.create_rg ? azurerm_resource_group.this[0].name : local.rg_name
  location            = var.key_vault_location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled = true

  soft_delete_retention_days = var.key_vault_soft_delete_retention_days
  purge_protection_enabled   = var.key_vault_purge_protection_enabled

  tags = {
    managed-by = "terraform"
    app        = local.full_name
  }
}

resource "azurerm_role_assignment" "terraform_secrets_officer" {
  count                = var.create_key_vault ? 1 : 0
  scope                = azurerm_key_vault.this[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "secret_reader" {
  for_each             = var.create_key_vault ? toset(var.key_vault_secret_readers) : toset([])
  scope                = azurerm_key_vault.this[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = each.value
}

resource "azurerm_key_vault_secret" "client_secret" {
  count           = var.create_key_vault && var.client_secret_enabled ? 1 : 0
  name            = "${local.app_slug}-client-secret"
  value           = azuread_application_password.this[0].value
  key_vault_id    = azurerm_key_vault.this[0].id
  content_type    = "application/x-client-secret"
  expiration_date = local.secret_end_date

  tags = {
    managed-by = "terraform"
    app        = local.full_name
  }

  depends_on = [azurerm_role_assignment.terraform_secrets_officer]
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
