#!/usr/bin/env bash
# Exercise 06 — Containers. Checks the emulator, Docker, and the live container, not your files.
# Run: ./check.sh
source "$(dirname "$0")/../_lib/check.sh"
require_lab_env

REPO=ex06-web
CLUSTER=ex06-cluster
SERVICE=ex06-web
FAMILY=ex06-web
ROLE=ex06-web-execution-role
LOG_GROUP=/ecs/ex06-web
URL=http://localhost:8060/

# Values that one check finds and later checks use.
REPO_URI=""
TASK_IDS=""

# --- Part B helpers -----------------------------------------------------------

repository_exists() {
  REPO_URI=$(awsl ecr describe-repositories --repository-names "$REPO" \
    --query 'repositories[0].repositoryUri' --output text) || return 1
  [ -n "$REPO_URI" ] && [ "$REPO_URI" != "None" ]
}

image_v1_pushed() {
  awsl ecr describe-images --repository-name "$REPO" --image-ids imageTag=v1
}

cluster_active() {
  [ "$(awsl ecs describe-clusters --clusters "$CLUSTER" \
    --query 'clusters[0].status' --output text)" = "ACTIVE" ]
}

role_trusts_ecs_tasks() {
  awsl iam get-role --role-name "$ROLE" --query Role.AssumeRolePolicyDocument \
    --output json | grep -q '"ecs-tasks.amazonaws.com"'
}

role_has_execution_policy() {
  [ "$(awsl iam list-attached-role-policies --role-name "$ROLE" \
    --query "length(AttachedPolicies[?PolicyName=='AmazonECSTaskExecutionRolePolicy'])" \
    --output text)" = "1" ]
}

log_group_ok() {
  [ "$(awsl logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" \
    --query "logGroups[?logGroupName=='$LOG_GROUP'].retentionInDays | [0]" \
    --output text)" = "7" ]
}

# Prints the latest revision of the task definition as JSON. Fails when it is not ACTIVE.
# Floci returns the latest revision also after `tofu destroy` deregisters it.
task_definition() {
  awsl ecs describe-task-definition --task-definition "$FAMILY" \
    --query taskDefinition --output json | jq -e 'select(.status == "ACTIVE")'
}

task_definition_image_ok() {
  [ -n "$REPO_URI" ] || return 1
  task_definition | jq -e --arg image "$REPO_URI:v1" '.containerDefinitions[0].image == $image'
}

task_definition_port_ok() {
  task_definition | jq -e '.networkMode == "bridge" and
    any(.containerDefinitions[0].portMappings[]; .containerPort == 80 and .hostPort == 8060)'
}

task_definition_role_ok() {
  task_definition | jq -e --arg role "$ROLE" '(.executionRoleArn // "") | endswith("role/" + $role)'
}

task_definition_logs_ok() {
  task_definition | jq -e --arg group "$LOG_GROUP" \
    '.containerDefinitions[0].logConfiguration | .logDriver == "awslogs" and .options["awslogs-group"] == $group'
}

service_ok() {
  awsl ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
    --query 'services[0]' --output json |
    jq -e --arg family "$FAMILY" '.status == "ACTIVE" and .desiredCount == 1 and .runningCount >= 1
      and (.taskDefinition | contains("task-definition/" + $family + ":"))'
}

# --- Live helpers -------------------------------------------------------------

running_task_has_container() {
  local task_id
  TASK_IDS=$(awsl ecs list-tasks --cluster "$CLUSTER" --service-name "$SERVICE" \
    --desired-status RUNNING --output json | jq -r '.taskArns[] | split("/") | last') || return 1
  for task_id in $TASK_IDS; do
    # Floci labels each task container with the task ID.
    if [ -n "$(docker ps -q --filter "label=io.floci.resource-id=$task_id" --filter status=running)" ]; then
      return 0
    fi
  done
  return 1
}

http_ok() {
  local response status body
  response=$(curl -sS -m 10 -w '\n%{http_code}' "$URL") || return 1
  status=${response##*$'\n'}
  body=${response%$'\n'*}
  [ "$status" = "200" ] && grep -q 'Hello from ex06-web' <<<"$body"
}

container_logs_arrive() {
  local task_id stream count
  [ -n "$TASK_IDS" ] || return 1
  for task_id in $TASK_IDS; do
    # Floci names the stream <date>/web/<task-id>. AWS names it ecs/web/<task-id>.
    stream=$(awsl logs describe-log-streams --log-group-name "$LOG_GROUP" \
      --query "logStreams[?ends_with(logStreamName, 'web/$task_id')].logStreamName | [0]" \
      --output text) || continue
    [ -n "$stream" ] && [ "$stream" != "None" ] || continue
    count=$(awsl logs get-log-events --log-group-name "$LOG_GROUP" --log-stream-name "$stream" \
      --query 'length(events)' --output text) || continue
    [ "$count" -ge 1 ] && return 0
  done
  return 1
}

# --- Part C helpers -----------------------------------------------------------

# Converts a CLI timestamp such as 2026-09-15T14:13:20.303000+02:00 to epoch seconds.
JQ_EPOCH='def epoch:
  if endswith("Z") then .[0:19] + "Z" | fromdateiso8601
  else (.[0:19] + "Z" | fromdateiso8601)
    - ((.[-6:-5] + "1" | tonumber) * ((.[-5:-3] | tonumber) * 3600 + (.[-2:] | tonumber) * 60))
  end;'

port_conflict_seen() {
  local arns service_created
  service_created=$(awsl ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
    --query 'services[0].createdAt' --output text) || return 1
  arns=$(awsl ecs list-tasks --cluster "$CLUSTER" --service-name "$SERVICE" \
    --desired-status STOPPED --output json | jq -r '.taskArns[]') || return 1
  [ -n "$arns" ] || return 1
  # Floci keeps stopped tasks after the service is deleted. Count only the tasks
  # of the current service. describe-tasks accepts 100 tasks in one call.
  xargs -n 100 <<<"$arns" | while read -r batch; do
    # shellcheck disable=SC2086
    awsl ecs describe-tasks --cluster "$CLUSTER" --tasks $batch --output json |
      jq -r --arg created "$service_created" "$JQ_EPOCH"'
        .tasks[] | select((.createdAt | epoch) >= ($created | epoch)) | .stoppedReason // empty'
  done | grep -q 'port is already allocated'
}

# --- Checks -------------------------------------------------------------------

section "Part B — ECR"
check "Repository $REPO exists" repository_exists
check "Repository $REPO has the image tag v1" image_v1_pushed

section "Part B — ECS"
check "Cluster $CLUSTER is ACTIVE" cluster_active
check "Role $ROLE trusts ecs-tasks.amazonaws.com" role_trusts_ecs_tasks
check "Role $ROLE has the policy AmazonECSTaskExecutionRolePolicy" role_has_execution_policy
check "Log group $LOG_GROUP keeps logs for 7 days" log_group_ok
check "Task definition $FAMILY uses the image <repository URI>:v1" task_definition_image_ok
check "Task definition $FAMILY uses bridge mode and maps port 80 to host port 8060" task_definition_port_ok
check "Task definition $FAMILY has the execution role $ROLE" task_definition_role_ok
check "Task definition $FAMILY sends logs to $LOG_GROUP with awslogs" task_definition_logs_ok
check "Service $SERVICE is ACTIVE with desiredCount 1 and at least 1 running task" service_ok

section "Live service"
check "A running task of $SERVICE has a running Docker container" running_task_has_container
check "GET $URL returns 200 and 'Hello from ex06-web'" http_ok
check "The container logs are in $LOG_GROUP" container_logs_arrive

section "Part C — Code"
check "A task of $SERVICE stopped with 'port is already allocated'" port_conflict_seen

summary
