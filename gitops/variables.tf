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
  description = "Public Git repository that holds the application manifests"
  type        = string
  default     = "https://github.com/hongkii/eks-learning-project.git"
}

variable "target_revision" {
  description = "Git revision the Applications track"
  type        = string
  default     = "main"
}

variable "argocd_user" {
  description = "Local account of the self-managed Argo CD, mapped to role:admin"
  type        = string
  default     = "hongkii"
}

variable "slack_channel_id" {
  description = "Slack channel ID that receives the notifications"
  type        = string
}
