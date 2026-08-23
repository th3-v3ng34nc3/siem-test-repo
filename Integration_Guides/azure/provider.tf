terraform {
  required_version = "~> 1.12"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.32.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "3.7.2"
    }

  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
