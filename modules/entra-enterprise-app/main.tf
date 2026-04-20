locals {
  full_name         = "DG-${var.app_name}"
  cert_display_name = coalesce(var.saml_certificate_display_name, "CN=${local.full_name}")
  # Detect Windows by checking for a drive-letter colon in the home path (C:\...)
  is_windows = substr(pathexpand("~"), 1, 1) == ":"

  # Payload and URL for the internal portal API that backs the SAML SSO edit blade
  # and federation metadata. The public Graph API identifierUris patch is necessary
  # but not sufficient — this API writes to a separate config store that the portal
  # and federation metadata endpoint actually read from.
  _saml_sso_url = "https://main.iam.ad.ext.azure.com/api/ApplicationSso/${azuread_service_principal.this.object_id}/FederatedSsoConfigV4/${azuread_application.this.client_id}"

  _saml_sso_config = jsonencode({
    identifierUris  = var.saml_identifier_uris
    idpIdentifier   = length(var.saml_identifier_uris) > 0 ? var.saml_identifier_uris[0] : ""
    idpReplyUrl     = ""
    logoutUrl       = var.saml_logout_url != null ? var.saml_logout_url : ""
    objectId        = azuread_service_principal.this.object_id
    replyUrls       = var.saml_reply_urls
    redirectUriSettings = [for url in var.saml_reply_urls : { index = null, uri = url }]
    relayState      = ""
    signOnUrl       = ""
    certificateNotificationEmail = length(var.notification_email_addresses) > 0 ? var.notification_email_addresses[0] : ""
    tokenIssuancePolicy = {
      emitSamlNameFormat         = false
      samlTokenVersion           = "2.0"
      signingAlgorithm           = "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
      tokenResponseSigningPolicy = "TokenOnly"
      version                    = 1
    }
    tokenIssuancePolicySource = "default"
  })
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

# Linux/macOS — auto-selected when pathexpand("~") starts with / (not a Windows drive letter)
resource "null_resource" "app_identifier_uris" {
  count = length(var.saml_identifier_uris) > 0 && !local.is_windows ? 1 : 0

  triggers = {
    object_id       = azuread_application.this.object_id
    identifier_uris = jsonencode(var.saml_identifier_uris)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/sh", "-c"]
    command     = <<-EOT
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
        --body '{"applicationTemplateId": "8adf8e6e-67b2-4cf2-a259-e3dc5476c621"}' \
        --headers "Content-Type=application/json" \
        || true
      retries=6; delay=10
      for i in $(seq 1 $retries); do
        az rest --method PATCH \
          --url "https://graph.microsoft.com/v1.0/applications/${azuread_application.this.object_id}" \
          --body '{"identifierUris": ${jsonencode(var.saml_identifier_uris)}}' \
          --headers "Content-Type=application/json" && break
        [ $i -eq $retries ] && exit 1
        echo "Attempt $i failed, retrying in $${delay}s..."
        sleep $delay
      done
      tmp_sso=$(mktemp)
      echo '${local._saml_sso_config}' > "$tmp_sso"
      az rest --method PUT \
        --url "${local._saml_sso_url}" \
        --body "@$tmp_sso" \
        --resource "74658136-14ec-4630-ad9b-26e160ff0fc6" \
        --headers "Content-Type=application/json"
      rm -f "$tmp_sso"
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/sh", "-c"]
    command     = <<-EOT
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
        --body '{"identifierUris": []}' \
        --headers "Content-Type=application/json"
    EOT
  }

  depends_on = [azuread_application.this, azuread_service_principal.this]
}

# Windows — auto-selected when pathexpand("~") contains a drive letter (C:\...)
# Pipes JSON body via stdin (@-) to avoid Windows argument-parsing issues with inline JSON.
resource "null_resource" "app_identifier_uris_win" {
  count = length(var.saml_identifier_uris) > 0 && local.is_windows ? 1 : 0

  triggers = {
    object_id       = azuread_application.this.object_id
    identifier_uris = jsonencode(var.saml_identifier_uris)
  }

  provisioner "local-exec" {
    interpreter = ["powershell", "-Command"]
    command     = <<-EOT
      $ErrorActionPreference = 'Stop'
      $result = az account show 2>$null
      if (-not $result) {
        az login --service-principal --federated-token $env:ARM_OIDC_TOKEN --username $env:ARM_CLIENT_ID --tenant $env:ARM_TENANT_ID --allow-no-subscriptions | Out-Null
      }
      $tmp = [System.IO.Path]::GetTempFileName()
      try {
        [System.IO.File]::WriteAllText($tmp, '{"applicationTemplateId": "8adf8e6e-67b2-4cf2-a259-e3dc5476c621"}')
        az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/${azuread_application.this.object_id}" --body "@$tmp" --headers "Content-Type=application/json"
        if ($LASTEXITCODE -ne 0) { Write-Host "Note: applicationTemplateId already set, skipping" }
      } finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
      }
      $tmp2 = [System.IO.Path]::GetTempFileName()
      try {
        [System.IO.File]::WriteAllText($tmp2, '{"identifierUris": ${jsonencode(var.saml_identifier_uris)}}')
        $retries = 6; $delay = 10
        for ($i = 1; $i -le $retries; $i++) {
          az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/${azuread_application.this.object_id}" --body "@$tmp2" --headers "Content-Type=application/json"
          if ($LASTEXITCODE -eq 0) { break }
          if ($i -eq $retries) { throw "az rest failed after $retries attempts" }
          Write-Host "Attempt $i failed, retrying in $delay seconds..."
          Start-Sleep -Seconds $delay
        }
      } finally {
        Remove-Item $tmp2 -ErrorAction SilentlyContinue
      }
      $tmp_sso = [System.IO.Path]::GetTempFileName()
      try {
        [System.IO.File]::WriteAllText($tmp_sso, '${local._saml_sso_config}')
        az rest --method PUT --url "${local._saml_sso_url}" --body "@$tmp_sso" --resource "74658136-14ec-4630-ad9b-26e160ff0fc6" --headers "Content-Type=application/json"
        if ($LASTEXITCODE -ne 0) { throw "FederatedSsoConfig PUT failed" }
      } finally {
        Remove-Item $tmp_sso -ErrorAction SilentlyContinue
      }
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["powershell", "-Command"]
    command     = <<-EOT
      $ErrorActionPreference = 'Stop'
      $result = az account show 2>$null
      if (-not $result) {
        az login --service-principal --federated-token $env:ARM_OIDC_TOKEN --username $env:ARM_CLIENT_ID --tenant $env:ARM_TENANT_ID --allow-no-subscriptions | Out-Null
      }
      $tmp = [System.IO.Path]::GetTempFileName()
      try {
        [System.IO.File]::WriteAllText($tmp, '{"identifierUris": []}')
        az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/${self.triggers.object_id}" --body "@$tmp" --headers "Content-Type=application/json"
        if ($LASTEXITCODE -ne 0) { throw "az rest failed with exit code $LASTEXITCODE" }
      } finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
      }
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
