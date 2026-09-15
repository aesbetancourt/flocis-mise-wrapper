"""Exercise 01 — S3 basics. Part C.

Complete each TODO. Run inside the lab folder:
    uv run --with boto3 python app.py

The client needs no endpoint or keys. Inside the lab, boto3 reads the floci profile.
boto3 S3 reference: https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/s3.html
"""

import boto3

BUCKET = "ex01-notes"
KEY = "notes/today.txt"

s3 = boto3.client("s3")

# TODO 1: Upload two versions of KEY: first "first draft", then "final text".
#         Method: put_object

# TODO 2: List all versions of KEY. Print each version ID and mark the latest one.
#         Method: list_object_versions

# TODO 3: Read the oldest version by its version ID and print its content.
#         Method: get_object with VersionId
