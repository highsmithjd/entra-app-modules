terraform {
  required_version = ">= 1.3.0"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.47.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.75.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.0"
    }
  }
}

provider "azuread" {}

provider "azurerm" {
  features {}
}

# Self-contained OIDC web app deployment.
# Deploy one copy per environment, each in its own repo with its own state.
# Each deployment creates its own resource group and Key Vault independently.
module "app" {
  source = "git::https://github.com/highsmithjd/entra-app-modules.git//modules/entra-app-registration?ref=v2.0.0"

  app_name  = "MyWebApp-Sbx"
  flow_type = "web"

  redirect_uris = ["https://sbx.mywebapp.example.com/auth/callback"]
  logout_url    = "https://sbx.mywebapp.example.com/logout"

  create_key_vault             = true
  create_key_vault_certificate = true

  key_vault_soft_delete_retention_days = 7
  key_vault_purge_protection_enabled   = false

  required_resource_access = [
    {
      resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
      resource_access = [
        { id = "37f7f235-527c-4136-accd-4a02d197296e", type = "Scope" }, # openid
        { id = "14dad69e-099b-42c9-810b-d002981feec1", type = "Scope" }, # profile
        { id = "64a6cdd6-aab1-4aad-94b8-3cc8405e90d6", type = "Scope" }, # email
      ]
    }
  ]

  notes = "Owner: platform-team | Ticket: PLAT-5678 | Env: sbx"
  tags  = ["platform-team", "web", "sbx"]
}

output "application_id" {
  value = module.app.application_id
}

output "key_vault_uri" {
  value = module.app.key_vault_uri
}

output "key_vault_certificate_names" {
  value = module.app.key_vault_certificate_names
}

output "key_vault_certificate_expiries" {
  value = module.app.key_vault_certificate_expiries
}
