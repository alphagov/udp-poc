output "api_endpoint" {
  description = "API Gateway endpoint for this domain"
  value       = aws_apigatewayv2_api.http_api.api_endpoint
}

output "dynamodb_table_name" {
  description = "DynamoDB table name for this domain"
  value       = aws_dynamodb_table.domain_data.name
}

output "domain_role_arn" {
  description = "IAM role ARN for this domain's Lambda"
  value       = aws_iam_role.lambda_role.arn
}

output "companion_role_arn" {
  description = "IAM role ARN for cross-domain access (alias for domain_role_arn)"
  value       = aws_iam_role.lambda_role.arn
}

output "database_name" {
  description = "Glue database name for this domain"
  value       = aws_glue_catalog_database.domain_db.name
}

output "table_name" {
  description = "Glue table name for this domain"
  value       = aws_glue_catalog_table.domain_table.name
}
