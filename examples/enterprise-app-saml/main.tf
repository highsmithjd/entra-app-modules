terraform {
  required_version = ">= 1.3.0"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.47.0"
    }
  }
}

provider "azuread" {}

# Self-contained SAML enterprise app deployment.
# Deploy one copy per environment, each in its own repo with its own state.
module "app" {
  source = "git::https://github.com/highsmithjd/entra-app-modules.git//modules/entra-enterprise-app?ref=v2.0.0"

  app_name = "MyVendorApp-Sbx"

  saml_identifier_uris = ["https://sbx.myvendorapp.example.com"]
  saml_reply_urls      = ["https://sbx.myvendorapp.example.com/saml/acs"]
  saml_logout_url      = "https://sbx.myvendorapp.example.com/saml/logout"

  saml_signing_certificate_enabled = true

  app_role_assignments = [
    {
      principal_object_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" # All Users group
      principal_type      = "Group"
    }
  ]

  notes = "Owner: platform-team | Ticket: PLAT-1234 | Vendor: MyVendor | Env: sbx"
  tags  = ["platform-team", "saml", "sbx"]
}

output "saml_federation_metadata_url" {
  value = module.app.saml_metadata_url
}

output "signing_cert_thumbprint" {
  value     = module.app.signing_certificate
  sensitive = true
}
