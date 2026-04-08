# entra-app-modules

Terraform modules for deploying Microsoft Entra ID (Azure AD) applications.

- **[entra-enterprise-app](#module-entra-enterprise-app)** — SAML Enterprise Applications (for SaaS vendors like Google, Oracle, Salesforce, etc.)
- **[entra-app-registration](#module-entra-app-registration)** — OAuth 2.0 / OIDC App Registrations (for internal apps, APIs, daemons, and CI/CD pipelines)
- **[entra-key-vault](#module-entra-key-vault)** — Azure Key Vault with RBAC, one per team, for storing app secrets and certificates

All apps are automatically prefixed with `DG-`. Key vaults are named `kv-dg-<team>` and resource groups `rg-dg-<team>`.

---

## Requirements

| Tool | Version |
|---|---|
| Terraform | >= 1.3.0 |
| hashicorp/azuread provider | >= 2.47.0 |
| hashicorp/time provider | >= 0.9.0 |

The identity running Terraform needs one of the following Entra roles:
- **Application Administrator** — can create and manage app registrations and enterprise apps
- **Cloud Application Administrator** — same but cannot manage Application Proxy

---

## Module: entra-enterprise-app

Use this module for SAML-based SSO with SaaS vendors. It creates the application registration, service principal, and optionally a SAML signing certificate.

### Usage

```hcl
module "saml_app" {
  source = "git::https://github.com/highsmithjd/entra-app-modules.git//modules/entra-enterprise-app?ref=main"

  app_name             = "MyVendorApp"
  saml_identifier_uris = ["https://myvendorapp.example.com"]
  saml_reply_urls      = ["https://myvendorapp.example.com/saml/acs"]
  saml_logout_url      = "https://myvendorapp.example.com/saml/logout"

  app_role_assignments = [
    {
      principal_object_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
      principal_type      = "Group"
    }
  ]

  notes = "Owner: platform-team | Ticket: PLAT-1234"
  tags  = ["platform-team", "saml", "production"]
}
```

### What gets created

- `azuread_application` — the app registration, configured for SAML
- `azuread_service_principal` — the enterprise app instance in your tenant
- `azuread_service_principal_token_signing_certificate` — Entra-managed SAML signing certificate (optional)
- `azuread_application_password` — client secret (optional, uncommon for SAML)
- `azuread_app_role_assignment` — assigns users/groups to the app (optional)

### How SAML works with this module

Entra acts as the Identity Provider (IdP). The SaaS vendor is the Service Provider (SP). When a user logs in:

1. The vendor redirects the user to Entra's login page
2. Entra authenticates the user and signs a SAML assertion using the signing certificate
3. Entra posts the assertion to the vendor's ACS URL (`saml_reply_urls`)
4. The vendor validates the signature using Entra's public federation metadata URL (output by this module)

The vendor never contacts your infrastructure directly — everything goes through Entra's public endpoints.

### Variables

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `app_name` | Short name. Will be prefixed with `DG-`. | `string` | — | yes |
| `saml_identifier_uris` | SAML entity IDs / audience URIs from the SP. | `list(string)` | `[]` | yes |
| `saml_reply_urls` | Assertion Consumer Service (ACS) URLs. | `list(string)` | `[]` | yes |
| `saml_logout_url` | Single logout URL. | `string` | `null` | no |
| `saml_signing_certificate_enabled` | Create an Entra-managed SAML signing certificate. | `bool` | `true` | no |
| `saml_certificate_display_name` | Display name for the signing cert. Defaults to `CN=<app_name>`. | `string` | `null` | no |
| `client_secret_enabled` | Create a client secret (uncommon for SAML). | `bool` | `false` | no |
| `client_secret_display_name` | Display name for the client secret. | `string` | `"terraform-managed"` | no |
| `client_secret_expiry_days` | Days until the client secret expires (max 730). | `number` | `365` | no |
| `app_role_assignments` | Users/groups to assign to the app. See [App Role Assignments](#app-role-assignments). | `list(object)` | `[]` | no |
| `feature_tags` | Controls portal visibility. See [Feature Tags](#feature-tags). | `object` | `{}` | no |
| `notes` | Free-text notes on the app object (owner, team, ticket, etc.). | `string` | `null` | no |
| `owners` | Entra object IDs to set as app owners. The Terraform caller is always added. | `list(string)` | `[]` | no |
| `tags` | Flat string list on the service principal (e.g. `["platform-team", "prod"]`). | `list(string)` | `[]` | no |

### Outputs

| Name | Description | Sensitive |
|---|---|---|
| `application_id` | Application (client) ID | no |
| `application_object_id` | Object ID of the app registration | no |
| `service_principal_object_id` | Object ID of the service principal | no |
| `display_name` | Full display name (with `DG-` prefix) | no |
| `saml_metadata_url` | Entra federation metadata URL to give to the SP | no |
| `signing_certificate` | Cert thumbprint, display name, expiry, and value | yes |
| `client_secret` | Client secret value (null if not created) | yes |
| `client_secret_expiry` | Client secret expiry date | no |

---

## Module: entra-app-registration

Use this module for OAuth 2.0 and OIDC applications — internal web apps, APIs, background services, and CI/CD pipelines.

### Usage

**Web app with client secret:**

```hcl
module "web_app" {
  source = "git::https://github.com/highsmithjd/entra-app-modules.git//modules/entra-app-registration?ref=main"

  app_name  = "MyWebApp"
  flow_type = "web"

  redirect_uris = ["https://mywebapp.example.com/auth/callback"]
  logout_url    = "https://mywebapp.example.com/logout"

  client_secret_enabled     = true
  client_secret_expiry_days = 365

  notes = "Owner: platform-team | Ticket: PLAT-5678"
  tags  = ["platform-team", "web", "production"]
}
```

**Daemon / service with certificate:**

```hcl
module "daemon_app" {
  source = "git::https://github.com/highsmithjd/entra-app-modules.git//modules/entra-app-registration?ref=main"

  app_name  = "MyDaemonService"
  flow_type = "daemon"

  client_certificate_enabled  = true
  client_certificate_value    = filebase64("service.crt")
  client_certificate_expiry   = "2027-01-01T00:00:00Z"

  notes = "Owner: platform-team | Used by: data pipeline"
  tags  = ["platform-team", "daemon", "production"]
}
```

**GitHub Actions using federated credentials (no secret or cert needed):**

```hcl
module "github_actions_app" {
  source = "git::https://github.com/highsmithjd/entra-app-modules.git//modules/entra-app-registration?ref=main"

  app_name  = "GitHubActions-MyRepo"
  flow_type = "daemon"

  federated_credentials = [
    {
      name    = "github-main"
      issuer  = "https://token.actions.githubusercontent.com"
      subject = "repo:my-org/my-repo:ref:refs/heads/main"
    }
  ]

  notes = "Owner: platform-team | No secrets — uses OIDC federation"
  tags  = ["platform-team", "github-actions"]
}
```

### What gets created

- `azuread_application` — the app registration
- `azuread_service_principal` — the service principal (optional via `create_service_principal`)
- `azuread_application_password` — client secret (optional)
- `azuread_application_certificate` — client certificate (optional)
- `azuread_application_federated_identity_credential` — federated OIDC credentials (optional, one per entry)

### Flow types

| `flow_type` | Use case | Redirect URIs | Credentials |
|---|---|---|---|
| `web` | Server-side web apps | Yes | Secret or cert |
| `spa` | Single-page apps (PKCE) | Yes | None (PKCE) |
| `daemon` | Services, pipelines, M2M | No | Secret, cert, or federated |
| `mobile_desktop` | Native / mobile clients | Yes | None (public client) |

### Variables

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `app_name` | Short name. Will be prefixed with `DG-`. | `string` | — | yes |
| `flow_type` | OAuth flow type: `web`, `spa`, `daemon`, `mobile_desktop`. | `string` | `"web"` | no |
| `redirect_uris` | Redirect URIs (web, spa, mobile_desktop flows). | `list(string)` | `[]` | no |
| `logout_url` | Front-channel logout URL (web flow). | `string` | `null` | no |
| `access_token_issuance_enabled` | Allow implicit access token issuance. Avoid for new apps. | `bool` | `false` | no |
| `id_token_issuance_enabled` | Allow implicit ID token issuance. Avoid for new apps. | `bool` | `false` | no |
| `client_secret_enabled` | Create a client secret. | `bool` | `false` | no |
| `client_secret_display_name` | Display name for the client secret. | `string` | `"terraform-managed"` | no |
| `client_secret_expiry_days` | Days until the client secret expires (max 730). | `number` | `365` | no |
| `client_certificate_enabled` | Upload a client certificate. | `bool` | `false` | no |
| `client_certificate_value` | Base64-encoded PEM/DER certificate value. | `string` | `null` | no |
| `client_certificate_display_name` | Display name for the certificate. | `string` | `"terraform-managed"` | no |
| `client_certificate_expiry` | Certificate expiry in RFC3339 format. | `string` | `null` | no |
| `required_resource_access` | API permissions to request. See [API Permissions](#api-permissions). | `list(object)` | `[]` | no |
| `app_roles` | Roles this app exposes to users or other apps. | `list(object)` | `[]` | no |
| `federated_credentials` | OIDC federated identity credentials. See [Federated Credentials](#federated-credentials). | `list(object)` | `[]` | no |
| `create_service_principal` | Whether to create a service principal. | `bool` | `true` | no |
| `feature_tags` | Controls portal visibility. See [Feature Tags](#feature-tags). | `object` | `{}` | no |
| `notes` | Free-text notes on the app object. | `string` | `null` | no |
| `owners` | Entra object IDs to set as app owners. | `list(string)` | `[]` | no |
| `tags` | Flat string list on the service principal. | `list(string)` | `[]` | no |

### Outputs

| Name | Description | Sensitive |
|---|---|---|
| `application_id` | Application (client) ID | no |
| `application_object_id` | Object ID of the app registration | no |
| `service_principal_object_id` | Object ID of the service principal | no |
| `display_name` | Full display name (with `DG-` prefix) | no |
| `tenant_id` | Tenant ID where the app is registered | no |
| `client_secret` | Client secret value (null if not created) | yes |
| `client_secret_expiry` | Client secret expiry date | no |
| `federated_credential_ids` | Map of federated credential names to IDs | no |

---

## Shared Concepts

### App Role Assignments

Used in `entra-enterprise-app` to control who can access the app. Each entry takes:

```hcl
app_role_assignments = [
  {
    principal_object_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    principal_type      = "Group"  # "User", "Group", or "ServicePrincipal"
  }
]
```

### API Permissions

Used in `entra-app-registration` to declare what APIs the app needs access to. Declaring permissions here does **not** grant admin consent — that must be done separately in the portal or via a `azuread_service_principal_delegated_permission_grant` resource.

```hcl
required_resource_access = [
  {
    resource_app_id = "00000003-0000-0000-c000-000000000000"  # Microsoft Graph
    resource_access = [
      { id = "e1fe6dd8-ba31-4d61-89e7-88639da4683d", type = "Scope" },  # User.Read (delegated)
      { id = "df021288-bdef-4463-88db-98f22de89214", type = "Role" }    # User.Read.All (application)
    ]
  }
]
```

Permission GUIDs can be found in the [Microsoft Graph permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference).

### Federated Credentials

Allows external OIDC tokens (GitHub Actions, AKS, GCP, etc.) to authenticate as the app without a secret or certificate.

```hcl
federated_credentials = [
  {
    name        = "github-main"
    issuer      = "https://token.actions.githubusercontent.com"
    subject     = "repo:my-org/my-repo:ref:refs/heads/main"
    description = "GitHub Actions on main branch"
    audiences   = ["api://AzureADTokenExchange"]  # default, can omit
  }
]
```

### Feature Tags

Controls how apps appear in the Entra portal and My Apps launcher.

**entra-enterprise-app defaults:**
```hcl
feature_tags = {
  enterprise            = true   # visible in Enterprise Applications
  gallery               = false
  hide                  = false  # visible in My Apps
}
```

**entra-app-registration defaults:**
```hcl
feature_tags = {
  enterprise = false  # hidden from Enterprise Applications list
  hide       = true   # hidden from My Apps
}
```

### Tags vs Notes

Entra does not support key-value tags like Azure Resource Manager. Two options are available:

- **`notes`** — free-text string on the application object. Use it for structured metadata: `"Owner: platform-team | Ticket: PLAT-123 | Env: production"`
- **`tags`** — flat list of strings on the service principal: `["platform-team", "production"]`

### Secrets and State

Client secret values are stored in Terraform state. Ensure your state backend is encrypted (Azure Blob Storage with a key, Terraform Cloud, etc.) and access is restricted. For production workloads, prefer certificates or federated credentials over secrets where possible.

---

## Examples

Full working examples are in the [`examples/`](examples/) directory:

- [`examples/enterprise-app-saml/`](examples/enterprise-app-saml/) — SAML Enterprise App with group assignments
- [`examples/app-registration-oidc/`](examples/app-registration-oidc/) — Web app, daemon with cert, and GitHub Actions federated auth
- [`examples/key-vault/`](examples/key-vault/) — Key Vault with RBAC for a team

---

## Module: entra-key-vault

Use this module to provision a dedicated Azure Key Vault for a team. Creates the resource group and vault so everything can be fully recreated by Terraform with no manual prerequisites.

Provision this **before** deploying the team's app registrations so the vault is ready to receive secrets.

### Usage

```hcl
module "key_vault" {
  source = "git::https://github.com/highsmithjd/entra-app-modules.git//modules/entra-key-vault?ref=v1.0.0"

  team_name = "compms"

  secret_readers = [
    "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # app managed identity object ID
  ]

  secret_officers = [
    "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"  # platform team group object ID
  ]

  tags = {
    env  = "prod"
    team = "compms"
  }
}
```

### What gets created

- `azurerm_resource_group` — `rg-dg-<team_name>` in Central US
- `azurerm_key_vault` — `kv-dg-<team_name>`, RBAC-enabled, Standard SKU
- `azurerm_role_assignment` — role assignments for readers, officers, and the Terraform caller

### DR note

With `purge_protection_enabled = true` (the default), a deleted vault cannot be recreated with the same name until the soft delete retention period expires (default 90 days) or the vault is manually purged. In a DR scenario, either purge the soft-deleted vault first or reduce `soft_delete_retention_days` to shorten the window.

### Variables

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `team_name` | Team name. Vault will be named `kv-dg-<team_name>`, resource group `rg-dg-<team_name>`. Lowercase, hyphens only. | `string` | — | yes |
| `location` | Azure region. | `string` | `"centralus"` | no |
| `soft_delete_retention_days` | Days to retain soft-deleted objects (7–90). | `number` | `90` | no |
| `purge_protection_enabled` | Prevent permanent deletion during retention period. | `bool` | `true` | no |
| `secret_readers` | Object IDs granted Key Vault Secrets User (read-only). | `list(string)` | `[]` | no |
| `secret_officers` | Object IDs granted Key Vault Secrets Officer (read/write). Terraform caller is always added. | `list(string)` | `[]` | no |
| `certificate_users` | Object IDs granted Key Vault Certificate User (read-only). | `list(string)` | `[]` | no |
| `certificate_officers` | Object IDs granted Key Vault Certificates Officer (read/write). | `list(string)` | `[]` | no |
| `tags` | Azure resource tags applied to the resource group and vault. | `map(string)` | `{}` | no |

### Outputs

| Name | Description |
|---|---|
| `key_vault_id` | Resource ID of the vault. Pass to `entra-app-registration` to enable secret storage. |
| `key_vault_uri` | URI of the vault (e.g. `https://kv-dg-compms.vault.azure.net/`). Give to app teams for runtime secret retrieval. |
| `key_vault_name` | Name of the vault. |
| `resource_group_name` | Name of the resource group. |
| `resource_group_id` | Resource ID of the resource group. |
