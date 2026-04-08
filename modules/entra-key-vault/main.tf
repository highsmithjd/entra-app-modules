locals {
  team_slug  = "dg-${var.team_name}"
  rg_name    = "rg-${local.team_slug}"
  vault_name = "kv-${local.team_slug}"

  # Merge platform tags with caller-supplied tags
  base_tags = {
    managed-by = "terraform"
    team       = var.team_name
  }
  all_tags = merge(local.base_tags, var.tags)
}

data "azurerm_client_config" "current" {}

# ---------------------------------------------------------------------------
# Resource group — created by this module so Terraform can fully recreate
# everything from scratch without any manual prerequisites.
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  name     = local.rg_name
  location = var.location
  tags     = local.all_tags
}

# ---------------------------------------------------------------------------
# Key Vault
# ---------------------------------------------------------------------------

resource "azurerm_key_vault" "this" {
  name                = local.vault_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name = "standard"

  # RBAC mode — access is controlled via Azure role assignments, not vault
  # access policies. This is the recommended modern approach.
  rbac_authorization_enabled = true

  soft_delete_retention_days = var.soft_delete_retention_days
  purge_protection_enabled   = var.purge_protection_enabled

  tags = local.all_tags
}

# ---------------------------------------------------------------------------
# Role assignments — Secrets
# ---------------------------------------------------------------------------

# The Terraform caller always gets Secrets Officer so it can write secrets
resource "azurerm_role_assignment" "terraform_secrets_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Additional secrets officers (platform team, other automation)
resource "azurerm_role_assignment" "secrets_officer" {
  for_each = toset(var.secret_officers)

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = each.value
}

# Secret readers — app identities that need to read secret values at runtime
resource "azurerm_role_assignment" "secrets_user" {
  for_each = toset(var.secret_readers)

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = each.value
}

# ---------------------------------------------------------------------------
# Role assignments — Certificates
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "certificate_officer" {
  for_each = toset(var.certificate_officers)

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "certificate_user" {
  for_each = toset(var.certificate_users)

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Certificate User"
  principal_id         = each.value
}
