"""Exercise 04 — Event-driven. Part C.

Complete each TODO. Run inside the lab folder:
    uv run --with boto3 python app.py

The clients need no endpoint or keys. Inside the lab, boto3 reads the floci profile.
boto3 S3 reference: https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/s3.html
boto3 Step Functions reference: https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/stepfunctions.html
boto3 DynamoDB reference: https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/dynamodb.html
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


# TODO 1: Find the ARN of the state machine with the name STATE_MACHINE.
#         Then keep the ARNs of the executions that exist now: old_executions = execution_arns(machine_arn)
#         Method: sfn.list_state_machines

# TODO 2: Upload each file in FILES under its key. Set the ContentType. Print the key and the size.
#         Method: s3.put_object

# TODO 3: Wait until one new execution for each file is not RUNNING. Stop after TIMEOUT_SECONDS.
#         New executions are in execution_arns(machine_arn) but not in old_executions.
#         Print the name and the status of each execution.
#         Print "key" and "category" from its output. The output is a JSON string.
#         Method: sfn.describe_execution

# TODO 4: Read the item of each key in FILES from TABLE. The hash key is "object_key".
#         Print the category, the size, the content type, and the first line.
#         Method: dynamodb.get_item
