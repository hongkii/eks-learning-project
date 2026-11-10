resource "kubectl_manifest" "application" {
  for_each = local.applications

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = each.key
      namespace = local.argocd_namespace
      # Deleting the Application also deletes the resources it deployed.
      # https://argo-cd.readthedocs.io/en/stable/user-guide/app_deletion/#about-the-deletion-finalizer
      finalizers  = ["resources-finalizer.argocd.argoproj.io"]
      annotations = local.notification_subscriptions
    }
    spec = merge({
      project = "default"
      source = {
        repoURL        = var.repo_url
        targetRevision = var.target_revision
        path           = each.value.path
      }
      destination = {
        name      = "in-cluster"
        namespace = each.value.namespace
      }
    }, each.value.sync_policy)
  })

  # Deleted before the capability, so the finalizer runs while a controller is there.
  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.in_cluster,
    kubernetes_namespace_v1.apps,
    aws_eks_capability.argocd,
    aws_eks_access_policy_association.argocd_edit,
    kubernetes_cluster_role_binding_v1.argocd_read_all,
  ]
}
