# Exercise 03 — Serverless API. Solution.
#
# Request flow: HTTP API (API Gateway v2) -> Lambda (Python) -> DynamoDB table.

locals {
  function_name = "ex03-notes-api"
}

# --- DynamoDB ----------------------------------------------------------------

resource "aws_dynamodb_table" "notes" {
  name         = "ex03-notes"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# --- IAM ---------------------------------------------------------------------

# The trust policy. It lets the Lambda service assume the role.
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# AWS managed policy: lets the function write to CloudWatch Logs.
resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Least privilege: only the two item actions the handler uses, on one table.
data "aws_iam_policy_document" "table_access" {
  statement {
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem"]
    resources = [aws_dynamodb_table.notes.arn]
  }
}

resource "aws_iam_role_policy" "table_access" {
  name   = "ex03-notes-table-access"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.table_access.json
}

# --- Lambda ------------------------------------------------------------------

# Create the log group before the function. OpenTofu then controls the
# retention, and `tofu destroy` deletes the log group.
resource "aws_cloudwatch_log_group" "function" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 7
}

# Zip the handler at plan time. The zip hash changes only when the code changes.
data "archive_file" "function" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/build/${local.function_name}.zip"
}

resource "aws_lambda_function" "notes_api" {
  function_name = local.function_name
  role          = aws_iam_role.lambda.arn
  runtime       = "python3.12"
  handler       = "handler.handler"
  timeout       = 10

  filename = data.archive_file.function.output_path
  # A new hash makes OpenTofu upload the new code.
  source_code_hash = data.archive_file.function.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.notes.name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.function,
    aws_iam_role_policy_attachment.logs,
    aws_iam_role_policy.table_access,
  ]
}

# --- API Gateway (HTTP API) --------------------------------------------------

resource "aws_apigatewayv2_api" "notes" {
  name          = local.function_name
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "notes_api" {
  api_id                 = aws_apigatewayv2_api.notes.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.notes_api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "create_note" {
  api_id    = aws_apigatewayv2_api.notes.id
  route_key = "POST /notes"
  target    = "integrations/${aws_apigatewayv2_integration.notes_api.id}"
}

resource "aws_apigatewayv2_route" "get_note" {
  api_id    = aws_apigatewayv2_api.notes.id
  route_key = "GET /notes/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.notes_api.id}"
}

# The $default stage serves the API at the root URL, with no stage name in the path.
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.notes.id
  name        = "$default"
  auto_deploy = true
}

# Lets API Gateway invoke the function. Real AWS returns 500 without it.
resource "aws_lambda_permission" "apigateway" {
  statement_id  = "AllowInvokeFromApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notes_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.notes.execution_arn}/*"
}

# --- Outputs -----------------------------------------------------------------

output "api_id" {
  value = aws_apigatewayv2_api.notes.id
}

# The endpoint that API Gateway reports. On Floci, it has the AWS host name.
output "api_endpoint" {
  value = aws_apigatewayv2_api.notes.api_endpoint
}

# The URL to call on Floci. On real AWS, use api_endpoint instead.
output "invoke_url" {
  value = "http://${aws_apigatewayv2_api.notes.id}.execute-api.localhost.floci.io:4566"
}

output "table_name" {
  value = aws_dynamodb_table.notes.name
}
