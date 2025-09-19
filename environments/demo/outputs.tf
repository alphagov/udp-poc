output "athena_workgroup_name" {
  value       = module.core.athena_workgroup_name
  description = "Athena workgroup for cross-domain queries"
}

output "app_settings_api_url" {
  description = "App Settings domain API URL"
  value       = module.app_settings.api_endpoint
}

output "app_settings_table_name" {
  description = "App Settings DynamoDB table name"
  value       = module.app_settings.dynamodb_table_name
}

output "notifications_api_url" {
  description = "Notifications domain API URL"
  value       = module.notifications.api_endpoint
}

output "notifications_table_name" {
  description = "Notifications DynamoDB table name"
  value       = module.notifications.dynamodb_table_name
}

output "companion_api_url" {
  description = "Companion domain API URL"
  value       = module.companion.api_endpoint
}

output "companion_table_name" {
  description = "Companion DynamoDB table name"
  value       = module.companion.dynamodb_table_name
}
