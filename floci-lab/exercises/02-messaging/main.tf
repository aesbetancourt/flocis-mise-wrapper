# Exercise 02 — Messaging. Part B.
#
# Complete each TODO, then run `tofu plan` and `tofu apply`.
# Resource documentation: https://search.opentofu.org/provider/hashicorp/aws/latest

# TODO 1: Create an SNS topic named "ex02-orders".
#         Resource: aws_sns_topic

# TODO 2: Create three SQS queues: "ex02-billing-dlq", "ex02-billing", and "ex02-shipping".
#         Resource: aws_sqs_queue

# TODO 3: Set the visibility timeout of "ex02-billing" to 5 seconds.
#         Add a redrive policy: after 2 receives, SQS moves a message to "ex02-billing-dlq".
#         Arguments: visibility_timeout_seconds, redrive_policy

# TODO 4: Let the topic send messages to "ex02-billing" and to "ex02-shipping".
#         Allow the principal "sns.amazonaws.com" to do "sqs:SendMessage".
#         Add the condition: aws:SourceArn must be the topic ARN.
#         Resource: aws_sqs_queue_policy. Data source: aws_iam_policy_document

# TODO 5: Subscribe both queues to the topic with the protocol "sqs".
#         Turn on raw message delivery for "ex02-billing" only.
#         Resource: aws_sns_topic_subscription

# TODO 6: Output the topic ARN as "topic_arn".
#         Output the queue URLs as "billing_queue_url", "shipping_queue_url", and "billing_dlq_url".
