# The capability reads supported settings from argocd-cm in its namespace.
# https://docs.aws.amazon.com/eks/latest/userguide/argocd-configure-settings.html
resource "kubernetes_config_map_v1" "argocd_cm" {
  metadata {
    name      = "argocd-cm"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    labels    = { "app.kubernetes.io/part-of" = "argocd" }
  }

  data = {
    # Same value as the Helm release. --load-restrictor is not a supported build option.
    "kustomize.buildOptions" = "--load-restrictor LoadRestrictionsNone"
  }

  # The Helm release stops rendering argocd-cm in the same apply.
  depends_on = [helm_release.argocd]
}

# The notifications controller ignores a ConfigMap without the opt-in label.
# https://docs.aws.amazon.com/eks/latest/userguide/argocd-notifications.html
resource "kubernetes_config_map_v1" "argocd_notifications_cm" {
  metadata {
    name      = "argocd-notifications-cm"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    labels    = { "eks.amazonaws.com/managed-notifications" = "enabled" }
  }

  data = merge(
    { context = yamlencode({ argocdUrl = aws_eks_capability.argocd.configuration[0].argo_cd[0].server_url }) },
    local.notifications_services,
    local.notifications_templates,
    local.notifications_triggers,
  )

  # The Helm release stops rendering argocd-notifications-cm in the same apply.
  depends_on = [helm_release.argocd]
}
