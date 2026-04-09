# Example: Multi-Environment Web App

This example shows how to structure a consumer repo for a web app deployed across multiple environments (sbx and prod) using a shared Azure resource group.

## Directory structure

```
├── shared/     # Shared infrastructure — owns the resource group
│   └── main.tf
├── sbx/        # Sandbox environment
│   └── main.tf
└── prod/       # Production environment
    └── main.tf
```

Each directory has its own Terraform state, so environments are fully isolated. Destroying one environment cannot impact another.

## Why a shared directory?

Every app deployment uses a `shared/` directory to own the Azure resource group. This is the standard pattern — even if you start with only `sbx`.

Key Vaults must live in a resource group. If one environment owned the resource group, destroying that environment would delete the resource group — and every other environment's Key Vault with it. By giving the resource group its own Terraform state in `shared/`, no single environment can destroy it accidentally.

Start with `shared/` from day one. Adding `prod/` later is straightforward; untangling a resource group from an existing environment's state is not. The `destroy:shared` job should only be run when retiring the app entirely, after all other environments have been destroyed.

## Apply order

**Provisioning:**
```
shared → sbx
       → prod
```
`shared` must be applied first. After that, `sbx` and `prod` are independent and can be applied in any order.

**Deprovisioning (when retiring the app):**
```
prod → sbx → shared
```
Always destroy `shared` last. Destroying it first will delete the resource group and all Key Vaults inside it.

## Adapting this example

- Replace `MyWebApp` with your app name throughout
- Update `redirect_uris` and `logout_url` for your actual URLs
- Update `required_resource_access` with the Graph permissions your app needs
- Replace the `backend "http" {}` blocks with your backend configuration
- If you need `dev`, `stage`, `prod` instead of `sbx`, `prod` — just rename the directories and follow the same pattern. The `shared/` directory and apply/destroy order remain the same.

## Exporting the Key Vault secret

After applying sbx or prod, the client secret is automatically stored in Key Vault. To retrieve it:

```bash
az keyvault secret show \
  --vault-name kv-dg-mywebapp-sbx \
  --name mywebapp-sbx-client-secret \
  --query value -o tsv
```
