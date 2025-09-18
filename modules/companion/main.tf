terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "bucket_name" {
  type = string
}
variable "product_name" {
  type    = string
  default = "app_settings"
}

variable "database_name" {
  type = string
}

variable "workgroup_name" {
  type = string
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "udp-companion-reader-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    sid       = "AthenaAccess"
    actions   = ["athena:StartQueryExecution", "athena:GetQueryExecution", "athena:GetQueryResults"]
    resources = ["*"]
  }

  statement {
    sid       = "GlueCatalogRead"
    actions   = ["glue:GetDatabase", "glue:GetDatabases", "glue:GetTable", "glue:GetTables"]
    resources = ["*"]
  }

  statement {
    sid       = "LakeFormationDataAccess"
    actions   = ["lakeformation:GetDataAccess"]
    resources = ["*"]
  }

  statement {
    sid     = "AthenaResultsS3"
    actions = ["s3:PutObject", "s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"]
    resources = [
      "arn:aws:s3:::${var.bucket_name}",
      "arn:aws:s3:::${var.bucket_name}/athena-results/*"
    ]
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name   = "udp-companion-reader-policy"
  policy = data.aws_iam_policy_document.lambda_policy.json
}

resource "aws_iam_role_policy_attachment" "attach" {
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

data "archive_file" "zip" {
  type        = "zip"
  source_dir  = "${path.module}/runtime"
  output_path = "${path.module}/build/companion.zip"
  depends_on  = [null_resource.install_deps]
}

resource "aws_lambda_function" "companion" {
  function_name    = "udp-companion-reader"
  role             = aws_iam_role.lambda_role.arn
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  filename         = data.archive_file.zip.output_path
  source_code_hash = filebase64sha256(data.archive_file.zip.output_path)

  environment {
    variables = {
      BUCKET_NAME    = var.bucket_name
      PRODUCT_NAME   = var.product_name
      DATABASE_NAME  = var.database_name
      WORKGROUP_NAME = var.workgroup_name
    }
  }
}

resource "aws_apigatewayv2_api" "http_api" {
  name          = "udp-companion-http"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.companion.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /companion/settings/{user_id}"
  target    = "integrations/${aws_apigatewayv2_integration.integration.id}"
}

resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.companion.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}


