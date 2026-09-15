"""Exercise 03 — Serverless API. Solution for the Lambda handler.

API Gateway (HTTP API, payload format 2.0) calls handler() for each request.
"""

import json
import os
import uuid
from datetime import datetime, timezone

import boto3

# Create the client outside the handler. Warm invocations then reuse it.
# Floci sets AWS_ENDPOINT_URL in the container, so boto3 needs no endpoint.
TABLE = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])


def handler(event, context):
    route = event["routeKey"]
    if route == "POST /notes":
        result = create_note(event)
    elif route == "GET /notes/{id}":
        result = get_note(event["pathParameters"]["id"])
    else:
        result = response(404, {"message": f"No route for {route}"})

    # Lambda sends everything that the function prints to CloudWatch Logs.
    print(json.dumps({"route": route, "status": result["statusCode"]}))
    return result


def create_note(event):
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return response(400, {"message": "The body must be JSON."})

    text = body.get("text") if isinstance(body, dict) else None
    if not isinstance(text, str) or not text.strip():
        return response(
            400, {"message": "The body must have a non-empty 'text' field."}
        )

    note = {
        "id": str(uuid.uuid4()),
        "text": text,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    TABLE.put_item(Item=note)
    return response(201, note)


def get_note(note_id):
    item = TABLE.get_item(Key={"id": note_id}).get("Item")
    if item is None:
        return response(404, {"message": f"Note {note_id} does not exist."})
    return response(200, item)


def response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
