# Capability controllers run outside the cluster. Their logs are vended logs keyed by the capability ARN.
# https://docs.aws.amazon.com/eks/latest/userguide/capabilities-controller-logs.html
locals {
  capability_log_types = {
    application  = "EKS_CAPABILITY_ARGOCD_APPLICATION_LOGS"
    notification = "EKS_CAPABILITY_ARGOCD_NOTIFICATION_LOGS"
  }
}

resource "aws_cloudwatch_log_group" "argocd_capability" {
  for_each = local.capability_log_types

  name              = "/aws/eks/${var.cluster_name}/capabilities/argocd/${each.key}"
  retention_in_days = 1
}

resource "aws_cloudwatch_log_delivery_source" "argocd_capability" {
  for_each = local.capability_log_types

  name         = "${var.cluster_name}-argocd-${each.key}"
  log_type     = each.value
  resource_arn = aws_eks_capability.argocd.arn
}

resource "aws_cloudwatch_log_delivery_destination" "argocd_capability" {
  for_each = local.capability_log_types

  name = "${var.cluster_name}-argocd-${each.key}"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.argocd_capability[each.key].arn
  }
}

resource "aws_cloudwatch_log_delivery" "argocd_capability" {
  for_each = local.capability_log_types

  delivery_source_name     = aws_cloudwatch_log_delivery_source.argocd_capability[each.key].name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.argocd_capability[each.key].arn
}
