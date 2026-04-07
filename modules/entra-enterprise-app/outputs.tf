output "application_id" {
  description = "The application (client) ID."
  value       = azuread_application.this.client_id
}

output "application_object_id" {
  description = "The object ID of the application registration."
  value       = azuread_application.this.id
}

output "service_principal_object_id" {
  description = "The object ID of the service principal."
  value       = azuread_service_principal.this.object_id
}

output "display_name" {
  description = "The full display name of the application (with DG- prefix)."
  value       = azuread_application.this.display_name
}

output "saml_metadata_url" {
  description = "The Entra-side SAML federation metadata URL for this app."
  value       = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/federationmetadata/2007-06/federationmetadata.xml?appid=${azuread_application.this.client_id}"
}

output "signing_certificate" {
  description = "The SAML token signing certificate details. Null if not created."
  value = var.saml_signing_certificate_enabled ? {
    thumbprint   = azuread_service_principal_token_signing_certificate.this[0].thumbprint
    display_name = azuread_service_principal_token_signing_certificate.this[0].display_name
    expiry       = azuread_service_principal_token_signing_certificate.this[0].end_date
    value        = azuread_service_principal_token_signing_certificate.this[0].value
  } : null
  sensitive = true
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
