# Exercise 01 — S3 basics. Solution.

resource "aws_s3_bucket" "notes" {
  bucket = "ex01-notes"

  # Lets `tofu destroy` delete the bucket while it still holds objects and old
  # versions. Part C adds objects that OpenTofu does not manage. Use this in
  # labs only: on a real account it deletes data without a second question.
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "notes" {
  bucket = aws_s3_bucket.notes.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "notes" {
  bucket = aws_s3_bucket.notes.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  # On real AWS, a rule for old versions can fail before versioning is active.
  # Floci does not need this, but the provider docs recommend it.
  depends_on = [aws_s3_bucket_versioning.notes]
}

resource "aws_s3_object" "welcome" {
  bucket  = aws_s3_bucket.notes.id
  key     = "welcome.txt"
  content = "Hello, Floci!"

  depends_on = [aws_s3_bucket_versioning.notes]
}

output "bucket_name" {
  value = aws_s3_bucket.notes.id
}
