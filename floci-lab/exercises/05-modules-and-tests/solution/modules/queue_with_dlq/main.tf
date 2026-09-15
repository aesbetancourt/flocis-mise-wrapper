# Module queue_with_dlq — resources. Solution.
#
# A module has no provider block. It uses the aws provider of the root module.

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# The dead-letter queue keeps the messages that failed too many times.
resource "aws_sqs_queue" "dlq" {
  name = "${var.name}-dlq"

  # Keep failed messages for 14 days, the SQS maximum.
  message_retention_seconds = 1209600

  tags = var.tags
}

resource "aws_sqs_queue" "main" {
  name                       = var.name
  visibility_timeout_seconds = var.visibility_timeout_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = var.tags
}
