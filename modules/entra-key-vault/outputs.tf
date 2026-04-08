output "key_vault_id" {
  description = "The resource ID of the key vault. Pass this to the entra-app-registration module to enable secret storage."
  value       = azurerm_key_vault.this.id
}

output "key_vault_uri" {
  description = "The URI of the key vault (e.g. https://kv-dg-compms.vault.azure.net/). Used by app code to retrieve secrets at runtime."
  value       = azurerm_key_vault.this.vault_uri
}

output "key_vault_name" {
  description = "The name of the key vault."
  value       = azurerm_key_vault.this.name
}

output "resource_group_name" {
  description = "The name of the resource group containing the key vault."
  value       = azurerm_resource_group.this.name
}

output "resource_group_id" {
  description = "The resource ID of the resource group."
  value       = azurerm_resource_group.this.id
}
