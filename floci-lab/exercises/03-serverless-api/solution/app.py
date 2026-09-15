"""Exercise 03 — Serverless API. Solution for Part C.

Run inside the lab folder. Give the invoke URL as the first argument:
    uv run --with boto3 python app.py "$(tofu output -raw invoke_url)"
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


# 1. Create two notes. The API returns 201 and the new note with its ID.
note_ids = []
for text in ["Buy milk", "Learn Lambda"]:
    status, note = call("POST", "/notes", {"text": text})
    print(f"POST /notes {text!r} -> {status}, id={note.get('id')}")
    note_ids.append(note["id"])

# 2. Read each note back by its ID.
for note_id in note_ids:
    status, note = call("GET", f"/notes/{note_id}")
    print(f"GET /notes/{note_id} -> {status}, text={note.get('text')!r}")

# 3. Read a note that does not exist. The API returns 404.
status, body = call("GET", "/notes/does-not-exist")
print(f"GET /notes/does-not-exist -> {status}, message={body.get('message')!r}")

# 4. Read the table directly, without the API. The notes are in DynamoDB.
table = boto3.resource("dynamodb").Table(TABLE_NAME)
items = table.scan()["Items"]
print(f"Table {TABLE_NAME} has {len(items)} items:")
for item in sorted(items, key=lambda item: item["created_at"]):
    print(f"  {item['id']}  {item['text']}")
