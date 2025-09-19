variable "consumer_role_arn" {
  description = "ARN of the consumer role that will test cross-domain access"
  type        = string
}

variable "source_domain" {
  description = "Domain that owns the data (e.g., app_settings)"
  type        = string
}

variable "target_domain" {
  description = "Domain that wants to access the data (e.g., companion)"
  type        = string
}

variable "source_database_name" {
  description = "Glue database name of the source domain"
  type        = string
}

variable "source_table_name" {
  description = "Glue table name of the source domain"
  type        = string
}

variable "lf_tag_domain_key" {
  description = "LF-tag key for domain"
  type        = string
  default     = "domain"
}

variable "lf_tag_pii_key" {
  description = "LF-tag key for pii"
  type        = string
  default     = "pii"
}