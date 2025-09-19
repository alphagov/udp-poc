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

# Athena data source connector for DynamoDB
resource "aws_athena_data_catalog" "dynamodb" {
  name        = "${var.domain_name}_dynamodb_catalog"
  description = "Data catalog for ${var.domain_name} DynamoDB table"
  type        = "LAMBDA"

  parameters = {
    "function" = aws_lambda_function.data_source_connector.arn
  }
}

# Lambda function for DynamoDB data source connector
resource "aws_lambda_function" "data_source_connector" {
  function_name    = "${var.domain_name}-dynamodb-connector"
  role             = aws_iam_role.data_source_connector_role.arn
  runtime          = "python3.9"
  handler          = "index.handler"
  filename         = data.archive_file.data_source_connector_zip.output_path
  source_code_hash = data.archive_file.data_source_connector_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.domain_data.name
    }
  }
}

# IAM role for data source connector Lambda
resource "aws_iam_role" "data_source_connector_role" {
  name = "${var.domain_name}-data-source-connector-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for data source connector
resource "aws_iam_role_policy" "data_source_connector_policy" {
  name = "${var.domain_name}-data-source-connector-policy"
  role = aws_iam_role.data_source_connector_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.domain_data.arn
      }
    ]
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "data_source_connector_basic" {
  role       = aws_iam_role.data_source_connector_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Create the data source connector Lambda code
resource "local_file" "data_source_connector_code" {
  filename = "${path.module}/data_source_connector/index.py"
  content  = <<-EOF
import json
import boto3
import os

dynamodb = boto3.client('dynamodb')
table_name = os.environ['DYNAMODB_TABLE_NAME']

def handler(event, context):
    """
    Athena data source connector for DynamoDB
    """
    try:
        # Get table schema
        response = dynamodb.describe_table(TableName=table_name)
        table_info = response['Table']
        
        # Scan the table to get sample data
        scan_response = dynamodb.scan(
            TableName=table_name,
            Limit=100
        )
        
        # Return data in Athena-compatible format
        return {
            'statusCode': 200,
            'body': json.dumps({
                'table_name': table_name,
                'items': scan_response.get('Items', []),
                'schema': {
                    'user_id': 'S',
                    'setting_key': 'S',
                    'value': 'S',
                    'updated_at': 'S'
                }
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
}

# Zip the data source connector code
data "archive_file" "data_source_connector_zip" {
  type        = "zip"
  source_file = local_file.data_source_connector_code.filename
  output_path = "${path.module}/build/data_source_connector.zip"
}

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

# Lake Formation permissions - data source catalog access
resource "aws_lakeformation_permissions" "data_catalog_access" {
  principal   = aws_lambda_function.data_source_connector.role
  permissions = ["SELECT", "DESCRIBE"]

  table {
    database_name = aws_glue_catalog_database.domain_db.name
    name          = aws_glue_catalog_table.domain_table.name
  }
}
