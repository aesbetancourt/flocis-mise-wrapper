"""Exercise 04 — Event-driven. Solution for Part C.

Run inside the lab folder:
    uv run --with boto3 python app.py
"""

import json
import time

import boto3

BUCKET = "ex04-uploads"
TABLE = "ex04-uploads"
STATE_MACHINE = "ex04-process-upload"
TIMEOUT_SECONDS = 120

# One small file and one file that is larger than 1024 bytes.
ROWS = "".join(f"{n},item-{n},{n % 7 + 1}\n" for n in range(1, 201))
FILES = {
    "incoming/notes.txt": ("text/plain", "Buy milk\nLearn Step Functions\n"),
    "incoming/report.csv": ("text/csv", "id,item,quantity\n" + ROWS),
}

s3 = boto3.client("s3")
sfn = boto3.client("stepfunctions")
dynamodb = boto3.client("dynamodb")


def execution_arns(machine_arn):
    """Return the ARNs of all executions of the state machine."""
    paginator = sfn.get_paginator("list_executions")
    return {
        execution["executionArn"]
        for page in paginator.paginate(stateMachineArn=machine_arn)
        for execution in page["executions"]
    }


# 1. Find the state machine ARN by its name.
machines = sfn.list_state_machines()["stateMachines"]
machine_arn = next(m["stateMachineArn"] for m in machines if m["name"] == STATE_MACHINE)
old_executions = execution_arns(machine_arn)

# 2. Upload the files. Each upload sends an event to EventBridge.
for key, (content_type, text) in FILES.items():
    body = text.encode()
    s3.put_object(Bucket=BUCKET, Key=key, Body=body, ContentType=content_type)
    print(f"Uploaded {key} ({len(body)} bytes)")

# 3. Wait until one new execution for each file is finished.
print("Waiting for the executions...")
finished = {}
deadline = time.monotonic() + TIMEOUT_SECONDS
while len(finished) < len(FILES):
    if time.monotonic() > deadline:
        raise SystemExit(f"Only {len(finished)} of {len(FILES)} executions finished in time.")
    time.sleep(2)
    for arn in execution_arns(machine_arn) - old_executions - finished.keys():
        execution = sfn.describe_execution(executionArn=arn)
        if execution["status"] != "RUNNING":
            finished[arn] = execution

# Floci does not sort list_executions by date. Sort the executions here.
for execution in sorted(finished.values(), key=lambda e: e["startDate"]):
    output = json.loads(execution.get("output") or "{}")
    print(
        f"Execution {execution['name']}: {execution['status']}. "
        f"{output.get('key')} is {output.get('category')}."
    )

# 4. Read the stored items from the table.
print(f"Items in {TABLE}:")
for key in FILES:
    item = dynamodb.get_item(TableName=TABLE, Key={"object_key": {"S": key}}).get("Item")
    if item is None:
        print(f"  {key}: no item")
        continue
    print(
        f"  {key}: {item['category']['S']}, {item['size']['N']} bytes, "
        f"{item['content_type']['S']}, first line {item['first_line']['S']!r}"
    )
