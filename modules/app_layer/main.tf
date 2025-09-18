terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

locals {
  lambda_name = "udp-app-settings-api"
  table_name  = var.table_name != "" ? var.table_name : "udp_app_settings"
  deploy_hash = random_string.deploy_suffix.result
}

resource "random_string" "deploy_suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "aws_dynamodb_table" "app_settings" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "user_id"
  range_key = "setting_key"

  attribute {
    name = "user_id"
    type = "S"
  }
  attribute {
    name = "setting_key"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "udp-app-settings-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    sid = "DynamoDBAccess"
    actions = [
      "dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem",
      "dynamodb:DeleteItem", "dynamodb:Query"
    ]
    resources = [aws_dynamodb_table.app_settings.arn]
  }

  statement {
    sid = "Logs"
    actions = [
      "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  statement {
    sid = "S3IngestWrite"
    actions = [
      "s3:PutObject", "s3:AbortMultipartUpload", "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::${var.bucket_name}",
      "arn:aws:s3:::${var.bucket_name}/products/${var.product_name}/*"
    ]
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name   = "udp-app-settings-lambda-policy"
  policy = data.aws_iam_policy_document.lambda_policy.json
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "null_resource" "install_runtime_deps" {
  triggers = {
    package_json_hash = filesha1("${path.module}/runtime/package.json")
  }

  provisioner "local-exec" {
    command = "cd ${path.module}/runtime && npm ci --omit=dev"
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/runtime"
  output_path = "${path.module}/build/lambda-${local.deploy_hash}.zip"
  depends_on  = [null_resource.install_runtime_deps]
}

resource "aws_lambda_function" "handler" {
  function_name    = local.lambda_name
  role             = aws_iam_role.lambda_role.arn
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = filebase64sha256(data.archive_file.lambda_zip.output_path)

  environment { variables = { TABLE_NAME = aws_dynamodb_table.app_settings.name } }
}

# Stream -> S3 ingestion lambda
data "aws_iam_policy_document" "ingest_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ingest_role" {
  name               = "udp-app-settings-ingest-role"
  assume_role_policy = data.aws_iam_policy_document.ingest_assume.json
}

data "aws_iam_policy_document" "ingest_policy" {
  statement {
    sid       = "DynamoDBStreamRead"
    actions   = ["dynamodb:DescribeStream", "dynamodb:GetRecords", "dynamodb:GetShardIterator", "dynamodb:ListStreams"]
    resources = [aws_dynamodb_table.app_settings.stream_arn]
  }

  statement {
    sid     = "S3Put"
    actions = ["s3:PutObject", "s3:AbortMultipartUpload", "s3:ListBucket"]
    resources = [
      "arn:aws:s3:::${var.bucket_name}",
      "arn:aws:s3:::${var.bucket_name}/products/${var.product_name}/*"
    ]
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_policy" "ingest_policy" {
  name   = "udp-app-settings-ingest-policy"
  policy = data.aws_iam_policy_document.ingest_policy.json
}

resource "aws_iam_role_policy_attachment" "ingest_attach" {
  role       = aws_iam_role.ingest_role.name
  policy_arn = aws_iam_policy.ingest_policy.arn
}

resource "null_resource" "install_ingest_deps" {
  triggers = {
    package_json_hash = filesha1("${path.module}/runtime/ingest/package.json")
  }

  provisioner "local-exec" {
    command = "cd ${path.module}/runtime/ingest && npm ci --omit=dev"
  }
}

data "archive_file" "ingest_zip" {
  type        = "zip"
  source_dir  = "${path.module}/runtime/ingest"
  output_path = "${path.module}/build/ingest-${local.deploy_hash}.zip"
  depends_on  = [null_resource.install_ingest_deps]
}

resource "aws_lambda_function" "ingest" {
  function_name    = "udp-app-settings-stream-ingest"
  role             = aws_iam_role.ingest_role.arn
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  filename         = data.archive_file.ingest_zip.output_path
  source_code_hash = filebase64sha256(data.archive_file.ingest_zip.output_path)

  environment {
    variables = {
      BUCKET_NAME  = var.bucket_name
      PRODUCT_NAME = var.product_name
    }
  }
}

resource "aws_lambda_event_source_mapping" "ddb_stream" {
  event_source_arn                   = aws_dynamodb_table.app_settings.stream_arn
  function_name                      = aws_lambda_function.ingest.arn
  starting_position                  = "LATEST"
  batch_size                         = 100
  maximum_batching_window_in_seconds = 5
  enabled                            = true
}

resource "aws_apigatewayv2_api" "http_api" {
  name          = "udp-app-settings-http"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.handler.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_settings" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /settings/{user_id}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "put_settings" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "PUT /settings/{user_id}/{setting_key}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}


