# The capability creates an access entry for its role. Deploying needs write access to the
# application namespaces and read access to every resource type for health checks.
# https://docs.aws.amazon.com/eks/latest/userguide/argocd-register-clusters.html
resource "aws_eks_access_policy_association" "argocd_edit" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.argocd_capability.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = [for app in local.applications : app.namespace]
  }

  depends_on = [aws_eks_capability.argocd]
}

resource "kubernetes_cluster_role_v1" "argocd_read_all" {
  metadata {
    name = "argocd-capability-read-all"
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "argocd_read_all" {
  metadata {
    name = "argocd-capability-read-all"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.argocd_read_all.metadata[0].name
  }

  # Access entries map to the group eks-access-entry:<principal ARN>.
  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Group"
    name      = "eks-access-entry:${aws_iam_role.argocd_capability.arn}"
  }
}
