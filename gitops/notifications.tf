locals {
  # Trigger conditions follow the upstream notifications catalog.
  # https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/catalog/
  notification_events = {
    deployed = {
      title    = ":white_check_mark: Deployed"
      when     = "app.status.operationState != nil and app.status.operationState.phase in ['Succeeded'] and app.status.health.status == 'Healthy'"
      once_per = "app.status.operationState?.syncResult?.revision"
    }
    health-degraded = {
      title    = ":warning: Health degraded"
      when     = "app.status.health.status == 'Degraded'"
      once_per = null
    }
    sync-failed = {
      title    = ":x: Sync failed"
      when     = "app.status.operationState != nil and app.status.operationState.phase in ['Error', 'Failed']"
      once_per = null
    }
    sync-status-unknown = {
      title    = ":grey_question: Sync status unknown"
      when     = "app.status.sync.status == 'Unknown'"
      once_per = null
    }
    sync-succeeded = {
      title    = ":large_green_circle: Sync succeeded"
      when     = "app.status.operationState != nil and app.status.operationState.phase in ['Succeeded']"
      once_per = null
    }
    sync-status-outofsync = {
      title    = ":large_yellow_circle: Out of sync"
      when     = "app.status.sync.status == 'OutOfSync'"
      once_per = null
    }
  }

  # Keys of argocd-notifications-cm. The Helm chart renders them on branch A.
  notifications_services = {
    "service.awssqs" = yamlencode({
      queue  = aws_sqs_queue.notifications.name
      region = var.aws_region
    })
  }

  notifications_triggers = {
    for name, e in local.notification_events : "trigger.on-${name}" => yamlencode([
      { for k, v in { when = e.when, oncePer = e.once_per, send = ["app-${name}"] } : k => v if v != null }
    ])
  }

  notifications_templates = {
    for name, e in local.notification_events : "template.app-${name}" => yamlencode({
      message = templatefile("${path.module}/notifications/block-kit.json.tftpl", { title = e.title })
    })
  }

  # An empty recipient sends to the queue in service.awssqs.
  notification_subscriptions = {
    for name in keys(local.notification_events) : "notifications.argoproj.io/subscribe.on-${name}.awssqs" => ""
  }
}

resource "aws_sqs_queue" "notifications" {
  name                      = "${var.cluster_name}-argocd-notifications"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 86400
}

data "aws_iam_openid_connect_provider" "eks" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

locals {
  oidc_issuer = replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
}

# IRSA for the notifications controller of the self-managed Argo CD.
resource "aws_iam_role" "notifications" {
  name = "${var.cluster_name}-argocd-notifications"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.eks.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:${local.argocd_namespace}:argocd-notifications-controller"
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "notifications" {
  name = "send-to-queue"
  role = aws_iam_role.notifications.id

  # The controller looks up the queue URL before each send, so SendMessage alone is not enough.
  # https://docs.aws.amazon.com/eks/latest/userguide/argocd-notifications.html
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:GetQueueUrl", "sqs:SendMessage"]
      Resource = aws_sqs_queue.notifications.arn
    }]
  })
}
