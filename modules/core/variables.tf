variable "region" {
  description = "AWS region for regionalized ARNs in outputs/policies"
  type        = string
}

variable "bucket_name_prefix" {
  description = "Prefix for the data lake S3 bucket name"
  type        = string
  default     = "udp-data-lake"
}

variable "athena_workgroup_name" {
  description = "Name for the Athena workgroup"
  type        = string
  default     = "udp-demo-workgroup"
}


