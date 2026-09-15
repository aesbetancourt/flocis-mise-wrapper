#!/usr/bin/env bash
# Exercise 05 — Modules and tests. Checks the emulator, not your files.
# Run: ./check.sh
source "$(dirname "$0")/../_lib/check.sh"
require_lab_env

ACCOUNT_URL=http://localhost:4566/000000000000
ACCOUNT_ARN=arn:aws:sqs:us-east-1:000000000000

queue_exists() { awsl sqs get-queue-url --queue-name "$1"; }

# Print one field of the redrive policy. The policy is a JSON string.
redrive_field() {
  local policy pattern
  policy=$(awsl sqs get-queue-attributes --queue-url "$ACCOUNT_URL/$1" \
    --attribute-names RedrivePolicy --query Attributes.RedrivePolicy --output text)
  pattern="\"$2\"[[:space:]]*:[[:space:]]*\"?([^\",}]+)"
  [[ $policy =~ $pattern ]] && printf '%s' "${BASH_REMATCH[1]}"
}

max_receive_count_is() {
  [ "$(redrive_field "$1" maxReceiveCount)" = "$2" ]
}

dlq_target_ok() {
  [ "$(redrive_field "$1" deadLetterTargetArn)" = "$ACCOUNT_ARN:$1-dlq" ]
}

check_queue() {
  local name=$1 count=$2
  section "Queue $name"
  check "Main queue $name exists" queue_exists "$name"
  check "Dead-letter queue $name-dlq exists" queue_exists "$name-dlq"
  check "$name sends failed messages to $name-dlq" dlq_target_ok "$name"
  check "$name has maxReceiveCount $count" max_receive_count_is "$name" "$count"
}

check_queue ex05-orders 5
check_queue ex05-emails 3
check_queue ex05-reports 1

summary
