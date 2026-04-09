terraform {
  required_version = ">= 1.3.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.75.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Shared resource group for all MyWebApp Key Vaults.
#
# Managed independently so that destroying sbx or prod cannot take out
# another environment's Key Vault.
#
# Apply this before sbx or prod.
# Destroy this LAST — only after all environments have been destroyed.
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
