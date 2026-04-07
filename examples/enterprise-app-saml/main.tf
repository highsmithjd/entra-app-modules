terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.47.0"
    }
  }
}

provider "azuread" {}

module "saml_app" {
  source = "../../modules/entra-enterprise-app"

  app_name = "MyVendorApp"

  # SAML SP configuration
  saml_identifier_uris = ["https://myvendorapp.example.com"]
  saml_reply_urls      = ["https://myvendorapp.example.com/saml/acs"]
  saml_logout_url      = "https://myvendorapp.example.com/saml/logout"

  # Create Entra-managed SAML signing certificate
  saml_signing_certificate_enabled = true

  # Assign two groups to the app
  app_role_assignments = [
    {
      principal_object_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" # All Users group
      principal_type      = "Group"
    },
    {
      principal_object_id = "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy" # Platform Team group
      principal_type      = "Group"
    }
  ]

  notes = "Owner: platform-team | Ticket: PLAT-1234 | Vendor: MyVendor"
  tags  = ["platform-team", "saml", "production"]
}

output "saml_federation_metadata_url" {
  value = module.saml_app.saml_metadata_url
}

output "signing_cert_thumbprint" {
  value     = module.saml_app.signing_certificate
  sensitive = true
}
