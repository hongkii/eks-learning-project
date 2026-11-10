resource "helm_release" "argocd" {
  name       = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "10.17.1"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name

  values = [
    file("${path.module}/helm/values.yaml"),
    # A local account in place of SSO. Local accounts are not supported by the capability.
    # https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/#local-usersaccounts
    yamlencode({
      configs = {
        cm = {
          "admin.enabled"               = false
          url                           = local.argocd_url
          "accounts.${var.argocd_user}" = "login"
        }
        rbac = {
          # No policy.default, so an account that is not listed gets no role.
          "policy.csv" = "g, ${var.argocd_user}, role:admin\n"
        }
      }
    }),
    yamlencode({
      notifications = {
        argocdUrl = local.argocd_url
        # .Local in the templates follows TZ.
        extraEnv = [{ name = "TZ", value = "Asia/Tokyo" }]
        serviceAccount = {
          annotations = { "eks.amazonaws.com/role-arn" = aws_iam_role.notifications.arn }
        }
        notifiers = local.notifications_services
        templates = local.notifications_templates
        triggers  = local.notifications_triggers
      }
    }),
  ]

  # Stored in argocd-secret. `make argocd-password` prints the password.
  set_sensitive = [{
    name  = "configs.secret.extra.accounts\\.${var.argocd_user}\\.password"
    value = random_password.argocd_user.bcrypt_hash
  }]
}

resource "random_password" "argocd_user" {
  length  = 24
  special = false
}
