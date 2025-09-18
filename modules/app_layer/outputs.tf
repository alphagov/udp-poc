output "http_api_endpoint" {
  value       = aws_apigatewayv2_api.http_api.api_endpoint
  description = "Base URL of the HTTP API"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.app_settings.name
  description = "DynamoDB table name for app settings"
}


