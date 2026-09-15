#!/usr/bin/env bash
# Exercise 04 — Event-driven. Checks the emulator and runs the event chain, not your files.
# Run: ./check.sh
source "$(dirname "$0")/../_lib/check.sh"
require_lab_env

ACCOUNT=000000000000
REGION=us-east-1
BUCKET=ex04-uploads
TABLE=ex04-uploads
FUNCTION=ex04-inspect
STATE_MACHINE=ex04-process-upload
RULE=ex04-object-created
QUEUE=ex04-upload-events
PIPE=ex04-upload-pipe

SM_ARN=arn:aws:states:$REGION:$ACCOUNT:stateMachine:$STATE_MACHINE
QUEUE_ARN=arn:aws:sqs:$REGION:$ACCOUNT:$QUEUE
RULE_ARN=arn:aws:events:$REGION:$ACCOUNT:rule/$RULE

# Values that one check finds and later checks use.
DEFINITION=""
CHECK_KEY="incoming/check-$$.txt"
CHECK_BODY="written by check.sh"

# --- Part B helpers -----------------------------------------------------------

bucket_exists() { awsl s3api head-bucket --bucket "$BUCKET"; }

bucket_sends_to_eventbridge() {
  local config
  config=$(awsl s3api get-bucket-notification-configuration --bucket "$BUCKET" --output json) || return 1
  jq -e 'has("EventBridgeConfiguration")' <<<"$config"
}

table_ok() {
  [ "$(awsl dynamodb describe-table --table-name "$TABLE" \
    --query "Table.KeySchema[?KeyType=='HASH'].AttributeName | [0]" --output text)" = "object_key" ]
}

function_ok() {
  [ "$(awsl lambda get-function-configuration --function-name "$FUNCTION" \
    --query Runtime --output text)" = "python3.12" ]
}

# role_exists <role ARN>. Floci accepts a role ARN that does not exist in IAM.
role_exists() {
  [ -n "$1" ] && [ "$1" != "None" ] && awsl iam get-role --role-name "${1##*/}"
}

function_role_exists() {
  role_exists "$(awsl lambda get-function-configuration --function-name "$FUNCTION" \
    --query Role --output text)"
}

state_machine_exists() {
  DEFINITION=$(awsl stepfunctions describe-state-machine --state-machine-arn "$SM_ARN" \
    --query definition --output text) || return 1
  [ -n "$DEFINITION" ]
}

state_machine_role_exists() {
  role_exists "$(awsl stepfunctions describe-state-machine --state-machine-arn "$SM_ARN" \
    --query roleArn --output text)"
}

# The Task states that call the function, with the lambda:invoke integration or the function ARN.
LAMBDA_TASKS='[.States[] | select(.Type == "Task") | select(
  (.Resource == "arn:aws:states:::lambda:invoke" and ((.Parameters.FunctionName // "") | test("ex04-inspect")))
  or ((.Resource // "") | test(":function:ex04-inspect")))]'

definition_calls_function() {
  jq -e "$LAMBDA_TASKS | length >= 1" <<<"$DEFINITION"
}

lambda_task_has_retry_and_catch() {
  jq -e "$LAMBDA_TASKS | any((.Retry | length) >= 1 and (.Catch | length) >= 1)" <<<"$DEFINITION"
}

definition_has_choice() {
  jq -e '[.States[] | select(.Type == "Choice")] | length >= 1' <<<"$DEFINITION"
}

definition_uses_put_item() {
  jq -e '[.States[] | select(.Type == "Task" and .Resource == "arn:aws:states:::dynamodb:putItem")] | length >= 1' \
    <<<"$DEFINITION"
}

rule_pattern_ok() {
  local pattern
  pattern=$(awsl events describe-rule --name "$RULE" --query EventPattern --output text) || return 1
  jq -e --arg bucket "$BUCKET" '
    (.source | index("aws.s3")) != null and
    (.["detail-type"] | index("Object Created")) != null and
    (.detail.bucket.name | index($bucket)) != null and
    (.detail.object.key | any(.prefix? == "incoming/"))' <<<"$pattern"
}

rule_enabled() {
  [ "$(awsl events describe-rule --name "$RULE" --query State --output text)" = "ENABLED" ]
}

rule_targets_queue() {
  [ "$(awsl events list-targets-by-rule --rule "$RULE" \
    --query "length(Targets[?Arn=='$QUEUE_ARN'])" --output text)" = "1" ]
}

queue_policy_ok() {
  local url policy
  url=$(awsl sqs get-queue-url --queue-name "$QUEUE" --query QueueUrl --output text) || return 1
  policy=$(awsl sqs get-queue-attributes --queue-url "$url" --attribute-names Policy \
    --query Attributes.Policy --output text) || return 1
  grep -q "events.amazonaws.com" <<<"$policy" && grep -q "$RULE_ARN" <<<"$policy"
}

pipe_ok() {
  [ "$(awsl pipes describe-pipe --name "$PIPE" \
    --query "[Source, Target, CurrentState]" --output text)" = "$QUEUE_ARN	$SM_ARN	RUNNING" ]
}

pipe_role_exists() {
  role_exists "$(awsl pipes describe-pipe --name "$PIPE" --query RoleArn --output text)"
}

# --- Live chain helpers -------------------------------------------------------

# Uploads a test object and waits up to 60 seconds for its item in the table.
upload_reaches_table() {
  awsl s3api head-bucket --bucket "$BUCKET" || return 1
  printf '%s\n' "$CHECK_BODY" | awsl s3 cp - "s3://$BUCKET/$CHECK_KEY" --content-type text/plain || return 1
  local attempt category
  for attempt in $(seq 30); do
    category=$(awsl dynamodb get-item --table-name "$TABLE" \
      --key "{\"object_key\": {\"S\": \"$CHECK_KEY\"}}" --query Item.category.S --output text)
    [ "$category" = "small" ] && return 0
    sleep 2
  done
  return 1
}

test_item_first_line_ok() {
  [ "$(awsl dynamodb get-item --table-name "$TABLE" \
    --key "{\"object_key\": {\"S\": \"$CHECK_KEY\"}}" --query Item.first_line.S --output text)" = "$CHECK_BODY" ]
}

# --- Part C helpers -----------------------------------------------------------

succeeded_executions() {
  # Floci keeps the executions of a deleted state machine. Make sure that it exists.
  awsl stepfunctions describe-state-machine --state-machine-arn "$SM_ARN" || return 1
  # Floci ignores --status-filter. Filter the list with a query instead.
  [ "$(awsl stepfunctions list-executions --state-machine-arn "$SM_ARN" \
    --query "length(executions[?status=='SUCCEEDED'])" --output text)" -ge 2 ]
}

# item_ok <key> <category>. The item has the category and the size of the object in S3.
item_ok() {
  local item size
  item=$(awsl dynamodb get-item --table-name "$TABLE" \
    --key "{\"object_key\": {\"S\": \"$1\"}}" --query '[Item.category.S, Item.size.N]' --output text) || return 1
  size=$(awsl s3api head-object --bucket "$BUCKET" --key "$1" --query ContentLength --output text) || return 1
  [ "$item" = "$2	$size" ]
}

# --- Checks -------------------------------------------------------------------

section "Part B — OpenTofu"
check "Bucket $BUCKET exists" bucket_exists
check "Bucket $BUCKET sends events to EventBridge" bucket_sends_to_eventbridge
check "Table $TABLE exists with the hash key object_key" table_ok
check "Function $FUNCTION exists with runtime python3.12" function_ok
check "The function role exists in IAM" function_role_exists
check "State machine $STATE_MACHINE exists" state_machine_exists
check "The state machine role exists in IAM" state_machine_role_exists
check "A Task state calls $FUNCTION" definition_calls_function
check "The $FUNCTION task has a Retry and a Catch" lambda_task_has_retry_and_catch
check "The state machine has a Choice state" definition_has_choice
check "A Task state uses arn:aws:states:::dynamodb:putItem" definition_uses_put_item
check "Rule $RULE matches Object Created in $BUCKET under incoming/" rule_pattern_ok
check "Rule $RULE is ENABLED" rule_enabled
check "Rule $RULE sends events to queue $QUEUE" rule_targets_queue
check "Queue policy of $QUEUE lets the rule send messages" queue_policy_ok
check "Pipe $PIPE is RUNNING from $QUEUE to $STATE_MACHINE" pipe_ok
check "The pipe role exists in IAM" pipe_role_exists

section "Live chain (the check uploads a file and waits up to 60 seconds)"
check "An upload under incoming/ creates an item with the category small" upload_reaches_table
check "The item has the first line of the file" test_item_first_line_ok

# Remove the object and the item that this checker created. Part C then counts only your files.
awsl s3 rm "s3://$BUCKET/$CHECK_KEY" >/dev/null 2>&1
awsl dynamodb delete-item --table-name "$TABLE" \
  --key "{\"object_key\": {\"S\": \"$CHECK_KEY\"}}" >/dev/null 2>&1

section "Part C — Code"
check "At least 2 executions of $STATE_MACHINE SUCCEEDED" succeeded_executions
check "incoming/notes.txt is stored as small, with its size" item_ok incoming/notes.txt small
check "incoming/report.csv is stored as large, with its size" item_ok incoming/report.csv large

summary
