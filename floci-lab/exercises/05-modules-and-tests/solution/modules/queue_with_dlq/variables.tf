# Module queue_with_dlq — inputs. Solution.

variable "name" {
  description = "Name of the main queue. The dead-letter queue gets the name <name>-dlq."
  type        = string
}

variable "max_receive_count" {
  description = "Number of receives before SQS moves a message to the dead-letter queue."
  type        = number
  default     = 3

  validation {
    condition     = var.max_receive_count >= 1 && var.max_receive_count <= 10
    error_message = "The max_receive_count must be a number from 1 to 10."
  }
}

variable "visibility_timeout_seconds" {
  description = "Time in seconds that a received message stays hidden from other consumers."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags for both queues."
  type        = map(string)
  default     = {}
}
