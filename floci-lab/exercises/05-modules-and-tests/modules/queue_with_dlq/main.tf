# Module queue_with_dlq — resources. Part B.
#
# Complete each TODO. Do not add a provider block here.
# The module uses the aws provider of the root module.
# Resource documentation: https://search.opentofu.org/provider/hashicorp/aws/latest

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# TODO 5: Create the dead-letter queue. Its name is "<name>-dlq".
#         Keep its messages for 14 days (1209600 seconds). Add the tags.
#         Resource: aws_sqs_queue, with the local name "dlq"

# TODO 6: Create the main queue. Use var.name, var.visibility_timeout_seconds, and the tags.
#         Resource: aws_sqs_queue, with the local name "main"

# TODO 7: In the main queue, add a redrive policy.
#         The policy sends a message to the dead-letter queue after var.max_receive_count receives.
#         Argument: redrive_policy, with jsonencode() and the keys deadLetterTargetArn and maxReceiveCount
