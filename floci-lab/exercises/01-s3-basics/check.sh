#!/usr/bin/env bash
# Exercise 01 — S3 basics. Checks the emulator, not your files.
# Run: ./check.sh
source "$(dirname "$0")/../_lib/check.sh"
require_lab_env

BUCKET=ex01-notes

bucket_exists() { awsl s3api head-bucket --bucket "$BUCKET"; }

versioning_enabled() {
  [ "$(awsl s3api get-bucket-versioning --bucket "$BUCKET" --query Status --output text)" = "Enabled" ]
}

lifecycle_rule_ok() {
  local days
  days=$(awsl s3api get-bucket-lifecycle-configuration --bucket "$BUCKET" \
    --query "Rules[?ID=='expire-old-versions' && Status=='Enabled'].NoncurrentVersionExpiration.NoncurrentDays | [0]" \
    --output text)
  [ "$days" = "30" ]
}

welcome_object_ok() {
  [ "$(awsl s3 cp "s3://$BUCKET/welcome.txt" -)" = "Hello, Floci!" ]
}

today_has_two_versions() {
  local count
  count=$(awsl s3api list-object-versions --bucket "$BUCKET" --prefix notes/today.txt \
    --query 'length(Versions)' --output text)
  [ "$count" -ge 2 ]
}

section "Part B — OpenTofu"
check "Bucket $BUCKET exists" bucket_exists
check "Versioning is Enabled" versioning_enabled
check "Lifecycle rule expire-old-versions deletes old versions after 30 days" lifecycle_rule_ok
check "welcome.txt contains 'Hello, Floci!'" welcome_object_ok

section "Part C — Code"
check "notes/today.txt has at least 2 versions" today_has_two_versions

summary
