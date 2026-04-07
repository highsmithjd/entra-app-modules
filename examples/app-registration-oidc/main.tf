terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.47.0"
    }
  }
}

provider "azuread" {}

# Example 1: Web app with client secret
module "web_app" {
  source = "../../modules/entra-app-registration"

  app_name  = "MyWebApp"
  flow_type = "web"

  redirect_uris = ["https://mywebapp.example.com/auth/callback"]
  logout_url    = "https://mywebapp.example.com/logout"

  client_secret_enabled      = true
  client_secret_display_name = "app-secret"
  client_secret_expiry_days  = 365

  # Request Microsoft Graph permissions
  required_resource_access = [
    {
      resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
      resource_access = [
        {
          id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read (delegated)
          type = "Scope"
        }
      ]
    }
  ]

  notes = "Owner: platform-team | Ticket: PLAT-5678"
  tags  = ["platform-team", "web", "production"]
}

# Example 2: Daemon / service-to-service with certificate
module "daemon_app" {
  source = "../../modules/entra-app-registration"

  app_name  = "MyDaemonService"
  flow_type = "daemon"

  client_certificate_enabled  = true
  client_certificate_value    = file("${path.module}/service.crt") # base64 PEM
  client_certificate_expiry   = "2027-01-01T00:00:00Z"

  required_resource_access = [
    {
      resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
      resource_access = [
        {
          id   = "df021288-bdef-4463-88db-98f22de89214" # User.Read.All (application)
          type = "Role"
        }
      ]
    }
  ]

  notes = "Owner: platform-team | Used by: data pipeline job"
  tags  = ["platform-team", "daemon", "production"]
}

# Example 3: GitHub Actions using federated credentials (no secret needed)
module "github_actions_app" {
  source = "../../modules/entra-app-registration"

  app_name  = "GitHubActions-MyRepo"
  flow_type = "daemon"

  federated_credentials = [
    {
      name        = "github-main"
      issuer      = "https://token.actions.githubusercontent.com"
      subject     = "repo:my-org/my-repo:ref:refs/heads/main"
      description = "GitHub Actions deployments from main branch"
    },
    {
      name        = "github-prs"
      issuer      = "https://token.actions.githubusercontent.com"
      subject     = "repo:my-org/my-repo:pull_request"
      description = "GitHub Actions on pull requests"
    }
  ]

  notes = "Owner: platform-team | No secrets — uses OIDC federation"
  tags  = ["platform-team", "github-actions", "production"]
}

output "web_app_client_id" {
  value = module.web_app.application_id
}

output "web_app_secret" {
  value     = module.web_app.client_secret
  sensitive = true
}

output "daemon_app_client_id" {
  value = module.daemon_app.application_id
}

output "github_app_client_id" {
  value = module.github_actions_app.application_id
}
