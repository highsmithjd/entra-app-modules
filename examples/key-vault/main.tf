terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.75.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.47.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azuread" {}

module "key_vault" {
  source = "../../modules/entra-key-vault"

  team_name = "compms"

  # Optional — these default to centralus and 90 days
  location                   = "centralus"
  soft_delete_retention_days = 90
  purge_protection_enabled   = true

  # Object IDs of identities that can read secrets at runtime (e.g. app managed identity)
  secret_readers = [
    "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  ]

  # Object IDs of additional admins beyond the Terraform caller
  secret_officers = [
    "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy" # platform team group
  ]

  tags = {
    env  = "prod"
    team = "compms"
  }
}

output "key_vault_uri" {
  description = "Give this URI to the app team so their code knows where to retrieve secrets."
  value       = module.key_vault.key_vault_uri
}

output "key_vault_id" {
  description = "Pass this to entra-app-registration to enable automatic secret storage."
  value       = module.key_vault.key_vault_id
}
