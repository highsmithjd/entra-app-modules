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

  # Replace with your backend configuration (e.g. azurerm, http, s3)
  backend "http" {}
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
        { id = "37f7f235-527c-4136-accd-4a02d197296e", type = "Scope" }, # openid
        { id = "14dad69e-099b-42c9-810b-d002981feec1", type = "Scope" }, # profile
        { id = "64a6cdd6-aab1-4aad-94b8-3cc8405e90d6", type = "Scope" }, # email
      ]
    }
  ]

  notes = "Owner: platform-team | Env: sbx"
  tags  = ["platform-team", "sbx"]
}

output "application_id" {
  value = module.app.application_id
}

output "key_vault_uri" {
  value = module.app.key_vault_uri
}

output "key_vault_secret_name" {
  value = module.app.key_vault_secret_name
}

output "client_secret_expiry" {
  value = module.app.client_secret_expiry
}
