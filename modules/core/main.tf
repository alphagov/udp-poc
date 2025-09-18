terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "random_string" "bucket_suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "aws_s3_bucket" "data_lake" {
  bucket = "${var.bucket_name_prefix}-${random_string.bucket_suffix.result}"
}

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Allow Lake Formation service-linked role to access the bucket for governed reads
data "aws_iam_policy_document" "data_lake_bucket" {
  statement {
    sid       = "LFListBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.data_lake.arn]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/lakeformation.amazonaws.com/AWSServiceRoleForLakeFormationDataAccess"]
    }
  }

  statement {
    sid       = "LFReadObjects"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.data_lake.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/lakeformation.amazonaws.com/AWSServiceRoleForLakeFormationDataAccess"]
    }
  }
}

resource "aws_s3_bucket_policy" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  policy = data.aws_iam_policy_document.data_lake_bucket.json
}

# Lake Formation
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

resource "aws_lakeformation_data_lake_settings" "main" {
  admins = [data.aws_iam_session_context.current.issuer_arn]
}

# Register S3 bucket as a Lake Formation data location
resource "aws_lakeformation_resource" "data_lake_s3" {
  arn = aws_s3_bucket.data_lake.arn
}

resource "aws_lakeformation_lf_tag" "domain" {
  key    = "domain"
  values = ["app_settings", "notifications"]
}

resource "aws_lakeformation_lf_tag" "pii" {
  key    = "pii"
  values = ["true", "false"]
}

# IAM roles
data "aws_iam_policy_document" "assume_role_account" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_iam_role" "data_owner" {
  name               = "udp-data-owner"
  assume_role_policy = data.aws_iam_policy_document.assume_role_account.json
}

resource "aws_iam_role" "data_consumer" {
  name               = "udp-data-consumer"
  assume_role_policy = data.aws_iam_policy_document.assume_role_account.json
}

data "aws_iam_policy_document" "glue_crawler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue_crawler" {
  name               = "udp-glue-crawler-role"
  assume_role_policy = data.aws_iam_policy_document.glue_crawler_assume.json
}

data "aws_iam_policy_document" "glue_crawler_policy" {
  statement {
    sid     = "S3Access"
    actions = ["s3:ListBucket", "s3:GetObject", "s3:PutObject"]
    resources = [
      aws_s3_bucket.data_lake.arn,
      "${aws_s3_bucket.data_lake.arn}/*"
    ]
  }

  statement {
    sid = "GlueCatalog"
    actions = [
      "glue:GetDatabase", "glue:GetDatabases", "glue:GetTable", "glue:GetTables",
      "glue:CreateTable", "glue:UpdateTable", "glue:CreateDatabase",
      "glue:GetCrawler", "glue:CreateCrawler", "glue:UpdateCrawler", "glue:StartCrawler"
    ]
    resources = ["*"]
  }

  statement {
    sid = "LakeFormationPermissions"
    actions = [
      "lakeformation:GetDataAccess", "lakeformation:GrantPermissions",
      "lakeformation:ListPermissions", "lakeformation:GetResourceLFTags",
      "lakeformation:SearchTablesByLFTags"
    ]
    resources = ["*"]
  }

  statement {
    sid = "CloudWatchLogs"
    actions = [
      "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/*",
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/*:log-stream:*"
    ]
  }
}

resource "aws_iam_policy" "glue_crawler" {
  name   = "udp-glue-crawler-policy"
  policy = data.aws_iam_policy_document.glue_crawler_policy.json
}

resource "aws_iam_role_policy_attachment" "glue_crawler_inline_attach" {
  role       = aws_iam_role.glue_crawler.name
  policy_arn = aws_iam_policy.glue_crawler.arn
}

resource "aws_iam_role_policy_attachment" "glue_service_managed_attach" {
  role       = aws_iam_role.glue_crawler.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Athena
resource "aws_athena_workgroup" "workgroup" {
  name = var.athena_workgroup_name

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    result_configuration {
      output_location = "s3://${aws_s3_bucket.data_lake.bucket}/athena-results/"
      encryption_configuration { encryption_option = "SSE_S3" }
    }
  }
}

# Ensure results prefix exists
resource "aws_s3_object" "athena_results_prefix" {
  bucket       = aws_s3_bucket.data_lake.id
  key          = "athena-results/"
  content      = ""
  content_type = "application/x-directory"
}


