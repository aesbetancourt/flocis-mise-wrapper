# Exercise 05 — Modules and tests. Solution.

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

module "queues" {
  source   = "./modules/queue_with_dlq"
  for_each = local.queues

  name                       = each.key
  max_receive_count          = each.value.max_receive_count
  visibility_timeout_seconds = each.value.visibility_timeout_seconds

  tags = {
    exercise = "05-modules-and-tests"
  }
}

output "queue_urls" {
  description = "URL of each main queue, by name."
  value       = { for name, queue in module.queues : name => queue.queue_url }
}
