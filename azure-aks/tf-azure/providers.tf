
terraform {
  required_version = ">= 1.12.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.37.0" # https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "=2.38.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}
