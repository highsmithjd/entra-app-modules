locals {
  full_name       = "DG-${var.app_name}"
  secret_end_date = timeadd(time_static.now.rfc3339, "${var.client_secret_expiry_days * 24}h")

  # Derive which redirect URI block to populate based on flow type
  is_web            = var.flow_type == "web"
  is_spa            = var.flow_type == "spa"
  is_mobile_desktop = var.flow_type == "mobile_desktop"
  # daemon flow has no redirect URIs

  # Key Vault naming — lowercase, hyphens only, max 24 chars total
  app_slug   = lower(replace(var.app_name, " ", "-"))
  vault_name = "kv-dg-${local.app_slug}"

  # Use the provided resource group name or auto-generate one
  rg_name        = coalesce(var.key_vault_resource_group_name, "rg-dg-${local.app_slug}")
  create_rg      = var.create_key_vault && var.key_vault_resource_group_name == null

  # Key Vault-managed certificate — requires create_key_vault = true
  create_kv_cert = var.create_key_vault && var.create_key_vault_certificate

  # Set of slot names to create KV certs for
  kv_cert_slots = local.create_kv_cert ? toset(var.key_vault_certificate_slots) : toset([])
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
# Key Vault — optional, one per app, co-located with the app registration
# ---------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

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

# Terraform SP always gets Secrets Officer so it can write secrets
resource "azurerm_role_assignment" "terraform_secrets_officer" {
  count                = var.create_key_vault ? 1 : 0
  scope                = azurerm_key_vault.this[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# App identities that need to read secrets at runtime
resource "azurerm_role_assignment" "secret_reader" {
  for_each             = var.create_key_vault ? toset(var.key_vault_secret_readers) : toset([])
  scope                = azurerm_key_vault.this[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = each.value
}

# Write client secret to vault when both are enabled
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
# Client certificate — externally provided
# ---------------------------------------------------------------------------

resource "azuread_application_certificate" "external" {
  count = var.client_certificate_enabled ? 1 : 0

  application_id = azuread_application.this.id
  type           = "AsymmetricX509Cert"
  value          = var.client_certificate_value
  end_date       = var.client_certificate_expiry
}

# ---------------------------------------------------------------------------
# Key Vault-managed certificates (self-signed, generated by Key Vault)
# Multiple slots allow zero-downtime rotation — both old and new certs are
# registered in Entra simultaneously during the handover window.
# ---------------------------------------------------------------------------

# Terraform SP needs Certificates Officer to create certs in the vault
resource "azurerm_role_assignment" "terraform_certificates_officer" {
  count                = local.create_kv_cert ? 1 : 0
  scope                = azurerm_key_vault.this[0].id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_certificate" "this" {
  for_each     = local.kv_cert_slots
  name         = "${local.app_slug}-cert-${each.key}"
  key_vault_id = azurerm_key_vault.this[0].id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }
    key_properties {
      exportable = true
      key_size   = var.key_vault_certificate_key_size
      key_type   = "RSA"
      reuse_key  = false
    }
    secret_properties {
      content_type = "application/x-pkcs12"
    }
    x509_certificate_properties {
      subject            = coalesce(var.key_vault_certificate_subject, "CN=${local.full_name}")
      validity_in_months = var.key_vault_certificate_validity_months
      key_usage          = ["digitalSignature"]
    }
  }

  tags = {
    managed-by = "terraform"
    app        = local.full_name
    slot       = each.key
  }

  depends_on = [azurerm_role_assignment.terraform_certificates_officer]
}

resource "azuread_application_certificate" "kv" {
  for_each = local.kv_cert_slots

  application_id = azuread_application.this.id
  type           = "AsymmetricX509Cert"
  value          = azurerm_key_vault_certificate.this[each.key].certificate_data_base64
  end_date       = azurerm_key_vault_certificate.this[each.key].certificate_attribute[0].expires

  depends_on = [azurerm_key_vault_certificate.this]
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
