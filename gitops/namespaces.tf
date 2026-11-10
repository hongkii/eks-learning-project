resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = local.argocd_namespace
  }
}

resource "kubernetes_namespace_v1" "apps" {
  for_each = local.applications

  metadata {
    name = each.value.namespace
  }
}
