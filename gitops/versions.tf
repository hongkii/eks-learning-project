terraform {
  # Ephemeral resources need 1.10 and write-only arguments need 1.11.
  required_version = ">= 1.13, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.72"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.5"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 3.0"
    }
  }
}
