resource "helm_release" "argocd" {
  name       = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "10.17.1"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name

  values = [
    file("${path.module}/helm/values.yaml"),
    templatefile("${path.module}/helm/sso-values.yaml.tftpl", {
      argocd_url   = local.argocd_url
      client_id    = var.dex_github_client_id
      admin_emails = var.argocd_admin_emails
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
    file("${path.module}/helm/scaled-down-values.yaml"),
  ]

  depends_on = [kubernetes_secret_v1.dex_github]
}

# Referenced from dex.config as $argocd-dex-github:clientSecret.
# https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/#sensitive-data-and-sso-client-secrets
ephemeral "aws_secretsmanager_secret_version" "dex_github" {
  secret_id = local.secret_names.dex_github
}

resource "kubernetes_secret_v1" "dex_github" {
  metadata {
    name      = "argocd-dex-github"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    labels    = { "app.kubernetes.io/part-of" = "argocd" }
  }

  data_wo = {
    clientSecret = ephemeral.aws_secretsmanager_secret_version.dex_github.secret_string
  }
  # Write-only data is not compared on plan. Increment to push a rotated value.
  data_wo_revision = 1
}

ephemeral "aws_secretsmanager_secret_version" "github_repo" {
  secret_id = local.secret_names.github_repo
}

# https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#repositories
resource "kubernetes_secret_v1" "repo" {
  metadata {
    name      = "argocd-repo-demo"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    labels    = { "argocd.argoproj.io/secret-type" = "repository" }
  }

  data_wo = {
    type     = "git"
    url      = var.repo_url
    project  = "default"
    username = jsondecode(ephemeral.aws_secretsmanager_secret_version.github_repo.secret_string).username
    password = jsondecode(ephemeral.aws_secretsmanager_secret_version.github_repo.secret_string).password
  }
  data_wo_revision = 1
}
