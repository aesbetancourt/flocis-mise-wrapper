"""Exercise 03 — Serverless API. Lambda handler. Part B.

API Gateway (HTTP API, payload format 2.0) calls handler() for each request.
Complete each TODO. `tofu apply` zips this file and uploads it.

Event format: https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-lambda.html
boto3 Table reference: https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/dynamodb/table/index.html
"""

import json
import os
import uuid
from datetime import datetime, timezone

import boto3

# TODO 1: Create a Table object for the table name in the TABLE_NAME environment variable.
#         Create it here, outside the handler. Warm invocations then reuse it.
#         Method: boto3.resource("dynamodb").Table(...)
TABLE = None


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
    # TODO 2: Read the JSON request body from event["body"].
    #         Return 400 when the body has no "text" field.
    #         Make a note with "id" (uuid4 as a string), "text", and "created_at" (UTC, ISO 8601).
    #         Save the note with TABLE.put_item. Return 201 and the note.
    return response(501, {"message": "TODO 2 is not complete."})


def get_note(note_id):
    # TODO 3: Read the note with TABLE.get_item.
    #         Return 404 when the result has no "Item" key.
    #         Return 200 and the item when it exists.
    return response(501, {"message": "TODO 3 is not complete."})


def response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
