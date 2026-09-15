# Exercise 04 — Event-driven. Solution.
#
# Event flow:
# S3 upload -> EventBridge rule -> SQS queue -> EventBridge Pipe -> Step Functions
# Step Functions -> Lambda (inspect) -> Choice (small or large) -> DynamoDB putItem

locals {
  bucket_name   = "ex04-uploads"
  function_name = "ex04-inspect"
}

# --- S3 ----------------------------------------------------------------------

# No force_destroy here. On Floci, `tofu destroy` then did not end for a bucket
# without versioning that held objects. Empty the bucket before you destroy.
# Read the Clean up section of the README.
resource "aws_s3_bucket" "uploads" {
  bucket = local.bucket_name
}

# Send every event of the bucket to the default EventBridge bus.
# A rule on the bus then selects the events.
resource "aws_s3_bucket_notification" "uploads" {
  bucket      = aws_s3_bucket.uploads.id
  eventbridge = true
}

# --- DynamoDB ----------------------------------------------------------------

resource "aws_dynamodb_table" "uploads" {
  name         = "ex04-uploads"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "object_key"

  attribute {
    name = "object_key"
    type = "S"
  }
}

# --- Lambda ------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "inspect" {
  name               = "${local.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "inspect_logs" {
  role       = aws_iam_role.inspect.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# The function reads objects. HeadObject also uses the s3:GetObject permission.
data "aws_iam_policy_document" "inspect_read" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.uploads.arn}/*"]
  }
}

resource "aws_iam_role_policy" "inspect_read" {
  name   = "ex04-inspect-read-uploads"
  role   = aws_iam_role.inspect.id
  policy = data.aws_iam_policy_document.inspect_read.json
}

resource "aws_cloudwatch_log_group" "inspect" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 7
}

data "archive_file" "inspect" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/build/${local.function_name}.zip"
}

resource "aws_lambda_function" "inspect" {
  function_name = local.function_name
  role          = aws_iam_role.inspect.arn
  runtime       = "python3.12"
  handler       = "handler.handler"
  timeout       = 30

  filename         = data.archive_file.inspect.output_path
  source_code_hash = data.archive_file.inspect.output_base64sha256

  depends_on = [
    aws_cloudwatch_log_group.inspect,
    aws_iam_role_policy_attachment.inspect_logs,
    aws_iam_role_policy.inspect_read,
  ]
}

# --- Step Functions ----------------------------------------------------------

data "aws_iam_policy_document" "states_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "process_upload" {
  name               = "ex04-process-upload-role"
  assume_role_policy = data.aws_iam_policy_document.states_assume.json
}

# The workflow calls one function and writes to one table.
data "aws_iam_policy_document" "process_upload" {
  statement {
    actions = ["lambda:InvokeFunction"]
    resources = [
      aws_lambda_function.inspect.arn,
      "${aws_lambda_function.inspect.arn}:*",
    ]
  }

  statement {
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.uploads.arn]
  }
}

resource "aws_iam_role_policy" "process_upload" {
  name   = "ex04-process-upload-access"
  role   = aws_iam_role.process_upload.id
  policy = data.aws_iam_policy_document.process_upload.json
}

resource "aws_sfn_state_machine" "process_upload" {
  name     = "ex04-process-upload"
  role_arn = aws_iam_role.process_upload.arn

  # templatefile() puts the function ARN and the table name into the definition.
  definition = templatefile("${path.module}/statemachine.asl.json", {
    function_arn = aws_lambda_function.inspect.arn
    table_name   = aws_dynamodb_table.uploads.name
  })
}

# --- EventBridge rule -> SQS queue ---------------------------------------------

resource "aws_sqs_queue" "upload_events" {
  name = "ex04-upload-events"
}

resource "aws_cloudwatch_event_rule" "object_created" {
  name        = "ex04-object-created"
  description = "New objects under incoming/ in ex04-uploads"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = { name = [aws_s3_bucket.uploads.id] }
      object = { key = [{ prefix = "incoming/" }] }
    }
  })
}

resource "aws_cloudwatch_event_target" "upload_events" {
  rule      = aws_cloudwatch_event_rule.object_created.name
  target_id = "upload-events-queue"
  arn       = aws_sqs_queue.upload_events.arn
}

# EventBridge uses the queue policy, not a role, to send to SQS.
data "aws_iam_policy_document" "upload_events_queue" {
  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.upload_events.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.object_created.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "upload_events" {
  queue_url = aws_sqs_queue.upload_events.id
  policy    = data.aws_iam_policy_document.upload_events_queue.json
}

# --- EventBridge Pipe: SQS queue -> state machine ---------------------------

data "aws_iam_policy_document" "pipes_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["pipes.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "upload_pipe" {
  name               = "ex04-upload-pipe-role"
  assume_role_policy = data.aws_iam_policy_document.pipes_assume.json
}

data "aws_iam_policy_document" "upload_pipe" {
  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [aws_sqs_queue.upload_events.arn]
  }

  statement {
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.process_upload.arn]
  }
}

resource "aws_iam_role_policy" "upload_pipe" {
  name   = "ex04-upload-pipe-access"
  role   = aws_iam_role.upload_pipe.id
  policy = data.aws_iam_policy_document.upload_pipe.json
}

resource "aws_pipes_pipe" "upload" {
  name     = "ex04-upload-pipe"
  role_arn = aws_iam_role.upload_pipe.arn
  source   = aws_sqs_queue.upload_events.arn
  target   = aws_sfn_state_machine.process_upload.arn

  source_parameters {
    sqs_queue_parameters {
      batch_size = 1
    }
  }

  target_parameters {
    step_function_state_machine_parameters {
      # A Standard workflow runs asynchronously. The pipe does not wait for the result.
      invocation_type = "FIRE_AND_FORGET"
    }
  }

  depends_on = [aws_iam_role_policy.upload_pipe]
}

# --- Outputs -----------------------------------------------------------------

output "bucket_name" {
  value = aws_s3_bucket.uploads.id
}

output "table_name" {
  value = aws_dynamodb_table.uploads.name
}

output "queue_url" {
  value = aws_sqs_queue.upload_events.id
}

output "state_machine_arn" {
  value = aws_sfn_state_machine.process_upload.arn
}
