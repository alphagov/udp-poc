variable "product_name" {
  description = "Short name of the data product/domain (e.g., orders)"
  type        = string
}

variable "bucket_name" {
  description = "Data lake S3 bucket name"
  type        = string
}

variable "lf_tag_domain_key" {
  description = "LF-tag key used for domain tag"
  type        = string
  default     = "domain"
}

variable "lf_tag_pii_key" {
  description = "LF-tag key used for pii tag"
  type        = string
  default     = "pii"
}

variable "glue_crawler_role_arn" {
  description = "IAM role ARN for Glue crawler"
  type        = string
}

variable "create_crawler" {
  description = "Whether to create a Glue crawler for this product"
  type        = bool
  default     = true
}


