# Exercise 03 — Serverless API. Part B.
#
# Complete each TODO, then run `tofu plan` and `tofu apply`.
# Resource documentation: https://search.opentofu.org/provider/hashicorp/aws/latest
#
# Request flow: HTTP API (API Gateway v2) -> Lambda (Python) -> DynamoDB table.

# TODO 1: Create a table named "ex03-notes".
#         Use on-demand billing (PAY_PER_REQUEST) and the hash key "id" of type string ("S").
#         Resource: aws_dynamodb_table

# TODO 2: Create an IAM role named "ex03-notes-api-role" for the function.
#         The trust policy allows "sts:AssumeRole" for the service "lambda.amazonaws.com".
#         Data source: aws_iam_policy_document. Resource: aws_iam_role

# TODO 3: Give the role its permissions.
#         a. Attach the AWS managed policy for CloudWatch Logs:
#            arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
#            Resource: aws_iam_role_policy_attachment
#         b. Add an inline policy that allows only "dynamodb:GetItem" and "dynamodb:PutItem".
#            Use the table ARN as the resource, not "*".
#            Data source: aws_iam_policy_document. Resource: aws_iam_role_policy

# TODO 4: Create the log group "/aws/lambda/ex03-notes-api". Keep the logs for 7 days.
#         Resource: aws_cloudwatch_log_group

# TODO 5: Zip the handler file lambda/handler.py to "${path.module}/build/ex03-notes-api.zip".
#         Data source: archive_file (type "zip", source_file, output_path)

# TODO 6: Create the function "ex03-notes-api".
#         Use runtime "python3.12", handler "handler.handler", and a timeout of 10 seconds.
#         Set filename and source_code_hash from the archive_file data source.
#         Set the environment variable TABLE_NAME to the table name.
#         Add depends_on for the log group. Read the Hints section of the README to learn why.
#         Resource: aws_lambda_function

# TODO 7: Create an HTTP API named "ex03-notes-api" and a Lambda proxy integration.
#         Integration: type "AWS_PROXY", payload format version "2.0", URI = the function invoke_arn.
#         Resources: aws_apigatewayv2_api, aws_apigatewayv2_integration

# TODO 8: Create the routes "POST /notes" and "GET /notes/{id}". Both target the integration.
#         Create the stage "$default" with auto_deploy = true.
#         Resources: aws_apigatewayv2_route, aws_apigatewayv2_stage

# TODO 9: Let API Gateway invoke the function.
#         Use the principal "apigateway.amazonaws.com" and the source ARN "<API execution_arn>/*".
#         Resource: aws_lambda_permission

# TODO 10: Add these outputs:
#          "api_id"       = the id of the API
#          "api_endpoint" = the api_endpoint attribute of the API
#          "invoke_url"   = "http://<API id>.execute-api.localhost.floci.io:4566"
