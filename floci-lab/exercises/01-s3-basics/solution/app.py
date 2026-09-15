"""Exercise 01 — S3 basics. Solution for Part C.

Run inside the lab folder:
    uv run --with boto3 python app.py
"""

import boto3

BUCKET = "ex01-notes"
KEY = "notes/today.txt"

s3 = boto3.client("s3")

# 1. Upload two versions of the same object.
s3.put_object(Bucket=BUCKET, Key=KEY, Body=b"first draft")
s3.put_object(Bucket=BUCKET, Key=KEY, Body=b"final text")

# 2. List all versions of the object. S3 returns the newest version first.
versions = s3.list_object_versions(Bucket=BUCKET, Prefix=KEY)["Versions"]
print(f"{KEY} has {len(versions)} versions:")
for version in versions:
    marker = "latest" if version["IsLatest"] else "old"
    print(f"  {version['VersionId']}  ({marker})")

# 3. Read the oldest version by its version ID.
oldest = versions[-1]
body = s3.get_object(Bucket=BUCKET, Key=KEY, VersionId=oldest["VersionId"])["Body"].read()
print(f"Oldest version content: {body.decode()}")
