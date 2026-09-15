"""Exercise 04 — Event-driven. Solution for the Lambda handler.

The state machine calls handler() with {"bucket": ..., "key": ...}.
The function reads the object metadata and the first line of the object.
Step Functions uses the return value as the output of the task.
"""

import json

import boto3

# Create the client outside the handler. Warm invocations then reuse it.
# Floci sets AWS_ENDPOINT_URL in the container, so boto3 needs no endpoint.
S3 = boto3.client("s3")

# Read only the start of the object. A large object then does not fill the memory.
FIRST_BYTES = 200


def handler(event, context):
    bucket = event["bucket"]
    key = event["key"]

    head = S3.head_object(Bucket=bucket, Key=key)
    size = head["ContentLength"]

    first_line = ""
    # A range request on an empty object fails. Read only when the object has data.
    if size > 0:
        body = S3.get_object(Bucket=bucket, Key=key, Range=f"bytes=0-{FIRST_BYTES - 1}")
        text = body["Body"].read().decode("utf-8", errors="replace")
        first_line = text.splitlines()[0] if text else ""

    result = {
        "bucket": bucket,
        "key": key,
        "size": size,
        "content_type": head.get("ContentType", ""),
        "first_line": first_line,
    }

    # Lambda sends everything that the function prints to CloudWatch Logs.
    print(json.dumps(result))
    return result
