# Example: Multi-Environment Web App

This example shows how to deploy the same app across multiple environments (sbx and prod) using independent, self-contained deployments.

## Directory structure

```
├── sbx/     # Sandbox environment — deploy from dg-entra-apps-nonprod/<app>
│   ├── main.tf
│   └── backend.tf
└── prod/    # Production environment — deploy from dg-entra-apps-prod/<app>
    ├── main.tf
    └── backend.tf
```

Each directory is a fully independent Terraform root with its own state. They share no resources — each creates its own resource group and Key Vault in its own Azure subscription.

## Deployment model

Each environment lives in a separate GitLab repo under the appropriate group:

```
dg-entra-apps-nonprod/dg-mywebapp   → deploys sbx/
dg-entra-apps-prod/dg-mywebapp      → deploys prod/
```

Access control is handled at the GitLab group level — Level 2 engineers get access to `dg-entra-apps-nonprod` only. There are no shared resources that could be accidentally destroyed.

## Apply and destroy

Environments are fully independent — apply or destroy either one at any time without affecting the other.

## Adapting this example

- Replace `MyWebApp` with your app name throughout
- Update `redirect_uris` and `logout_url` for your actual URLs
- Update `required_resource_access` with the Graph permissions your app needs
- Replace the `backend "http" {}` blocks with your backend configuration
