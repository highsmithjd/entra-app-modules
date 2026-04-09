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

module "app" {
  source = "../../../modules/entra-app-registration"

  app_name  = "MyWebApp-Sbx"
  flow_type = "web"

  redirect_uris = ["https://sbx.mywebapp.example.com/auth/callback"]
  logout_url    = "https://sbx.mywebapp.example.com/logout"

  client_secret_enabled     = true
  client_secret_expiry_days = 365

  create_key_vault                     = true
  key_vault_resource_group_name        = "rg-dg-mywebapp" # managed by shared/
  key_vault_soft_delete_retention_days = 7
  key_vault_purge_protection_enabled   = false

  required_resource_access = [
    {
      resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
      resource_access = [
        { id = "e1fe6dd8-ba31-4d61-89e7-88639da4683d", type = "Scope" }, # User.Read (delegated)
      ]
    }
  ]

  notes = "Owner: platform-team | Ticket: PLAT-5678 | Env: sbx"
  tags  = ["platform-team", "web", "sbx"]
}

output "application_id" {
  value = module.app.application_id
}

output "client_secret_expiry" {
  value = module.app.client_secret_expiry
}

output "key_vault_uri" {
  value = module.app.key_vault_uri
}

output "key_vault_secret_name" {
  value = module.app.key_vault_secret_name
}
