locals {
  full_name         = "DG-${var.app_name}"
  cert_display_name = coalesce(var.saml_certificate_display_name, "CN=${local.full_name}")
  # Detect Windows by checking for a drive-letter colon in the home path (C:\...)
  is_windows = substr(pathexpand("~"), 1, 1) == ":"

  # The SAML template auto-creates a "User" role with its own GUID. When custom
  # roles exist, assigning to 00000000... is invalid — use the template's role instead.
  default_app_role_id = try(
    [for r in azuread_service_principal.this.app_roles : r.id if r.display_name == "User"][0],
    "00000000-0000-0000-0000-000000000000"
  )
}

# ---------------------------------------------------------------------------
# Application registration
# ---------------------------------------------------------------------------

data "azuread_client_config" "current" {}

resource "azuread_application" "this" {
  display_name     = local.full_name
  sign_in_audience = "AzureADMyOrg"
  notes            = var.notes

  # Link to the custom SAML app template. This causes Entra to fully initialize
  # the app as a SAML enterprise app — including the internal config store that
  # backs the portal's Basic SAML Configuration edit blade. Without this, the
  # blade renders read-only even when Graph API data looks correct.
  template_id = "8adf8e6e-67b2-4cf2-a259-e3dc5476c621"

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
    # Prevent accidental rename which would break SSO.
    # Ignore template_id after creation — it's a ForceNew attribute and changing
    # it would destroy the app; existing apps migrating to v3 must destroy+recreate.
    # app_role: template auto-creates User and msiam_access roles; ignore prevents
    # OpenTofu from stripping them on every apply.
    ignore_changes = [display_name, template_id, app_role]
  }
}

# Post-creation provisioner — runs on Linux/macOS (auto-selected via is_windows).
#
# Responsibilities:
#   1. PATCH identifierUris — Graph API rejects vendor entity IDs at creation time
#      (unverified domain restriction), but accepts them on a subsequent PATCH.
#   2. PUT FederatedSsoConfigV4 — writes to the internal config store that backs
#      the portal's Basic SAML Configuration blade (belt-and-suspenders alongside
#      template_id initialization).
#   3. PATCH preferredTokenSigningKeyThumbprint — activates the signing cert; without
#      this the cert is present but not used for SAML token signing.
#
# The destroy provisioner clears identifierUris before the app is deleted —
# Entra blocks deletion when non-verified URIs are present.
resource "null_resource" "app_identifier_uris" {
  count = !local.is_windows ? 1 : 0

  triggers = {
    object_id       = azuread_application.this.object_id
    identifier_uris = jsonencode(var.saml_identifier_uris)
    cert_thumbprint = var.saml_signing_certificate_enabled ? azuread_service_principal_token_signing_certificate.this[0].thumbprint : ""
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
      # The SAML exemption from verified-domain restrictions applies once the SP has
      # preferredSingleSignOnMode=saml — which depends_on guarantees before this runs.
      # The retry loop handles Entra replication lag before the exemption propagates.
      %{~ if length(var.saml_identifier_uris) > 0}
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
      %{~ endif}
      %{~ if var.saml_signing_certificate_enabled}
      az rest --method PATCH \
        --url "https://graph.microsoft.com/v1.0/servicePrincipals/${azuread_service_principal.this.object_id}" \
        --body '{"preferredTokenSigningKeyThumbprint": "${azuread_service_principal_token_signing_certificate.this[0].thumbprint}"}' \
        --headers "Content-Type=application/json"
      %{~ endif}
      sleep 20
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

  depends_on = [
    azuread_application.this,
    azuread_service_principal.this,
    azuread_service_principal_token_signing_certificate.this,
  ]
}

# Windows — auto-selected when pathexpand("~") contains a drive letter (C:\...)
# Pipes JSON body via temp file to avoid Windows argument-parsing issues with inline JSON.
resource "null_resource" "app_identifier_uris_win" {
  count = local.is_windows ? 1 : 0

  triggers = {
    object_id       = azuread_application.this.object_id
    identifier_uris = jsonencode(var.saml_identifier_uris)
    cert_thumbprint = var.saml_signing_certificate_enabled ? azuread_service_principal_token_signing_certificate.this[0].thumbprint : ""
  }

  provisioner "local-exec" {
    interpreter = ["powershell", "-Command"]
    command     = <<-EOT
      $ErrorActionPreference = 'Stop'
      $result = az account show 2>$null
      if (-not $result) {
        az login --service-principal --federated-token $env:ARM_OIDC_TOKEN --username $env:ARM_CLIENT_ID --tenant $env:ARM_TENANT_ID --allow-no-subscriptions | Out-Null
      }
      # The SAML exemption from verified-domain restrictions applies once the SP has
      # preferredSingleSignOnMode=saml — which depends_on guarantees before this runs.
      # The retry loop handles Entra replication lag before the exemption propagates.
      %{~ if length(var.saml_identifier_uris) > 0}
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
      %{~ endif}
      %{~ if var.saml_signing_certificate_enabled}
      $tmp_cert = [System.IO.Path]::GetTempFileName()
      try {
        [System.IO.File]::WriteAllText($tmp_cert, '{"preferredTokenSigningKeyThumbprint": "${azuread_service_principal_token_signing_certificate.this[0].thumbprint}"}')
        az rest --method PATCH --url "https://graph.microsoft.com/v1.0/servicePrincipals/${azuread_service_principal.this.object_id}" --body "@$tmp_cert" --headers "Content-Type=application/json"
        if ($LASTEXITCODE -ne 0) { throw "preferredTokenSigningKeyThumbprint PATCH failed" }
      } finally {
        Remove-Item $tmp_cert -ErrorAction SilentlyContinue
      }
      %{~ endif}
      Start-Sleep -Seconds 20
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

  depends_on = [
    azuread_application.this,
    azuread_service_principal.this,
    azuread_service_principal_token_signing_certificate.this,
  ]
}

# ---------------------------------------------------------------------------
# Service principal (the instance of the app in your tenant)
# ---------------------------------------------------------------------------

resource "azuread_service_principal" "this" {
  client_id                     = azuread_application.this.client_id
  app_role_assignment_required  = length(var.app_role_assignments) > 0
  preferred_single_sign_on_mode = "saml"
  notification_email_addresses  = var.notification_email_addresses

  # use_existing adopts a pre-existing SP if one was created by template instantiation,
  # rather than erroring. Safe to set unconditionally.
  use_existing = true

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

  app_role_id         = local.default_app_role_id
  principal_object_id = each.value.principal_object_id
  resource_object_id  = azuread_service_principal.this.object_id

  # Wait for provisioners to complete template linkage before assigning roles —
  # the default access role may not be resolvable until the app is fully initialized.
  depends_on = [
    null_resource.app_identifier_uris,
    null_resource.app_identifier_uris_win,
  ]
}
