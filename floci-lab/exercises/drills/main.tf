# Drills — a small fixed stack. All drills use it.
#
# Read README.md before you change this file. Each drill ends with a Reset step
# that returns this file to its clean state.

resource "aws_sqs_queue" "orders" {
  name                       = "drill-orders"
  visibility_timeout_seconds = 30

  tags = {
    owner = "drills"
  }
}

resource "aws_sns_topic" "events" {
  name = "drill-events"
}

# Lets the topic send messages to the queue. On real AWS, delivery fails without it.
resource "aws_sqs_queue_policy" "orders" {
  queue_url = aws_sqs_queue.orders.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.orders.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_sns_topic.events.arn }
      }
    }]
  })
}

resource "aws_sns_topic_subscription" "orders" {
  topic_arn            = aws_sns_topic.events.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.orders.arn
  raw_message_delivery = true
}

resource "aws_s3_bucket" "files" {
  bucket = "drill-files"

  # Lets `tofu destroy` delete the bucket while it holds objects. Use in labs only.
  force_destroy = true
}

resource "aws_ssm_parameter" "greeting" {
  name  = "drill-greeting"
  type  = "String"
  value = "hello"
}

output "queue_url" {
  value = aws_sqs_queue.orders.url
}

output "topic_arn" {
  value = aws_sns_topic.events.arn
}
