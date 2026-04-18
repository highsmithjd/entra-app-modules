locals {
  full_name         = "DG-${var.app_name}"
  cert_display_name = coalesce(var.saml_certificate_display_name, "CN=${local.full_name}")
  # Detect Windows by checking for a drive-letter colon in the home path (C:\...)
  is_windows        = substr(pathexpand("~"), 1, 1) == ":"
  interpreter       = local.is_windows ? ["powershell", "-Command"] : ["/bin/sh", "-c"]
}

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
    enterprise            = var.feature_tags.enterprise
    gallery               = var.feature_tags.gallery
    hide                  = var.feature_tags.hide
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

# Patch identifier URIs using the appropriate shell for the current OS.
# local.is_windows auto-detects Windows via the home-path drive letter.
# The PowerShell path pipes the JSON body via stdin (@-) to avoid Windows
# argument-parsing issues with inline JSON.
resource "null_resource" "app_identifier_uris" {
  count = length(var.saml_identifier_uris) > 0 ? 1 : 0

  triggers = {
    object_id       = azuread_application.this.object_id
    identifier_uris = jsonencode(var.saml_identifier_uris)
  }

  provisioner "local-exec" {
    interpreter = local.interpreter
    command     = local.is_windows ? <<-EOT
      $ErrorActionPreference = 'Stop'
      $result = az account show 2>$null
      if (-not $result) {
        az login --service-principal --federated-token $env:ARM_OIDC_TOKEN --username $env:ARM_CLIENT_ID --tenant $env:ARM_TENANT_ID --allow-no-subscriptions | Out-Null
      }
      '{"identifierUris": ${jsonencode(var.saml_identifier_uris)}}' | az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/${azuread_application.this.object_id}" --body '@-'
    EOT
    : <<-EOT
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
    when        = destroy
    interpreter = local.interpreter
    command     = local.is_windows ? <<-EOT
      $ErrorActionPreference = 'Stop'
      $result = az account show 2>$null
      if (-not $result) {
        az login --service-principal --federated-token $env:ARM_OIDC_TOKEN --username $env:ARM_CLIENT_ID --tenant $env:ARM_TENANT_ID --allow-no-subscriptions | Out-Null
      }
      '{"identifierUris": []}' | az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/${self.triggers.object_id}" --body '@-'
    EOT
    : <<-EOT
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
