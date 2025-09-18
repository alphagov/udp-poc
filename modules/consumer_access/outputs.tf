output "granted_domains" {
  value       = var.allowed_domains
  description = "Domains granted DESCRIBE on databases"
}

output "granted_non_pii" {
  value       = var.allow_non_pii_tables
  description = "Whether consumer was granted SELECT on non-PII tables"
}


