output "argocd_namespace" {
  description = "Namespace of the Argo CD objects"
  value       = local.argocd_namespace
}

output "argocd_password" {
  description = "Password of the local account. Read it with make argocd-password."
  value       = random_password.argocd_user.result
  sensitive   = true
}

output "argocd_capability_url" {
  description = "Argo CD UI of the capability, signed in through IAM Identity Center"
  value       = aws_eks_capability.argocd.configuration[0].argo_cd[0].server_url
}
