#!/usr/bin/env bash
# Exercise 03 — Serverless API. Checks the emulator and calls the live API, not your files.
# Run: ./check.sh
source "$(dirname "$0")/../_lib/check.sh"
require_lab_env

TABLE=ex03-notes
FUNCTION=ex03-notes-api
API_NAME=ex03-notes-api
LOG_GROUP=/aws/lambda/ex03-notes-api

# Values that one check finds and later checks use.
TABLE_ARN=""
ROLE_ARN=""
API_ID=""
NOTE_ID=""
CHECK_TEXT="note from check.sh $$"
STATUS=""
BODY=""

# --- Part B helpers -----------------------------------------------------------

table_ok() {
  local hash_key
  hash_key=$(awsl dynamodb describe-table --table-name "$TABLE" \
    --query "Table.KeySchema[?KeyType=='HASH'].AttributeName | [0]" --output text) || return 1
  [ "$hash_key" = "id" ] || return 1
  TABLE_ARN=$(awsl dynamodb describe-table --table-name "$TABLE" --query Table.TableArn --output text)
}

function_runtime_ok() {
  [ "$(awsl lambda get-function-configuration --function-name "$FUNCTION" \
    --query Runtime --output text)" = "python3.12" ]
}

function_env_ok() {
  [ "$(awsl lambda get-function-configuration --function-name "$FUNCTION" \
    --query Environment.Variables.TABLE_NAME --output text)" = "$TABLE" ]
}

role_exists() {
  ROLE_ARN=$(awsl lambda get-function-configuration --function-name "$FUNCTION" \
    --query Role --output text) || return 1
  awsl iam get-role --role-name "${ROLE_ARN##*/}"
}

# Floci does not enforce IAM, but it can evaluate a policy.
# Prints the decision for one action on one resource.
simulate() {
  awsl iam simulate-principal-policy --policy-source-arn "$ROLE_ARN" \
    --action-names "$1" --resource-arns "$2" \
    --query 'EvaluationResults[0].EvalDecision' --output text
}

role_can_use_table() {
  [ -n "$ROLE_ARN" ] && [ -n "$TABLE_ARN" ] || return 1
  [ "$(simulate dynamodb:PutItem "$TABLE_ARN")" = "allowed" ] &&
    [ "$(simulate dynamodb:GetItem "$TABLE_ARN")" = "allowed" ]
}

role_cannot_delete() {
  [ -n "$ROLE_ARN" ] && [ -n "$TABLE_ARN" ] || return 1
  local decision
  decision=$(simulate dynamodb:DeleteItem "$TABLE_ARN") || return 1
  [ "$decision" = "implicitDeny" ] || [ "$decision" = "explicitDeny" ]
}

role_can_write_logs() {
  [ -n "$ROLE_ARN" ] || return 1
  local log_stream_arn="arn:aws:logs:us-east-1:000000000000:log-group:$LOG_GROUP:*"
  [ "$(simulate logs:PutLogEvents "$log_stream_arn")" = "allowed" ]
}

log_group_ok() {
  [ "$(awsl logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" \
    --query "logGroups[?logGroupName=='$LOG_GROUP'].retentionInDays | [0]" \
    --output text)" = "7" ]
}

api_ok() {
  API_ID=$(awsl apigatewayv2 get-apis \
    --query "Items[?Name=='$API_NAME' && ProtocolType=='HTTP'].ApiId | [0]" --output text)
  # The CLI prints "None" when no API matches. Clear it, so the live checks fail.
  [ "$API_ID" = "None" ] && API_ID=""
  [ -n "$API_ID" ]
}

route_exists() {
  [ -n "$API_ID" ] || return 1
  [ "$(awsl apigatewayv2 get-routes --api-id "$API_ID" \
    --query "length(Items[?RouteKey=='$1' && Target != null])" --output text)" = "1" ]
}

default_stage_ok() {
  [ -n "$API_ID" ] || return 1
  [ "$(awsl apigatewayv2 get-stages --api-id "$API_ID" \
    --query "Items[?StageName=='\$default'].AutoDeploy | [0]" --output text)" = "True" ]
}

# --- Live API helpers ---------------------------------------------------------

# http METHOD PATH [JSON]. Sets STATUS and BODY.
http() {
  local response
  STATUS=""
  BODY=""
  [ -n "$API_ID" ] || return 1
  local url="http://$API_ID.execute-api.localhost.floci.io:4566$2"
  if [ $# -ge 3 ]; then
    response=$(curl -sS -m 60 -w '\n%{http_code}' -X "$1" "$url" \
      -H 'Content-Type: application/json' -d "$3") || return 1
  else
    response=$(curl -sS -m 60 -w '\n%{http_code}' -X "$1" "$url") || return 1
  fi
  STATUS=${response##*$'\n'}
  BODY=${response%$'\n'*}
}

post_returns_201() {
  http POST /notes "{\"text\": \"$CHECK_TEXT\"}" || return 1
  [ "$STATUS" = "201" ] || return 1
  NOTE_ID=$(jq -r '.id // empty' <<<"$BODY")
  [ -n "$NOTE_ID" ]
}

get_returns_same_note() {
  [ -n "$NOTE_ID" ] || return 1
  http GET "/notes/$NOTE_ID" || return 1
  [ "$STATUS" = "200" ] &&
    [ "$(jq -r '.id' <<<"$BODY")" = "$NOTE_ID" ] &&
    [ "$(jq -r '.text' <<<"$BODY")" = "$CHECK_TEXT" ]
}

get_unknown_returns_404() {
  http GET /notes/ex03-no-such-note || return 1
  # Without an API, Floci answers with an S3 error in XML. The handler answers in JSON.
  [ "$STATUS" = "404" ] && jq -e . <<<"$BODY"
}

note_is_in_table() {
  [ -n "$NOTE_ID" ] || return 1
  [ "$(awsl dynamodb get-item --table-name "$TABLE" \
    --key "{\"id\": {\"S\": \"$NOTE_ID\"}}" --query Item.text.S --output text)" = "$CHECK_TEXT" ]
}

# --- Part C helpers -----------------------------------------------------------

app_notes_exist() {
  local count
  count=$(awsl dynamodb scan --table-name "$TABLE" \
    --filter-expression '#text IN (:a, :b)' \
    --expression-attribute-names '{"#text": "text"}' \
    --expression-attribute-values '{":a": {"S": "Buy milk"}, ":b": {"S": "Learn Lambda"}}' \
    --query Count --output text)
  [ "$count" -ge 2 ]
}

# --- Checks -------------------------------------------------------------------

section "Part B — OpenTofu"
check "Table $TABLE exists with the hash key id" table_ok
check "Function $FUNCTION exists with runtime python3.12" function_runtime_ok
check "Function has TABLE_NAME=$TABLE" function_env_ok
check "The function role exists in IAM" role_exists
check "The role allows dynamodb:PutItem and dynamodb:GetItem on the table" role_can_use_table
check "The role does not allow dynamodb:DeleteItem on the table (least privilege)" role_cannot_delete
check "The role allows logs:PutLogEvents on the log group" role_can_write_logs
check "Log group $LOG_GROUP keeps logs for 7 days" log_group_ok
check "HTTP API $API_NAME exists" api_ok
check "Route POST /notes has a target" route_exists "POST /notes"
check "Route GET /notes/{id} has a target" route_exists "GET /notes/{id}"
check "Stage \$default exists with auto-deploy" default_stage_ok

section "Live API (the first call can take some seconds)"
check "POST /notes returns 201 and a note ID" post_returns_201
check "GET /notes/{id} returns 200 and the same note" get_returns_same_note
check "The note is in the table" note_is_in_table
check "GET /notes/{id} for an unknown ID returns 404" get_unknown_returns_404

# Remove the note that this checker created. Part C then counts only your notes.
if [ -n "$NOTE_ID" ]; then
  awsl dynamodb delete-item --table-name "$TABLE" \
    --key "{\"id\": {\"S\": \"$NOTE_ID\"}}" >/dev/null 2>&1
fi

section "Part C — Code"
check "The table holds the notes 'Buy milk' and 'Learn Lambda'" app_notes_exist

summary
