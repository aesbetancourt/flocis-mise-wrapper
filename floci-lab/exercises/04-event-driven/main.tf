# Exercise 04 — Event-driven. Part B.
#
# Complete each TODO, then run `tofu plan` and `tofu apply`.
# Resource documentation: https://search.opentofu.org/provider/hashicorp/aws/latest
#
# Event flow:
# S3 upload -> EventBridge rule -> SQS queue -> EventBridge Pipe -> Step Functions
# Step Functions -> Lambda "ex04-inspect" -> Choice (small or large) -> DynamoDB putItem

# TODO 1: Create a bucket named "ex04-uploads". Do not set force_destroy. Read the Clean up section of the README.
#         Send the events of the bucket to EventBridge (eventbridge = true).
#         Resources: aws_s3_bucket, aws_s3_bucket_notification

# TODO 2: Create a table named "ex04-uploads".
#         Use on-demand billing (PAY_PER_REQUEST) and the hash key "object_key" of type string ("S").
#         Resource: aws_dynamodb_table

# TODO 3: Create an IAM role named "ex04-inspect-role" for the function.
#         The trust policy allows "sts:AssumeRole" for the service "lambda.amazonaws.com".
#         Attach arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole.
#         Add an inline policy that allows "s3:GetObject" on "<bucket ARN>/*".
#         Resources: aws_iam_role, aws_iam_role_policy_attachment, aws_iam_role_policy
#         Data source: aws_iam_policy_document

# TODO 4: Create the function "ex04-inspect" from lambda/handler.py.
#         Create the log group "/aws/lambda/ex04-inspect" first. Keep the logs for 7 days.
#         Zip the file to "${path.module}/build/ex04-inspect.zip".
#         Use runtime "python3.12", handler "handler.handler", and a timeout of 30 seconds.
#         Resources: aws_cloudwatch_log_group, aws_lambda_function. Data source: archive_file

# TODO 5: Create an IAM role named "ex04-process-upload-role" for the state machine.
#         The trust policy allows "sts:AssumeRole" for the service "states.amazonaws.com".
#         Add an inline policy with two statements:
#         a. "lambda:InvokeFunction" on the function ARN and on "<function ARN>:*".
#         b. "dynamodb:PutItem" on the table ARN.
#         Resources: aws_iam_role, aws_iam_role_policy. Data source: aws_iam_policy_document

# TODO 6: Create the state machine "ex04-process-upload" with the role from TODO 5.
#         Read the definition from statemachine.asl.json with templatefile().
#         Give the template two variables: function_arn and table_name.
#         Resource: aws_sfn_state_machine

# TODO 7: Create the queue "ex04-upload-events".
#         Create the rule "ex04-object-created" on the default bus. The rule matches events with:
#         source "aws.s3", detail-type "Object Created", the bucket name, and the key prefix "incoming/".
#         Add the queue as the target of the rule.
#         Resources: aws_sqs_queue, aws_cloudwatch_event_rule, aws_cloudwatch_event_target

# TODO 8: Let the rule send messages to the queue.
#         Allow the principal "events.amazonaws.com" to do "sqs:SendMessage".
#         Add the condition: aws:SourceArn must be the rule ARN.
#         Resource: aws_sqs_queue_policy. Data source: aws_iam_policy_document

# TODO 9: Create an IAM role named "ex04-upload-pipe-role" for the pipe.
#         The trust policy allows "sts:AssumeRole" for the service "pipes.amazonaws.com".
#         Add an inline policy with two statements:
#         a. "sqs:ReceiveMessage", "sqs:DeleteMessage", and "sqs:GetQueueAttributes" on the queue ARN.
#         b. "states:StartExecution" on the state machine ARN.
#         Resources: aws_iam_role, aws_iam_role_policy. Data source: aws_iam_policy_document

# TODO 10: Create the pipe "ex04-upload-pipe" from the queue to the state machine.
#          Read 1 message at a time (batch_size = 1).
#          Start the workflow with invocation_type = "FIRE_AND_FORGET".
#          Resource: aws_pipes_pipe

# TODO 11: Add these outputs:
#          "bucket_name"       = the bucket name
#          "table_name"        = the table name
#          "queue_url"         = the queue URL
#          "state_machine_arn" = the state machine ARN
