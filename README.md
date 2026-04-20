# entra-app-modules

Terraform modules for deploying Microsoft Entra ID (Azure AD) applications.

- **[entra-enterprise-app](#module-entra-enterprise-app)** — SAML Enterprise Applications (for SaaS vendors like Google, Oracle, Salesforce, etc.)
- **[entra-app-registration](#module-entra-app-registration)** — OAuth 2.0 / OIDC App Registrations (for internal apps, APIs, daemons, and CI/CD pipelines)

All apps are automatically prefixed with `DG-`. The `entra-app-registration` module supports an optional Key Vault for secret and certificate storage — see [Key Vault](#key-vault) below.

---

## Requirements

| Tool | Version |
|---|---|
| OpenTofu (preferred) | >= 1.3.0 |
| Terraform (compatible) | >= 1.3.0 |
| hashicorp/azuread provider | >= 2.47.0 |
| hashicorp/null provider | >= 3.0.0 |
| hashicorp/time provider | >= 0.9.0 *(entra-app-registration only)* |
| Azure CLI (`az`) | any recent version |

The identity running Terraform needs one of the following Entra roles:
- **Application Administrator** — can create and manage app registrations and enterprise apps
- **Cloud Application Administrator** — same but cannot manage Application Proxy

---

## Module: entra-enterprise-app

Use this module for SAML-based SSO with SaaS vendors. It creates the application registration, service principal, and optionally a SAML signing certificate.

### Usage

```hcl
module "saml_app" {
  source = "git::https://github.com/highsmithjd/entra-app-modules.git//modules/entra-enterprise-app?ref=v3.0.5"

  app_name             = "MyVendorApp"
  saml_identifier_uris = ["https://myvendorapp.example.com/saml/metadata"]
  saml_reply_urls      = ["https://myvendorapp.example.com/saml/acs"]
  saml_logout_url      = "https://myvendorapp.example.com/saml/logout"

  saml_signing_certificate_enabled = true
  notification_email_addresses     = ["platform-team@example.com"]

  app_role_assignments = [
    {
      principal_object_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
      principal_type      = "Group"
    }
  ]

  saml_group_claim = {
    enabled = true
    scope   = "ApplicationGroup"
  }

  notes = "Owner: platform-team | Ticket: PLAT-1234"
}
```

### What gets created

- `azuread_application` — the app registration, linked to Entra's SAML template via `template_id`
- `azuread_service_principal` — the enterprise app instance in your tenant, set to `preferredSingleSignOnMode = saml`
- `azuread_service_principal_token_signing_certificate` — Entra-managed SAML signing certificate (optional)
- `azuread_app_role_assignment` — assigns users/groups to the app's template-created "User" role (optional)
- `null_resource` — runs `az rest` PATCHes after creation to set the Entity ID and activate the signing certificate (see below)

### How SAML works with this module

Entra acts as the Identity Provider (IdP). The SaaS vendor is the Service Provider (SP). When a user logs in:

1. The vendor redirects the user to Entra's login page
2. Entra authenticates the user and signs a SAML assertion using the signing certificate
3. Entra posts the assertion to the vendor's ACS URL (`saml_reply_urls`)
4. The vendor validates the signature using Entra's public federation metadata URL (output by this module)

The vendor never contacts your infrastructure directly — everything goes through Entra's public endpoints.

### Why Entity IDs require a post-creation PATCH

The Graph API (`POST /applications`) rejects vendor-supplied Entity IDs (e.g. `https://vendor.com/saml/metadata`) at creation time because they don't match a verified domain in your tenant. A subsequent `PATCH /applications/{id}` accepts them — provided the service principal already has `preferredSingleSignOnMode = saml`.

This module sets that property on the service principal at creation time, which qualifies the app for the [SAML verified-domain exemption](https://learn.microsoft.com/en-us/entra/identity-platform/identifier-uri-restrictions). The `null_resource` provisioner runs after the service principal is ready and PATCHes the Entity ID via the Graph API. A retry loop handles Entra's eventual consistency — the exemption sometimes takes a few seconds to propagate after the SP is created.

> **Why does the portal work but the API doesn't at creation time?**
> The Azure portal sets `preferredSingleSignOnMode = saml` before writing the Entity ID, so the exemption is already in place. The Graph API enforces the verified-domain check at `POST` time before the SP exists, and there's no way to make both happen atomically. The PATCH workaround matches what the portal does under the hood.

### Why `template_id` is required

The module sets `template_id = "8adf8e6e-67b2-4cf2-a259-e3dc5476c621"` on the `azuread_application` resource. This links the app to Entra's built-in custom SAML application template, which:

- Initializes the internal SAML configuration store that backs the portal's **Basic SAML Configuration** edit blade — without it, the blade renders read-only even when all Graph API values are correct
- Auto-creates a "User" app role used for group/user assignments (the module resolves this role dynamically)

> **Breaking change in v3.0.0:** existing apps created without `template_id` must be **destroyed and recreated** to pick up this change. In-place migration is not possible because `template_id` is a ForceNew attribute.

### Windows support

The provisioner auto-detects the operating system and uses the appropriate shell:

- **Linux / macOS** — `/bin/sh`
- **Windows** — PowerShell, writing the JSON body to a temp file to avoid Windows argument-parsing issues with inline JSON and UTF-8 BOM issues with `Set-Content`

No configuration is needed. The `use_powershell_provisioner` variable is accepted for backwards compatibility but is ignored.

### Variables

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `app_name` | Short name. Will be prefixed with `DG-`. | `string` | — | yes |
| `saml_identifier_uris` | SAML Entity IDs / Audience URIs provided by the SP. | `list(string)` | `[]` | no |
| `saml_reply_urls` | Assertion Consumer Service (ACS) URLs. | `list(string)` | `[]` | no |
| `saml_logout_url` | Single logout URL. | `string` | `null` | no |
| `saml_signing_certificate_enabled` | Create an Entra-managed SAML signing certificate. | `bool` | `true` | no |
| `saml_certificate_display_name` | Display name for the signing cert. Defaults to `CN=DG-<app_name>`. | `string` | `null` | no |
| `saml_group_claim` | Emit a groups claim in the SAML token. See [Groups Claim](#groups-claim). | `object` | `{}` | no |
| `notification_email_addresses` | Emails to notify when the signing certificate is near expiry. | `list(string)` | `[]` | no |
| `app_role_assignments` | Users/groups to assign to the app. See [App Role Assignments](#app-role-assignments). | `list(object)` | `[]` | no |
| `feature_tags` | Controls portal visibility. See [Feature Tags](#feature-tags). | `object` | `{}` | no |
| `notes` | Free-text notes on the app object (owner, team, ticket, etc.). | `string` | `null` | no |
| `owners` | Entra object IDs to set as app owners. The Terraform caller is always added. | `list(string)` | `[]` | no |

### Groups Claim

Controls whether and how group membership is included in the SAML token. Useful when the SP needs to know which groups a user belongs to for authorization decisions.

```hcl
saml_group_claim = {
  enabled = true
  scope   = "ApplicationGroup"  # only groups assigned to this app (recommended)
  format  = []                  # emit Object IDs (default); see below for alternatives
}
```

| `scope` | What's included |
|---|---|
| `ApplicationGroup` | Only groups assigned to this app (recommended — keeps tokens small) |
| `SecurityGroup` | All security groups the user is a member of |
| `DirectoryRole` | Azure AD directory roles |
| `All` | All groups and directory roles |

| `format` | Value emitted per group |
|---|---|
| `[]` | Object ID / GUID (default) |
| `["cloud_displayname"]` | Display name (cloud-only groups) |
| `["sam_account_name"]` | sAMAccountName (on-prem synced groups) |
| `["dns_domain_and_sam_account_name"]` | DNS\sAMAccountName (on-prem synced groups) |

### Outputs

| Name | Description | Sensitive |
|---|---|---|
| `application_id` | Application (client) ID | no |
| `application_object_id` | Object ID of the app registration | no |
| `service_principal_object_id` | Object ID of the service principal | no |
| `display_name` | Full display name (with `DG-` prefix) | no |
| `saml_metadata_url` | Entra federation metadata URL — give this to the SP vendor | no |
| `signing_certificate` | Cert thumbprint, display name, expiry, and value | yes |

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

## Key Vault

Both modules support an optional Azure Key Vault per app. When enabled, the module creates the vault and grants the Terraform service principal the necessary roles automatically.

### Prerequisites

Before enabling Key Vault features, the following must be in place:

**Azure subscription**
An active Azure subscription is required. Key Vaults and resource groups are Azure resources — they are separate from Entra ID and incur Azure costs.

**Pipeline service principal permissions**
The identity running Terraform (e.g. a CI/CD service principal) needs the following at the subscription or resource group scope:

| What | Why |
|---|---|
| `Contributor` on the subscription or resource group | Create and manage resource groups and Key Vaults |
| `User Access Administrator` on the subscription or resource group | Assign RBAC roles to the vault (the module does this automatically for secrets and certificates) |

Or use the built-in **`Owner`** role which covers both. Without `User Access Administrator`, the module will fail when it tries to assign itself `Key Vault Secrets Officer` or `Key Vault Certificates Officer`.

**Entra roles**
These are unchanged from the base module requirements — `Application Administrator` or `Cloud Application Administrator`.

### Basic usage

```hcl
module "app" {
  source = "git::https://github.com/highsmithjd/entra-app-modules.git//modules/entra-app-registration?ref=v2.0.0"

  app_name = "MyApp"

  create_key_vault = true
  # Vault is named kv-dg-myapp and placed in rg-dg-myapp (auto-created)
}
```

### Resource group per environment

Each environment is fully self-contained — the module creates its own resource group and Key Vault. When `key_vault_resource_group_name` is not set (the default), the module auto-creates a resource group named `rg-dg-<app_slug>`.

The recommended deployment model is **one repo per environment**, with each repo managing a single environment independently:

```
dg-myapp-nonprod/   → sbx environment → rg-dg-myapp-sbx + kv-dg-myapp-sbx
dg-myapp-prod/      → prod environment → rg-dg-myapp-prod + kv-dg-myapp-prod
```

This gives full isolation — destroying sbx cannot affect prod, and RBAC on the repo controls who can deploy to each environment. There is no shared state between environments.

If you need to override the resource group (e.g. to use a pre-existing one), set `key_vault_resource_group_name` explicitly.

### Client secret storage

When both `create_key_vault = true` and `client_secret_enabled = true`, the client secret is automatically written to the vault as `<app_slug>-client-secret`.

### Key Vault-managed certificates

When `create_key_vault_certificate = true`, the module generates a self-signed RSA certificate inside Key Vault and uploads the public key to Entra automatically. The private key never leaves Key Vault.

```hcl
module "app" {
  source = "git::https://github.com/highsmithjd/entra-app-modules.git//modules/entra-app-registration?ref=v2.0.0"

  app_name = "MyApp"

  create_key_vault             = true
  create_key_vault_certificate = true

  key_vault_certificate_validity_months = 12   # default
  key_vault_certificate_key_size        = 2048 # default, or 4096
  key_vault_certificate_subject         = "CN=MyApp" # defaults to CN=DG-<app_name>
}
```

To export the PFX after apply (e.g. to send to a vendor):

```bash
# Download from Key Vault (produces a binary PKCS#12)
az keyvault secret download \
  --vault-name kv-dg-myapp \
  --name myapp-cert \
  --file myapp.pfx \
  --encoding base64

# Re-encrypt with a password before sending to the vendor
openssl pkcs12 -in myapp.pfx -out temp.pem -passin pass: -nodes
openssl pkcs12 -export -in temp.pem -out myapp-protected.pfx -passout pass:YourPasswordHere
rm temp.pem
```

Share the password with the vendor out-of-band — not in the same message as the file.

### Key Vault variables (both modules)

| Name | Description | Type | Default |
|---|---|---|---|
| `create_key_vault` | Create a dedicated Key Vault for this app. | `bool` | `false` |
| `key_vault_resource_group_name` | Use an existing resource group instead of creating one. | `string` | `null` |
| `key_vault_location` | Azure region for the vault. | `string` | `"centralus"` |
| `key_vault_soft_delete_retention_days` | Soft delete retention (7–90 days). | `number` | `90` |
| `key_vault_purge_protection_enabled` | Prevent permanent deletion during retention period. | `bool` | `true` |
| `key_vault_secret_readers` | Object IDs granted `Key Vault Secrets User` on the vault. | `list(string)` | `[]` |

### Key Vault certificate variables (entra-app-registration only)

| Name | Description | Type | Default |
|---|---|---|---|
| `create_key_vault_certificate` | Generate a self-signed cert in Key Vault and upload to Entra. Requires `create_key_vault = true`. | `bool` | `false` |
| `key_vault_certificate_slots` | Named certificate slots. See [Certificate rotation](#certificate-rotation). | `list(string)` | `["primary"]` |
| `key_vault_certificate_subject` | Subject DN. Defaults to `CN=DG-<app_name>`. | `string` | `null` |
| `key_vault_certificate_validity_months` | Validity period in months (1–120). | `number` | `12` |
| `key_vault_certificate_key_size` | RSA key size: `2048` or `4096`. | `number` | `2048` |

### Key Vault outputs (entra-app-registration)

| Name | Description |
|---|---|
| `key_vault_uri` | URI of the Key Vault. |
| `key_vault_secret_name` | Name of the client secret in Key Vault. |
| `key_vault_certificate_names` | Map of slot name to Key Vault certificate name (e.g. `{ primary = "myapp-cert-primary" }`). |
| `key_vault_certificate_thumbprints` | Map of slot name to certificate thumbprint. |
| `key_vault_certificate_expiries` | Map of slot name to certificate expiry date. |

### Certificate rotation

All cert slots are registered in Entra simultaneously, so you can rotate without downtime:

**Step 1 — add the secondary slot:**
```hcl
key_vault_certificate_slots = ["primary", "secondary"]
```
Apply. Both certs are now valid in Entra. Export `<app_slug>-cert-secondary` from Key Vault, password-protect it, and send it to the vendor.

**Step 2 — wait for the vendor to confirm the new cert works.**

**Step 3 — remove the old slot:**
```hcl
key_vault_certificate_slots = ["secondary"]
```
Apply. The old cert is removed from Entra and deleted from Key Vault.

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

Full working examples are in the [`examples/`](examples/) directory. Each example is a single self-contained environment — one `main.tf` and one `backend.tf`. Deploy one copy per environment, each in its own repo.

- [`examples/enterprise-app-saml/`](examples/enterprise-app-saml/) — SAML Enterprise App with group assignments
- [`examples/app-registration-oidc/`](examples/app-registration-oidc/) — OIDC web app with Key Vault-managed certificate
- [`examples/multi-env-web-app/`](examples/multi-env-web-app/) — Web app showing sbx and prod as independent self-contained deployments
