# Exercise 01 — S3 basics. Part B.
#
# Complete each TODO, then run `tofu plan` and `tofu apply`.
# Resource documentation: https://search.opentofu.org/provider/hashicorp/aws/latest

# TODO 1: Create a bucket named "ex01-notes".
#         Resource: aws_s3_bucket

# TODO 2: Turn on versioning for the bucket.
#         Resource: aws_s3_bucket_versioning

# TODO 3: Add a lifecycle rule with the ID "expire-old-versions".
#         The rule deletes old (noncurrent) versions after 30 days.
#         Resource: aws_s3_bucket_lifecycle_configuration

# TODO 4: Upload an object with the key "welcome.txt" and the content "Hello, Floci!".
#         Resource: aws_s3_object

# TODO 5: Output the bucket name as "bucket_name".
