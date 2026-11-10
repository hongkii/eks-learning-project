# SQS -> EventBridge Pipe -> custom event bus -> rule -> API destination -> Slack chat.postMessage.
# Argo CD only writes to SQS, so this path does not change in the migration.

resource "aws_cloudwatch_event_bus" "notifications" {
  name = "${var.cluster_name}-argocd-notifications"
}

resource "aws_iam_role" "pipe" {
  name = "${var.cluster_name}-argocd-notifications-pipe"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pipes.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "pipe" {
  name = "queue-to-bus"
  role = aws_iam_role.pipe.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.notifications.arn
      },
      {
        Effect   = "Allow"
        Action   = "events:PutEvents"
        Resource = aws_cloudwatch_event_bus.notifications.arn
      },
    ]
  })
}

resource "aws_pipes_pipe" "notifications" {
  name     = "${var.cluster_name}-argocd-notifications"
  role_arn = aws_iam_role.pipe.arn
  source   = aws_sqs_queue.notifications.arn
  target   = aws_cloudwatch_event_bus.notifications.arn

  source_parameters {
    sqs_queue_parameters {
      batch_size = 1
    }
  }

  target_parameters {
    # Wrapping <$.body> in JSON keeps a JSON message body as JSON, so the rule reads $.detail.body.
    # https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-pipes-input-transformation.html
    input_template = "{\"body\": <$.body>}"

    eventbridge_event_bus_parameters {
      source      = "argocd.notifications"
      detail_type = "argocd-notification"
    }
  }

  depends_on = [aws_iam_role_policy.pipe]
}

# aws_cloudwatch_event_connection has no write-only argument, so the connection is a
# CloudFormation stack that resolves the token with a dynamic reference.
resource "aws_cloudformation_stack" "slack" {
  name = "${var.cluster_name}-argocd-slack"

  template_body = templatefile("${path.module}/cfn/slack-api-destination.yaml.tftpl", {
    name        = "${var.cluster_name}-argocd-slack"
    secret_name = local.secret_names.slack_token
  })
}

resource "aws_cloudwatch_event_rule" "slack" {
  name           = "${var.cluster_name}-argocd-to-slack"
  event_bus_name = aws_cloudwatch_event_bus.notifications.name
  event_pattern  = jsonencode({ source = ["argocd.notifications"] })
}

resource "aws_iam_role" "slack_target" {
  name = "${var.cluster_name}-argocd-to-slack"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "slack_target" {
  name = "invoke-api-destination"
  role = aws_iam_role.slack_target.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "events:InvokeApiDestination"
      Resource = aws_cloudformation_stack.slack.outputs["ApiDestinationArn"]
    }]
  })
}

resource "aws_cloudwatch_event_target" "slack" {
  rule           = aws_cloudwatch_event_rule.slack.name
  event_bus_name = aws_cloudwatch_event_bus.notifications.name
  arn            = aws_cloudformation_stack.slack.outputs["ApiDestinationArn"]
  role_arn       = aws_iam_role.slack_target.arn

  # The template message is a Block Kit array.
  input_transformer {
    input_paths = {
      blocks = "$.detail.body"
    }
    input_template = "{\"channel\": \"${var.slack_channel_id}\", \"text\": \"Argo CD notification\", \"blocks\": <blocks>}"
  }
}
