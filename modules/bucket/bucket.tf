# creates a (private) bucket by default
resource "aws_s3_bucket" "bucket" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy  # when destroying this resource, this will delete all objects in the bucket

  tags = {
    Name = local.bucket_name
  }
}

# Provides a resource to manage S3 Bucket Ownership Controls
resource "aws_s3_bucket_ownership_controls" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Provides an S3 bucket ACL resource (private)
resource "aws_s3_bucket_acl" "bucket" {
  depends_on = [aws_s3_bucket_ownership_controls.bucket]
  bucket     = aws_s3_bucket.bucket.id
  acl        = "private"
}

# Provides server side encryption of the bucket (AES256)
resource "aws_s3_bucket_server_side_encryption_configuration" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Disable bucket versioning
resource "aws_s3_bucket_versioning" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  versioning_configuration {
    status = "Disabled"
  }
}

# Manages S3 bucket-level Public Access Block configuration.
# all true means block all public access
resource "aws_s3_bucket_public_access_block" "bucket" {
  bucket                  = aws_s3_bucket.bucket.id
  block_public_acls       = true  # default (false) Whether Amazon S3 should block public ACLs for this bucket.
  block_public_policy     = true
  # default (false) Whether Amazon S3 should block public bucket policies for this bucket.
  ignore_public_acls      = true # default (false) Whether Amazon S3 should ignore public ACLs for this bucket.
  restrict_public_buckets = true
  # default (false) Whether Amazon S3 should restrict public bucket policies for this bucket.
}

# Provides an S3 Intelligent-Tiering configuration resource
# it works as follows (default)
# - Frequent Access tier (automatic): This is the default access tier that any object created or transitioned to S3 Intelligent-Tiering
# begins its lifecycle in. An object remains in this tier as long as it is being accessed. The Frequent Access tier provides low latency
# and high throughput performance.
# - Infrequent Access tier (automatic): If an object is not accessed for 30 consecutive days, the object moves to the Infrequent Access tier.
# The Infrequent Access tier provides low latency and high throughput performance.
# - Archive Instant Access tier (automatic): If an object is not accessed for 90 consecutive days, the object moves to the
# Archive Instant Access tier. The Archive Instant Access tier provides low latency and high throughput performance.
resource "aws_s3_bucket_intelligent_tiering_configuration" "entire_bucket" {
  bucket = aws_s3_bucket.bucket.id
  name   = "${local.bucket_name}-entire-bucket"
  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = var.intelligent_tiering_days
  }
}
