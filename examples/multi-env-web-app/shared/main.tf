terraform {
  required_version = ">= 1.3.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.75.0"
    }
  }

  # Replace with your backend configuration (e.g. azurerm, http, s3)
  backend "http" {}
}

provider "azurerm" {
  features {}
}

# ---------------------------------------------------------------------------
# Shared resource group
#
# This is the only resource in this environment. It owns the resource group
# that all environments' Key Vaults will live in. Managing it separately
# means no single environment's destroy can take out another's Key Vault.
#
# Apply this before sbx or prod.
# Destroy this LAST — only after both sbx and prod have been destroyed.
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "shared" {
  name     = "rg-dg-mywebapp"
  location = "centralus"

  tags = {
    managed-by = "terraform"
    app        = "DG-MyWebApp"
  }
}

output "resource_group_name" {
  description = "Name of the shared resource group. Pass this to sbx and prod as key_vault_resource_group_name."
  value       = azurerm_resource_group.shared.name
}
