provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "EKS-Study"
      ManagedBy = "Terraform"
      Purpose   = "ArgoCD-Migration"
    }
  }
}

# The cluster belongs to ../terraform. Reading it here keeps one apply from both
# creating the cluster and configuring providers against it.
data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_caller_identity" "current" {}

locals {
  cluster_ca = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

  # exec fetches a fresh token per run, so a long apply does not outlive it.
  # https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs#exec-plugins
  kube_exec = {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.aws_region]
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = local.cluster_ca

  exec {
    api_version = local.kube_exec.api_version
    command     = local.kube_exec.command
    args        = local.kube_exec.args
  }
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = local.cluster_ca
    exec                   = local.kube_exec
  }
}

provider "kubectl" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = local.cluster_ca
  load_config_file       = false

  exec {
    api_version = local.kube_exec.api_version
    command     = local.kube_exec.command
    args        = local.kube_exec.args
  }
}
