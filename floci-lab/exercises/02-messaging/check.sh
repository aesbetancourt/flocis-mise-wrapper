#!/usr/bin/env bash
# Exercise 02 — Messaging. Checks the emulator, not your files.
# Run: ./check.sh
source "$(dirname "$0")/../_lib/check.sh"
require_lab_env

PREFIX=arn:aws:sqs:us-east-1:000000000000
TOPIC_ARN=arn:aws:sns:us-east-1:000000000000:ex02-orders
BILLING=ex02-billing
SHIPPING=ex02-shipping
DLQ=ex02-billing-dlq

queue_url() { awsl sqs get-queue-url --queue-name "$1" --query QueueUrl --output text; }

queue_attribute() {
  local url
  url=$(queue_url "$1") || return 1
  awsl sqs get-queue-attributes --queue-url "$url" --attribute-names "$2" \
    --query "Attributes.$2" --output text
}

# Prints the ARN of the subscription from the topic to queue $1.
subscription_arn() {
  local arn
  arn=$(awsl sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" \
    --query "Subscriptions[?Protocol=='sqs' && Endpoint=='$PREFIX:$1'].SubscriptionArn | [0]" \
    --output text) || return 1
  [ -n "$arn" ] && [ "$arn" != "None" ] && echo "$arn"
}

raw_delivery_is() {
  local arn
  arn=$(subscription_arn "$1") || return 1
  [ "$(awsl sns get-subscription-attributes --subscription-arn "$arn" \
    --query Attributes.RawMessageDelivery --output text)" = "$2" ]
}

topic_exists() { awsl sns get-topic-attributes --topic-arn "$TOPIC_ARN"; }

visibility_timeout_ok() { [ "$(queue_attribute "$BILLING" VisibilityTimeout)" = "5" ]; }

redrive_policy_ok() {
  local policy
  policy=$(queue_attribute "$BILLING" RedrivePolicy) || return 1
  grep -q "\"$PREFIX:$DLQ\"" <<<"$policy" &&
    grep -Eq '"maxReceiveCount" *: *"?2"?[^0-9]' <<<"$policy"
}

queue_policy_ok() {
  local policy
  policy=$(queue_attribute "$1" Policy) || return 1
  grep -q "sns.amazonaws.com" <<<"$policy" && grep -q "$TOPIC_ARN" <<<"$policy"
}

dlq_has_message() {
  local visible hidden
  visible=$(queue_attribute "$DLQ" ApproximateNumberOfMessages) || return 1
  hidden=$(queue_attribute "$DLQ" ApproximateNumberOfMessagesNotVisible) || return 1
  [ $((visible + hidden)) -ge 1 ]
}

# Reads one DLQ message. Visibility timeout 0 keeps it visible.
dlq_message_is_raw_order() {
  local url body
  url=$(queue_url "$DLQ") || return 1
  body=$(awsl sqs receive-message --queue-url "$url" --visibility-timeout 0 \
    --query 'Messages[0].Body' --output text) || return 1
  grep -q '"order_id"' <<<"$body" && ! grep -q '"TopicArn"' <<<"$body"
}

section "Part B — OpenTofu"
check "Topic ex02-orders exists" topic_exists
check "Queue $BILLING exists" queue_url "$BILLING"
check "Queue $SHIPPING exists" queue_url "$SHIPPING"
check "Queue $DLQ exists" queue_url "$DLQ"
check "$BILLING is subscribed to the topic" subscription_arn "$BILLING"
check "$SHIPPING is subscribed to the topic" subscription_arn "$SHIPPING"
check "$BILLING subscription uses raw message delivery" raw_delivery_is "$BILLING" true
check "$SHIPPING subscription gets the SNS envelope (no raw delivery)" raw_delivery_is "$SHIPPING" false
check "$BILLING visibility timeout is 5 seconds" visibility_timeout_ok
check "$BILLING redrive policy moves messages to $DLQ after 2 receives" redrive_policy_ok
check "$BILLING queue policy lets the topic send messages" queue_policy_ok "$BILLING"
check "$SHIPPING queue policy lets the topic send messages" queue_policy_ok "$SHIPPING"

section "Part C — Code"
check "$DLQ holds at least 1 message" dlq_has_message
check "The DLQ message is the raw order JSON, not an SNS envelope" dlq_message_is_raw_order

summary
