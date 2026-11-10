# https://docs.aws.amazon.com/eks/latest/userguide/capability-role.html
resource "aws_iam_role" "argocd_capability" {
  name = "${var.cluster_name}-argocd-capability"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "capabilities.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

data "aws_secretsmanager_secret" "github_repo" {
  name = local.secret_names.github_repo
}

resource "aws_iam_role_policy" "argocd_capability" {
  name = "argocd-capability"
  role = aws_iam_role.argocd_capability.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # awssqs authenticates with the capability role instead of IRSA.
        # https://docs.aws.amazon.com/eks/latest/userguide/argocd-notifications.html
        Sid      = "SendToQueue"
        Effect   = "Allow"
        Action   = ["sqs:GetQueueUrl", "sqs:SendMessage"]
        Resource = aws_sqs_queue.notifications.arn
      },
      {
        # https://docs.aws.amazon.com/eks/latest/userguide/integration-secrets-manager.html
        Sid      = "ReadRepositoryCredentials"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = data.aws_secretsmanager_secret.github_repo.arn
      },
      {
        Sid      = "DecryptRepositoryCredentials"
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = "arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:key/*"
        Condition = {
          StringLike = {
            "kms:EncryptionContext:SecretARN" = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:argocd/*"
            "kms:ViaService"                  = "secretsmanager.*.amazonaws.com"
          }
        }
      },
    ]
  })
}

resource "aws_eks_capability" "argocd" {
  cluster_name    = var.cluster_name
  capability_name = "argocd"
  type            = "ARGOCD"
  role_arn        = aws_iam_role.argocd_capability.arn

  # The only value. Argo CD resources and CRDs stay in the cluster after deletion.
  delete_propagation_policy = "RETAIN"

  configuration {
    argo_cd {
      # The primary namespace cannot be changed after creation.
      namespace = local.argocd_namespace

      aws_idc {
        idc_instance_arn = local.idc_instance_arn
      }

      rbac_role_mapping {
        role = "ADMIN"
        identity {
          id   = aws_identitystore_group.argocd_admins.group_id
          type = "SSO_GROUP"
        }
      }
    }
  }

  # The self-managed controllers are at zero replicas before the capability starts.
  depends_on = [helm_release.argocd, aws_iam_role_policy.argocd_capability]
}
