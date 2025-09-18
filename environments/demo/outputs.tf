output "s3_bucket_name" {
  value       = module.core.s3_bucket_name
  description = "Core data lake bucket"
}

output "athena_workgroup_name" {
  value       = module.core.athena_workgroup_name
  description = "Athena workgroup"
}

output "app_settings" {
  value = {
    database = module.app_settings.database_name
    prefix   = module.app_settings.s3_prefix
    crawler  = module.app_settings.crawler_name
  }
  description = "App settings data product"
}

output "notifications" {
  value = {
    database = module.notifications.database_name
    prefix   = module.notifications.s3_prefix
    crawler  = module.notifications.crawler_name
  }
  description = "Notifications data product"
}

output "app_settings_api_url" {
  description = "Base URL for the App Settings API"
  value       = module.app_layer.http_api_endpoint
}

output "app_settings_table_name" {
  description = "DynamoDB table name storing app settings"
  value       = module.app_layer.dynamodb_table_name
}

output "companion_api_url" {
  description = "Companion reader API URL"
  value       = module.companion_reader.companion_api_url
}
