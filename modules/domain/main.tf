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

variable "domain_name" {
  description = "Name of the data domain (e.g., app_settings, notifications)"
  type        = string
}

variable "lf_tag_domain_key" {
  description = "Lake Formation domain tag key"
  type        = string
}

variable "lf_tag_pii_key" {
  description = "Lake Formation PII tag key"
  type        = string
}

variable "glue_crawler_role_arn" {
  description = "IAM role ARN for Glue operations"
  type        = string
}

locals {
  table_name = "udp_${var.domain_name}"
  api_name   = "udp-${var.domain_name}-api"
}

# Domain's own DynamoDB table
resource "aws_dynamodb_table" "domain_data" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "user_id"
  range_key = "item_key"

  attribute {
    name = "user_id"
    type = "S"
  }
  attribute {
    name = "item_key"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
}

# Domain API Gateway + Lambda
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
  name               = "udp-${var.domain_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    sid = "DynamoDBAccess"
    actions = [
      "dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem",
      "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:Scan"
    ]
    resources = [aws_dynamodb_table.domain_data.arn]
  }

  statement {
    sid = "Logs"
    actions = [
      "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name   = "udp-${var.domain_name}-lambda-policy"
  policy = data.aws_iam_policy_document.lambda_policy.json
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "null_resource" "install_deps" {
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
  output_path = "${path.module}/build/lambda.zip"
  depends_on  = [null_resource.install_deps]
}

resource "aws_lambda_function" "domain_api" {
  function_name    = local.api_name
  role             = aws_iam_role.lambda_role.arn
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME  = aws_dynamodb_table.domain_data.name
      DOMAIN_NAME = var.domain_name
    }
  }
}

resource "aws_apigatewayv2_api" "http_api" {
  name          = "udp-${var.domain_name}-http"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.domain_api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_items" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /{user_id}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "put_item" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "PUT /{user_id}/{item_key}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.domain_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

# Simplified approach: Use Glue tables directly with DynamoDB connection
# This avoids the complexity of Athena data source connectors

# Data source connectors removed - using Glue tables directly

data "aws_region" "current" {}

# Glue table representing the DynamoDB data
resource "aws_glue_catalog_table" "domain_table" {
  name          = "${var.domain_name}_data"
  database_name = aws_glue_catalog_database.domain_db.name

  table_type = "EXTERNAL_TABLE"
  parameters = {
    classification = "dynamodb"
    EXTERNAL       = "TRUE"
  }

  storage_descriptor {
    location = "dynamodb://${aws_dynamodb_table.domain_data.name}"

    ser_de_info {
      name                  = "dynamodb"
      serialization_library = "org.apache.hadoop.hive.dynamodb.DynamoDBSerDe"
      parameters = {
        "dynamodb.table.name"     = aws_dynamodb_table.domain_data.name
        "dynamodb.column.mapping" = "user_id:user_id,item_key:item_key,value:value,updated_at:updated_at"
      }
    }

    columns {
      name = "user_id"
      type = "string"
    }
    columns {
      name = "item_key"
      type = "string"
    }
    columns {
      name = "value"
      type = "string"
    }
    columns {
      name = "updated_at"
      type = "timestamp"
    }
  }
}

# Glue database for this domain
resource "aws_glue_catalog_database" "domain_db" {
  name = "${var.domain_name}_domain"
}

# Tag the database and table for Lake Formation governance
resource "aws_lakeformation_resource_lf_tag" "db_domain_tag" {
  database {
    name = aws_glue_catalog_database.domain_db.name
  }
  lf_tag {
    key   = var.lf_tag_domain_key
    value = var.domain_name
  }
}

resource "aws_lakeformation_resource_lf_tag" "table_domain_tag" {
  table {
    database_name = aws_glue_catalog_database.domain_db.name
    name          = aws_glue_catalog_table.domain_table.name
  }
  lf_tag {
    key   = var.lf_tag_domain_key
    value = var.domain_name
  }
}

resource "aws_lakeformation_resource_lf_tag" "table_pii_tag" {
  table {
    database_name = aws_glue_catalog_database.domain_db.name
    name          = aws_glue_catalog_table.domain_table.name
  }
  lf_tag {
    key   = var.lf_tag_pii_key
    value = "false"
  }
}

# Lake Formation permissions - domain owner has full access to their own data
resource "aws_lakeformation_permissions" "domain_owner_access" {
  principal   = aws_iam_role.lambda_role.arn
  permissions = ["SELECT", "DESCRIBE"]

  table {
    database_name = aws_glue_catalog_database.domain_db.name
    name          = aws_glue_catalog_table.domain_table.name
  }
}

