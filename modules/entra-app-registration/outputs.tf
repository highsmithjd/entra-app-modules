output "application_id" {
  description = "The application (client) ID."
  value       = azuread_application.this.client_id
}

output "application_object_id" {
  description = "The object ID of the application registration."
  value       = azuread_application.this.id
}

output "service_principal_object_id" {
  description = "The object ID of the service principal. Null if create_service_principal is false."
  value       = var.create_service_principal ? azuread_service_principal.this[0].object_id : null
}

output "display_name" {
  description = "The full display name of the application (with DG- prefix)."
  value       = azuread_application.this.display_name
}

output "tenant_id" {
  description = "The tenant ID where the app is registered."
  value       = data.azuread_client_config.current.tenant_id
}

output "client_secret" {
  description = "The client secret value. Null if not created. Sensitive — store in a vault, not in state long-term."
  value       = var.client_secret_enabled ? azuread_application_password.this[0].value : null
  sensitive   = true
}

output "client_secret_expiry" {
  description = "The expiry date of the client secret. Null if not created."
  value       = var.client_secret_enabled ? local.secret_end_date : null
}

output "key_vault_uri" {
  description = "The URI of the Key Vault. Null if create_key_vault is false."
  value       = var.create_key_vault ? azurerm_key_vault.this[0].vault_uri : null
}

output "key_vault_secret_name" {
  description = "The name of the client secret in Key Vault. Null if create_key_vault or client_secret_enabled is false."
  value       = var.create_key_vault && var.client_secret_enabled ? azurerm_key_vault_secret.client_secret[0].name : null
}

output "key_vault_certificate_names" {
  description = "Map of slot name to Key Vault certificate name (e.g. { primary = 'myapp-cert-primary' }). Empty if not created by the module."
  value       = { for slot, cert in azurerm_key_vault_certificate.this : slot => cert.name }
}

output "key_vault_certificate_thumbprints" {
  description = "Map of slot name to certificate thumbprint. Empty if not created by the module."
  value       = { for slot, cert in azurerm_key_vault_certificate.this : slot => cert.thumbprint }
}

output "key_vault_certificate_expiries" {
  description = "Map of slot name to certificate expiry date. Empty if not created by the module."
  value       = { for slot, cert in azurerm_key_vault_certificate.this : slot => cert.certificate_attribute[0].expires }
}

output "federated_credential_ids" {
  description = "Map of federated credential names to their IDs."
  value = {
    for name, fc in azuread_application_federated_identity_credential.this :
    name => fc.id
  }
}
