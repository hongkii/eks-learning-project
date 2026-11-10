variable "aws_region" {
  description = "AWS region of the cluster"
  type        = string
  default     = "ap-northeast-1"
}

variable "cluster_name" {
  description = "EKS cluster created by ../terraform"
  type        = string
  default     = "my-study-eks"
}

variable "repo_url" {
  description = "HTTPS URL of the private Git repository that holds the application manifests"
  type        = string
}

variable "target_revision" {
  description = "Git revision the Applications track"
  type        = string
  default     = "main"
}

variable "dex_github_client_id" {
  description = "Client ID of the GitHub OAuth App that Dex uses"
  type        = string
}

variable "argocd_admin_emails" {
  description = "E-mail addresses mapped to role:admin in the self-managed Argo CD"
  type        = list(string)
}

variable "slack_channel_id" {
  description = "Slack channel ID that receives the notifications"
  type        = string
}

variable "idc_user" {
  description = "IAM Identity Center user that signs in to the Argo CD capability"
  type = object({
    user_name   = string
    email       = string
    given_name  = string
    family_name = string
  })
}
