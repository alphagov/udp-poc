
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
