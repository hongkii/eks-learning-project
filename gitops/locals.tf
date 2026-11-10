locals {
  argocd_namespace = "gitops"

  # The self-managed UI is reached with kubectl port-forward on this URL.
  argocd_url = "https://localhost:8080"

  # Created by hand and read by name. The value never enters the Terraform state.
  secret_names = {
    slack_token = "argocd/slack-token"
  }

  # Manifests are in argocd-demo/ of this repository.
  applications = {
    app-auto = {
      namespace   = "demo-auto"
      path        = "argocd-demo/env/auto"
      sync_policy = { syncPolicy = { automated = { prune = true } } }
    }
    app-manual = {
      namespace   = "demo-manual"
      path        = "argocd-demo/env/manual"
      sync_policy = {}
    }
  }
}
