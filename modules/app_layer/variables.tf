variable "table_name" {
  description = "Optional override for DynamoDB table name"
  type        = string
  default     = ""
}

variable "bucket_name" {
  description = "Data lake S3 bucket to land change events"
  type        = string
}

variable "product_name" {
  description = "Domain/product name for S3 prefix (e.g., app_settings)"
  type        = string
  default     = "app_settings"
}


