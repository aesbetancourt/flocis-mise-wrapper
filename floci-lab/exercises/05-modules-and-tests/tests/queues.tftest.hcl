# Exercise 05 — Modules and tests. Part C.
#
# Complete each TODO, then run `tofu init -plugin-dir=../../.terraform/providers` and `tofu test`.
# Each run block tests the module directly. Use this block in each run:
#
#   module {
#     source = "./modules/queue_with_dlq"
#   }
#
# Test documentation: https://opentofu.org/docs/cli/commands/test/

# The input values for every run block. A run block can replace them.
# The names start with "ex05-test-", so the test does not touch your ex05- queues.
variables {
  name                       = "ex05-test-jobs"
  max_receive_count          = 4
  visibility_timeout_seconds = 45
  tags = {
    exercise = "05-modules-and-tests"
  }
}

# TODO 11: Add the run block "plan_names_and_redrive" with command = plan.
#          Assert the name of the main queue and the name of the dead-letter queue.
#          Assert maxReceiveCount in the redrive policy. Function: jsondecode()

# TODO 12: Add the run block "apply_creates_queues" with command = apply.
#          Assert the outputs queue_url and dlq_arn. Syntax: output.<name>

# TODO 13: Add the run block "reject_zero_receive_count" with command = plan.
#          Set max_receive_count = 0 in a variables block.
#          Expect the validation to fail. Argument: expect_failures = [var.max_receive_count]
