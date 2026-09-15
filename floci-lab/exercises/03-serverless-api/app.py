"""Exercise 03 — Serverless API. Part C.

Complete each TODO. Run inside the lab folder. Give the invoke URL as the first argument:
    uv run --with boto3 python app.py "$(tofu output -raw invoke_url)"

call() sends HTTP requests with urllib from the Python standard library.
boto3 needs no endpoint or keys. Inside the lab, boto3 reads the floci profile.
boto3 Table reference: https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/dynamodb/table/index.html
"""

import json
import sys
import urllib.error
import urllib.request

import boto3

TABLE_NAME = "ex03-notes"

if len(sys.argv) != 2:
    sys.exit(
        'Usage: uv run --with boto3 python app.py "$(tofu output -raw invoke_url)"'
    )
API_URL = sys.argv[1].rstrip("/")


def call(method, path, body=None):
    """Send one HTTP request to the API. Return the status code and the JSON body."""
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(
        API_URL + path,
        data=data,
        method=method,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as error:
        # urllib raises an error for 4xx and 5xx. The body is still JSON.
        return error.code, json.loads(error.read())


# TODO 1: Create two notes with the texts "Buy milk" and "Learn Lambda".
#         Print the status code and the ID of each note. Keep the IDs.
#         Example: status, note = call("POST", "/notes", {"text": "Buy milk"})

# TODO 2: Read each note back by its ID. Print the status code and the text.
#         Example: status, note = call("GET", f"/notes/{note_id}")

# TODO 3: Read the note with the ID "does-not-exist". Print the status code.

# TODO 4: Read all items from the table directly, without the API.
#         Print the ID and the text of each item.
#         Method: boto3.resource("dynamodb").Table(TABLE_NAME).scan()
