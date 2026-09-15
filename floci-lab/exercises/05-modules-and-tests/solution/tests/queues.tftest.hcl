# Exercise 05 — Modules and tests. Solution for Part C.
#
# Run: tofu init -plugin-dir=../../../.terraform/providers && tofu test
# The apply run makes real queues on the emulator. OpenTofu deletes them at the end.

# The input values for every run block. The names start with "ex05-test-".
variables {
  name                       = "ex05-test-jobs"
  max_receive_count          = 4
  visibility_timeout_seconds = 45
  tags = {
    exercise = "05-modules-and-tests"
  }
}

run "plan_names_and_redrive" {
  command = plan

  module {
    source = "./modules/queue_with_dlq"
  }

  # In a plan, the ARN of the dead-letter queue is unknown, so the redrive
  # policy is unknown too. Give the ARN a fixed value for this run only.
  override_resource {
    target = aws_sqs_queue.dlq
    values = {
      arn = "arn:aws:sqs:us-east-1:000000000000:ex05-test-jobs-dlq"
    }
  }

  assert {
    condition     = aws_sqs_queue.main.name == "ex05-test-jobs"
    error_message = "The main queue must use the name from var.name."
  }

  assert {
    condition     = aws_sqs_queue.dlq.name == "ex05-test-jobs-dlq"
    error_message = "The dead-letter queue must use the name <name>-dlq."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue.main.redrive_policy).maxReceiveCount == 4
    error_message = "The redrive policy must use var.max_receive_count."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue.main.redrive_policy).deadLetterTargetArn == "arn:aws:sqs:us-east-1:000000000000:ex05-test-jobs-dlq"
    error_message = "The redrive policy must point to the dead-letter queue."
  }
}

# Makes the two queues on the emulator and reads the real values.
run "apply_creates_queues" {
  command = apply

  module {
    source = "./modules/queue_with_dlq"
  }

  assert {
    condition     = output.queue_url == "http://localhost:4566/000000000000/ex05-test-jobs"
    error_message = "The queue_url output must be the URL of the main queue."
  }

  assert {
    condition     = output.dlq_arn == "arn:aws:sqs:us-east-1:000000000000:ex05-test-jobs-dlq"
    error_message = "The dlq_arn output must be the ARN of the dead-letter queue."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue.main.redrive_policy).deadLetterTargetArn == output.dlq_arn
    error_message = "The main queue must send failed messages to the dead-letter queue."
  }
}

# The run passes only when the validation of var.max_receive_count fails.
run "reject_zero_receive_count" {
  command = plan

  module {
    source = "./modules/queue_with_dlq"
  }

  variables {
    max_receive_count = 0
  }

  expect_failures = [
    var.max_receive_count,
  ]
}
