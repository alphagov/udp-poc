output "companion_role_arn" {
  value       = aws_iam_role.lambda_role.arn
  description = "IAM role ARN for Companion Lambda"
}

output "companion_api_url" {
  value       = aws_apigatewayv2_api.http_api.api_endpoint
  description = "Base URL of the Companion API"
}


