# Exercise 05 — Modules and tests. Part B.
#
# Complete the module in modules/queue_with_dlq first. Then complete each TODO here.
# Module documentation: https://opentofu.org/docs/language/modules/

locals {
  # One entry for each queue. The key is the queue name.
  queues = {
    "ex05-orders" = {
      max_receive_count          = 5
      visibility_timeout_seconds = 60
    }
    "ex05-emails" = {
      max_receive_count          = 3
      visibility_timeout_seconds = 30
    }
    "ex05-reports" = {
      max_receive_count          = 1
      visibility_timeout_seconds = 300
    }
  }
}

# TODO 9: Call the module one time for each entry in local.queues.
#         Name the module block "queues". Use for_each, each.key, and each.value.
#         Give all queues the tag exercise = "05-modules-and-tests".

# TODO 10: Output a map from each queue name to its URL. Name the output "queue_urls".
#          Expression: a for expression over module.queues
