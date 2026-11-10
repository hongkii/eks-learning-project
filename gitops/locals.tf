locals {
  argocd_namespace = "gitops"

  # The self-managed UI is reached with kubectl port-forward on this URL.
  argocd_url = "https://localhost:8080"

  # Created by hand and read by name. Values never enter the Terraform state.
  secret_names = {
    github_repo = "argocd/github-repo"
    dex_github  = "argocd/dex-github"
    slack_token = "argocd/slack-token"
  }

  applications = {
    app-auto = {
      namespace   = "demo-auto"
      path        = "env/auto"
      sync_policy = { syncPolicy = { automated = { prune = true } } }
    }
    app-manual = {
      namespace   = "demo-manual"
      path        = "env/manual"
      sync_policy = {}
    }
  }
}
