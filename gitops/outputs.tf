output "argocd_namespace" {
  description = "Namespace of the Argo CD objects"
  value       = local.argocd_namespace
}

output "argocd_password" {
  description = "Password of the local account. Read it with make argocd-password."
  value       = random_password.argocd_user.result
  sensitive   = true
}
