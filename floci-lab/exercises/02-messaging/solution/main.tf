# Exercise 02 — Messaging. Solution.

resource "aws_sns_topic" "orders" {
  name = "ex02-orders"
}

# Billing messages that fail two times go here.
resource "aws_sqs_queue" "billing_dlq" {
  name = "ex02-billing-dlq"
}

resource "aws_sqs_queue" "billing" {
  name = "ex02-billing"

  # A received message stays hidden for 5 seconds. Then SQS can deliver it
  # again. A short timeout makes the retries in Part C fast.
  visibility_timeout_seconds = 5

  # After 2 receives without a delete, the next receive moves the message to
  # the DLQ.
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.billing_dlq.arn
    maxReceiveCount     = 2
  })
}

resource "aws_sqs_queue" "shipping" {
  name = "ex02-shipping"
}

# Lets the topic send messages to a queue. On real AWS, SNS cannot deliver to
# the queue without this policy. Floci delivers the messages without it.
data "aws_iam_policy_document" "topic_to_queue" {
  for_each = {
    billing  = aws_sqs_queue.billing.arn
    shipping = aws_sqs_queue.shipping.arn
  }

  statement {
    sid       = "AllowOrdersTopic"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [each.value]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.orders.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "billing" {
  queue_url = aws_sqs_queue.billing.id
  policy    = data.aws_iam_policy_document.topic_to_queue["billing"].json
}

resource "aws_sqs_queue_policy" "shipping" {
  queue_url = aws_sqs_queue.shipping.id
  policy    = data.aws_iam_policy_document.topic_to_queue["shipping"].json
}

# Billing gets the raw message body: the order JSON only.
resource "aws_sns_topic_subscription" "billing" {
  topic_arn            = aws_sns_topic.orders.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.billing.arn
  raw_message_delivery = true
}

# Shipping gets the SNS envelope. The order JSON is in its Message field.
resource "aws_sns_topic_subscription" "shipping" {
  topic_arn = aws_sns_topic.orders.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.shipping.arn
}

output "topic_arn" {
  value = aws_sns_topic.orders.arn
}

output "billing_queue_url" {
  value = aws_sqs_queue.billing.url
}

output "shipping_queue_url" {
  value = aws_sqs_queue.shipping.url
}

output "billing_dlq_url" {
  value = aws_sqs_queue.billing_dlq.url
}
