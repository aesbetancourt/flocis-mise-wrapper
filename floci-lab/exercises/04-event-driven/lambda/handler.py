"""Exercise 04 — Event-driven. Lambda handler. Part B.

The state machine calls handler() with {"bucket": ..., "key": ...}.
Step Functions uses the return value as the output of the task.
Complete each TODO. `tofu apply` zips this file and uploads it.

boto3 S3 reference: https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/s3.html
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

    # TODO 1: Read the object metadata. Set size to ContentLength and content_type to ContentType.
    #         Method: S3.head_object
    size = 0
    content_type = ""

    # TODO 2: When size is more than 0, read the first FIRST_BYTES bytes of the object.
    #         Decode the bytes as UTF-8 and set first_line to the first line.
    #         A range request on an empty object fails. Do not read an empty object.
    #         Method: S3.get_object with Range=f"bytes=0-{FIRST_BYTES - 1}"
    first_line = ""

    result = {
        "bucket": bucket,
        "key": key,
        "size": size,
        "content_type": content_type,
        "first_line": first_line,
    }

    # Lambda sends everything that the function prints to CloudWatch Logs.
    print(json.dumps(result))
    return result
