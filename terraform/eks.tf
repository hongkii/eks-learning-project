# EKS cluster, KMS key, CloudWatch log group and managed addons.

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids = aws_subnet.private[*].id

    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs

    security_group_ids = [aws_security_group.eks_cluster.id]
  }

  # Access entries need API or API_AND_CONFIG_MAP. The EKS API default is CONFIG_MAP.
  # https://docs.aws.amazon.com/eks/latest/userguide/setting-up-access-entries.html
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # Enabling all log types increases CloudWatch ingestion cost.
  # https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html
  enabled_cluster_log_types = var.enabled_cluster_log_types

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_cloudwatch_log_group.eks_cluster,
  ]

  tags = {
    Name = var.cluster_name
  }
}

resource "aws_kms_key" "eks" {
  description             = "EKS Secret Encryption Key for ${var.cluster_name}"
  deletion_window_in_days = 7

  tags = {
    Name = "${var.cluster_name}-eks-encryption-key"
  }
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.cluster_name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.cluster_name}-cluster-logs"
  }
}

# Addon versions are resolved from kubernetes_version, so one apply moves the
# cluster and the addons together. A rollback needs the addons brought down too.
# https://docs.aws.amazon.com/eks/latest/userguide/rollback-cluster.html
data "aws_eks_addon_version" "this" {
  for_each = toset(["aws-ebs-csi-driver", "coredns", "kube-proxy", "vpc-cni"])

  addon_name         = each.value
  kubernetes_version = var.kubernetes_version
  most_recent        = var.addon_most_recent
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "aws-ebs-csi-driver"
  addon_version = data.aws_eks_addon_version.this["aws-ebs-csi-driver"].version

  service_account_role_arn = aws_iam_role.ebs_csi_driver.arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_node_group.main
  ]

  tags = {
    Name = "${var.cluster_name}-ebs-csi-addon"
  }
}

resource "aws_eks_addon" "coredns" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "coredns"
  addon_version = data.aws_eks_addon_version.this["coredns"].version

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_node_group.main
  ]

  tags = {
    Name = "${var.cluster_name}-coredns-addon"
  }
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "kube-proxy"
  addon_version = data.aws_eks_addon_version.this["kube-proxy"].version

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # A DaemonSet needs no nodes, and installing it before the nodes join means they
  # start with the right version.
  depends_on = [aws_eks_cluster.main]

  tags = {
    Name = "${var.cluster_name}-kube-proxy-addon"
  }
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "vpc-cni"
  addon_version = data.aws_eks_addon_version.this["vpc-cni"].version

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # A DaemonSet needs no nodes, and installing it before the nodes join means they
  # start with the right version.
  depends_on = [aws_eks_cluster.main]

  tags = {
    Name = "${var.cluster_name}-vpc-cni-addon"
  }
}
