# The capability does not register the local cluster, and kubernetes.default.svc is not supported.
# The name in-cluster keeps compatibility with examples that use it.
# https://docs.aws.amazon.com/eks/latest/userguide/argocd-register-clusters.html
resource "kubernetes_secret_v1" "in_cluster" {
  metadata {
    name      = "in-cluster"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    labels    = { "argocd.argoproj.io/secret-type" = "cluster" }
  }

  data = {
    name    = "in-cluster"
    server  = data.aws_eks_cluster.this.arn
    project = "default"
  }
}
