terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

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

# Grant cross-domain access to specific table
resource "aws_lakeformation_permissions" "cross_domain_access" {
  principal   = var.consumer_role_arn
  permissions = ["SELECT", "DESCRIBE"]

  table {
    database_name = var.source_database_name
    name          = var.source_table_name
  }
}
