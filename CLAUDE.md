# entra-app-modules — Claude Code Context

Terraform module library for provisioning Microsoft Entra ID apps. Two modules live here; consumers reference them by git tag.

## Modules

| Module | Use case |
|---|---|
| `modules/entra-app-registration` | OAuth 2.0 / OIDC apps — web, SPA, daemon, mobile |
| `modules/entra-enterprise-app` | SAML SSO — SaaS vendors (Google, Salesforce, etc.) |

## Naming conventions

All apps are automatically prefixed with `DG-` inside the module — do not add it manually in `app_name`.

| Resource | Pattern | Example |
|---|---|---|
| App display name | `DG-<app_name>` | `DG-OIDCDebugger` |
| Key Vault | `kv-dg-<app_slug>` | `kv-dg-oidcdebugger` |
| Resource group (auto) | `rg-dg-<app_slug>` | `rg-dg-oidcdebugger` |

`app_slug` is `app_name` lowercased with spaces replaced by hyphens.

## Versioning workflow

This repo uses semantic versioning. Consumers pin to a git tag — they never reference `main`.

1. Make changes on a feature branch (`feat/...` or `fix/...`)
2. Open a PR, get it merged to `main`
3. Tag the release: `git tag v1.x.x && git push origin v1.x.x`
4. Update consumer repos to reference the new tag

**Do not push a tag before the PR is merged.**

Current latest: check `git tag --sort=-v:refname | head -1`

## Key Vault pattern

When `create_key_vault = true`:
- The module creates a Key Vault and optionally a resource group
- The Terraform SP is automatically granted `Key Vault Secrets Officer`
- If `client_secret_enabled` is also true, the secret is written to the vault automatically
- To use a shared resource group across environments, pass `key_vault_resource_group_name` — the module will use it without creating a new one

## Security defaults

- Implicit flow (`access_token_issuance_enabled`, `id_token_issuance_enabled`) defaults to `false` — do not enable for new apps; OAuth 2.1 drops implicit flow
- Prefer certificates or federated credentials over client secrets for production
- Client secret values land in Terraform state — ensure state backend is encrypted and access-controlled

## Required Entra roles

The identity running Terraform needs:
- **Application Administrator** — full app registration and enterprise app management
- **Cloud Application Administrator** — same, minus Application Proxy

## Adding a new module

Follow the existing module structure:
- `main.tf` — resources
- `variables.tf` — all inputs with descriptions and validations
- `outputs.tf` — all useful outputs
- `versions.tf` — provider version constraints

Mirror Key Vault support from `entra-app-registration` if the new module needs secret storage.
