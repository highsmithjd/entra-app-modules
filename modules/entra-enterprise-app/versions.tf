terraform {
  required_version = ">= 1.3.0"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.47.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.75.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = ">= 2.0.0"
    }
  }
}
