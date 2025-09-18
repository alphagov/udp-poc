variable "consumer_role_arn" {
  description = "IAM role ARN for the consumer"
  type        = string
}

variable "lf_tag_pii_key" {
  description = "LF-tag key for pii"
  type        = string
  default     = "pii"
}

variable "lf_tag_domain_key" {
  description = "LF-tag key for domain"
  type        = string
  default     = "domain"
}

variable "allowed_domains" {
  description = "List of domain values consumer can access"
  type        = list(string)
  default     = []
}

variable "allow_non_pii_tables" {
  description = "Grant SELECT on tables tagged pii=false"
  type        = bool
  default     = true
}


