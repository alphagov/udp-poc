output "athena_workgroup_name" {
  description = "Athena workgroup name"
  value       = aws_athena_workgroup.workgroup.name
}

output "data_consumer_role_arn" {
  description = "ARN of the data consumer IAM role"
  value       = aws_iam_role.data_consumer.arn
}

output "glue_crawler_role_arn" {
  description = "ARN of the Glue crawler IAM role"
  value       = aws_iam_role.glue_crawler.arn
}

output "lf_tag_domain_key" {
  description = "Lake Formation domain LF-tag key"
  value       = aws_lakeformation_lf_tag.domain.key
}

output "lf_tag_pii_key" {
  description = "Lake Formation pii LF-tag key"
  value       = aws_lakeformation_lf_tag.pii.key
}
