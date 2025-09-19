terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Lake Formation setup for cross-domain governance
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

resource "aws_lakeformation_data_lake_settings" "main" {
  admins = [data.aws_iam_session_context.current.issuer_arn]
}

resource "aws_lakeformation_lf_tag" "domain" {
  key    = "domain"
  values = ["app_settings", "notifications", "companion"]
}

resource "aws_lakeformation_lf_tag" "pii" {
  key    = "pii"
  values = ["true", "false"]
}

# IAM roles for cross-domain access
data "aws_iam_policy_document" "assume_role_account" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_iam_role" "data_consumer" {
  name               = "udp-data-consumer"
  assume_role_policy = data.aws_iam_policy_document.assume_role_account.json
}

# Glue crawler role for domain operations
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

# Athena workgroup for cross-domain queries
resource "aws_athena_workgroup" "workgroup" {
  name = var.athena_workgroup_name

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    result_configuration {
      output_location = "s3://aws-athena-query-results-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}/"
      encryption_configuration { encryption_option = "SSE_S3" }
    }
  }
}
